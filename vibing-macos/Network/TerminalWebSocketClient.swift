//
//  TerminalWebSocketClient.swift
//  VibeTerminal
//
//  完整的 WebSocket 客户端实现 - 与 vibe-terminal-server 通信
//
//  功能：
//  - URLSessionWebSocketTask 连接管理
//  - 二进制协议帧编码/解码
//  - 自动重连机制
//  - 心跳检测
//  - 会话管理
//
//  协议格式：
//  - [1字节] 帧类型标记
//  - [4字节] 数据长度 (小端序)
//  - [N字节] 数据内容
//

import Foundation
import Combine

// MARK: - 连接状态

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(Int)  // 带重连次数
    case failed(Error)

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.reconnecting(let a), .reconnecting(let b)):
            return a == b
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

// MARK: - 终端会话信息

struct TerminalSession: Identifiable, Equatable {
    let id: String
    let command: String
    let isActive: Bool
    let createdAt: Date
    var lastActivity: Date

    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        lhs.id == rhs.id && lhs.isActive == rhs.isActive
    }
}

// MARK: - 客户端委托协议

protocol TerminalWebSocketClientDelegate: AnyObject {
    /// 连接状态改变
    func client(_ client: TerminalWebSocketClient, didChangeState state: ConnectionState)

    /// 接收到会话输出
    func client(_ client: TerminalWebSocketClient, didReceiveOutput frame: ScreenFrame, forSession sessionId: String)

    /// 光标更新
    func client(_ client: TerminalWebSocketClient, didUpdateCursor cursor: CursorFrame, forSession sessionId: String)

    /// 模式更新
    func client(_ client: TerminalWebSocketClient, didUpdateMode mode: ModeFrame, forSession sessionId: String)

    /// 会话创建
    func client(_ client: TerminalWebSocketClient, didCreateSession sessionId: String)

    /// 会话关闭
    func client(_ client: TerminalWebSocketClient, didCloseSession sessionId: String)

    /// 接收错误
    func client(_ client: TerminalWebSocketClient, didReceiveError error: Error)

    /// 接收到原始 PTY 输出（SwiftTerm 模式）
    func client(_ client: TerminalWebSocketClient, didReceiveRawOutput data: Data, forSession sessionId: String)
}

// MARK: - 扩展委托协议 - 提供默认实现

extension TerminalWebSocketClientDelegate {
    func client(_ client: TerminalWebSocketClient, didChangeState state: ConnectionState) {}
    func client(_ client: TerminalWebSocketClient, didReceiveOutput frame: ScreenFrame, forSession sessionId: String) {}
    func client(_ client: TerminalWebSocketClient, didUpdateCursor cursor: CursorFrame, forSession sessionId: String) {}
    func client(_ client: TerminalWebSocketClient, didUpdateMode mode: ModeFrame, forSession sessionId: String) {}
    func client(_ client: TerminalWebSocketClient, didCreateSession sessionId: String) {}
    func client(_ client: TerminalWebSocketClient, didCloseSession sessionId: String) {}
    func client(_ client: TerminalWebSocketClient, didReceiveError error: Error) {}
    func client(_ client: TerminalWebSocketClient, didReceiveRawOutput data: Data, forSession sessionId: String) {}
}

// MARK: - 客户端错误

enum TerminalClientError: Error, LocalizedError {
    case notConnected
    case invalidURL(String)
    case sendFailed(Error)
    case connectionTimeout
    case handshakeFailed(String)
    case encodeFailed(String)
    case decodeFailed(String)
    case sessionNotFound(String)
    case maxReconnectAttemptsReached

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .sendFailed(let error):
            return "Send failed: \(error.localizedDescription)"
        case .connectionTimeout:
            return "Connection timeout"
        case .handshakeFailed(let reason):
            return "Handshake failed: \(reason)"
        case .encodeFailed(let reason):
            return "Encode failed: \(reason)"
        case .decodeFailed(let reason):
            return "Decode failed: \(reason)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .maxReconnectAttemptsReached:
            return "Max reconnect attempts reached"
        }
    }
}

// MARK: - 客户端配置

struct TerminalClientConfig {
    /// 连接超时时间（秒）
    var connectionTimeout: TimeInterval = 10

    /// 心跳间隔（秒）
    var heartbeatInterval: TimeInterval = 30

    /// 心跳超时时间（秒）
    var heartbeatTimeout: TimeInterval = 60

    /// 自动重连
    var autoReconnect: Bool = true

    /// 重连基础延迟（秒）
    var reconnectBaseDelay: TimeInterval = 1

    /// 重连最大延迟（秒）
    var reconnectMaxDelay: TimeInterval = 30

    /// 最大重连次数（0 表示无限）
    var maxReconnectAttempts: Int = 0

    /// 接收缓冲区大小
    var receiveBufferSize: Int = 1024 * 1024  // 1MB

    static let `default` = TerminalClientConfig()
}

// MARK: - 主客户端类

final class TerminalWebSocketClient: NSObject {

    // MARK: - Published Properties (for SwiftUI)

    @Published private(set) var connectionState: ConnectionState = .disconnected

    // MARK: - Private Properties

    private let serverURL: URL
    private let config: TerminalClientConfig

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?

    private let stateQueue = DispatchQueue(label: "com.vibeterminal.client.state", qos: .userInitiated)
    private let sendQueue = DispatchQueue(label: "com.vibeterminal.client.send", qos: .userInitiated)
    private let receiveQueue = DispatchQueue(label: "com.vibeterminal.client.receive", qos: .userInitiated)

    private var receiveBuffer = Data()
    private var heartbeatTimer: Timer?
    private var lastPongTime = Date()

    private var reconnectAttempts = 0
    private var isReconnecting = false

    // 会话管理
    private var activeSessions: [String: TerminalSession] = [:]
    private var subscribedSessions = Set<String>()

    // 待发送队列（连接断开时缓存）
    private var pendingFrames: [Frame] = []

    // 会话创建回调
    private var sessionCreationContinuations: [String: CheckedContinuation<String, Error>] = [:]

    // MARK: - Delegate

    weak var delegate: TerminalWebSocketClientDelegate?
    private let delegateQueue = DispatchQueue.main

    // MARK: - Initialization

    init(serverURL: URL, config: TerminalClientConfig = .default) {
        self.serverURL = serverURL
        self.config = config

        super.init()

        setupURLSession()
    }

    convenience init?(urlString: String, config: TerminalClientConfig = .default) {
        guard let url = URL(string: urlString) else {
            return nil
        }
        self.init(serverURL: url, config: config)
    }

    deinit {
        disconnect()
    }

    // MARK: - Setup

    private func setupURLSession() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.connectionTimeout
        configuration.timeoutIntervalForResource = config.connectionTimeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldUsePipelining = true

        let operationQueue = OperationQueue()
        operationQueue.name = "com.vibeterminal.client.urlsession"
        operationQueue.underlyingQueue = receiveQueue

        session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: operationQueue
        )
    }

    // MARK: - Connection Management

    /// 连接到服务器
    func connect() {
        stateQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.connectionState != .connected &&
                  self.connectionState != .connecting else {
                return
            }

            self.updateState(.connecting)

            guard let session = self.session else {
                self.updateState(.failed(TerminalClientError.notConnected))
                return
            }

            let task = session.webSocketTask(with: self.serverURL)
            task.priority = URLSessionTask.highPriority
            self.webSocketTask = task
            task.resume()

            // 启动接收循环
            self.receiveLoop()

            // 启动连接超时检测
            self.scheduleConnectionTimeout()
        }
    }

    /// 断开连接
    func disconnect() {
        stateQueue.async { [weak self] in
            guard let self = self else { return }

            self.isReconnecting = false
            self.reconnectAttempts = 0
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil

            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.webSocketTask = nil

            self.updateState(.disconnected)
        }
    }

    /// 强制重新连接
    func reconnect() {
        stateQueue.async { [weak self] in
            guard let self = self else { return }

            // 取消当前连接
            self.webSocketTask?.cancel()

            // 重置状态
            self.isReconnecting = true
            self.reconnectAttempts += 1

            // 检查最大重连次数
            if self.config.maxReconnectAttempts > 0 &&
               self.reconnectAttempts > self.config.maxReconnectAttempts {
                self.updateState(.failed(TerminalClientError.maxReconnectAttemptsReached))
                self.isReconnecting = false
                self.reconnectAttempts = 0
                return
            }

            self.updateState(.reconnecting(self.reconnectAttempts))

            // 计算延迟（指数退避）
            let delay = min(
                self.config.reconnectBaseDelay * pow(2.0, Double(self.reconnectAttempts - 1)),
                self.config.reconnectMaxDelay
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.connect()
            }
        }
    }

    // MARK: - Session Management

    /// 创建新的终端会话 - 通过 JSON 文本消息（服务端只接受 JSON 格式的 create_session）
    func createSession(request: CreateSessionRequest) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: TerminalClientError.notConnected)
                    return
                }

                let requestId = UUID().uuidString
                self.sessionCreationContinuations[requestId] = continuation

                // 构建 JSON 文本消息（Rust 服务端 handle_protocol_message 处理）
                var jsonDict: [String: Any] = [
                    "type": "create_session",
                    "command": request.command,
                    "args": request.args,
                    "cols": request.cols,
                    "rows": request.rows,
                ]
                if let cwd = request.cwd {
                    jsonDict["cwd"] = cwd
                }

                Task { [weak self] in
                    guard let self = self, let task = self.webSocketTask else {
                        self?.sessionCreationContinuations.removeValue(forKey: requestId)
                        continuation.resume(throwing: TerminalClientError.notConnected)
                        return
                    }

                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
                        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                        try await task.send(.string(jsonString))

                        // 超时检测
                        Task {
                            try? await Task.sleep(nanoseconds: UInt64(self.config.connectionTimeout * 1_000_000_000))
                            self.stateQueue.async {
                                if let cont = self.sessionCreationContinuations.removeValue(forKey: requestId) {
                                    cont.resume(throwing: TerminalClientError.connectionTimeout)
                                }
                            }
                        }
                    } catch {
                        self.stateQueue.async {
                            self.sessionCreationContinuations.removeValue(forKey: requestId)
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// 创建 Shell 会话
    func createShellSession(cwd: String? = nil) async throws -> String {
        var request = CreateSessionRequest.shell()
        if let cwd = cwd {
            request = request.withCwd(cwd)
        }
        return try await createSession(request: request)
    }

    /// 创建命令会话
    func createCommandSession(_ command: String, args: [String] = [], cwd: String? = nil) async throws -> String {
        var request = CreateSessionRequest.command(command, args: args)
        if let cwd = cwd {
            request = request.withCwd(cwd)
        }
        return try await createSession(request: request)
    }

    /// 订阅会话输出
    func subscribe(toSessionIds sessionIds: [String]) async throws {
        try await sendFrame(.subscribe(sessionIds))
        stateQueue.async {
            sessionIds.forEach { self.subscribedSessions.insert($0) }
        }
    }

    /// 发送输入数据到会话
    func sendInput(_ data: Data, toSession sessionId: String) async throws {
        try await sendFrame(.input(sessionId: sessionId, data: data))
    }

    /// 发送文本输入到会话
    func sendText(_ text: String, toSession sessionId: String) async throws {
        guard let data = text.data(using: .utf8) else {
            throw TerminalClientError.encodeFailed("Failed to encode text")
        }
        try await sendInput(data, toSession: sessionId)
    }

    /// 发送按键到会话
    func sendKey(_ key: KeyCode, toSession sessionId: String) async throws {
        let data = key.encode()
        try await sendInput(data, toSession: sessionId)
    }

    /// 发送 JSON 文本消息（直接与服务端 JSON 处理器兼容）
    /// 发送原始 JSON 文本（用于 relay 命令等）
    func sendRawText(_ text: String) async throws {
        guard let task = webSocketTask else {
            throw TerminalClientError.notConnected
        }
        return try await withCheckedThrowingContinuation { continuation in
            task.send(.string(text)) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func sendJsonText(type: String, payload: [String: Any]) async throws {
        guard let task = webSocketTask else {
            throw TerminalClientError.notConnected
        }
        var json = payload
        json["type"] = type
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        // 使用 completion handler 方式发送（比 async/await 更可靠）
        return try await withCheckedThrowingContinuation { continuation in
            task.send(.string(jsonString)) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// 调整会话终端大小
    func resizeSession(sessionId: String, cols: UInt16, rows: UInt16) async throws {
        try await sendFrame(.resizeSession(sessionId: sessionId, cols: cols, rows: rows))
    }

    /// 关闭会话
    func closeSession(sessionId: String) async throws {
        try await sendFrame(.closeSession(sessionId: sessionId))
        stateQueue.async {
            self.subscribedSessions.remove(sessionId)
            self.activeSessions.removeValue(forKey: sessionId)
        }
    }

    /// 获取活动会话列表
    func getActiveSessions() -> [TerminalSession] {
        return stateQueue.sync {
            Array(activeSessions.values).sorted { $0.createdAt < $1.createdAt }
        }
    }

    // MARK: - Frame Sending

    private func sendFrame(_ frame: Frame) async throws {
        guard let webSocketTask = webSocketTask else {
            throw TerminalClientError.notConnected
        }

        // 编码帧
        let data = encodeFrame(frame)

        return try await withCheckedThrowingContinuation { continuation in
            sendQueue.async { [weak self, weak webSocketTask] in
                guard let self = self, let task = webSocketTask else {
                    continuation.resume(throwing: TerminalClientError.notConnected)
                    return
                }

                let message = URLSessionWebSocketTask.Message.data(data)

                task.send(message) { [weak self] error in
                    if let error = error {
                        // 如果发送失败且断开连接，加入待发送队列
                        if self?.connectionState != .connected {
                            self?.stateQueue.async {
                                self?.pendingFrames.append(frame)
                            }
                        }
                        continuation.resume(throwing: TerminalClientError.sendFailed(error))
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        lastPongTime = Date()

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: config.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
            self?.checkHeartbeatTimeout()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func sendPing() {
        Task { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }

            do {
                try await self.sendFrame(.ping)
            } catch {
                print("Failed to send ping: \(error)")
            }
        }
    }

    private func checkHeartbeatTimeout() {
        let elapsed = Date().timeIntervalSince(lastPongTime)
        if elapsed > config.heartbeatTimeout {
            print("Heartbeat timeout after \(elapsed)s")

            delegateQueue.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.client(self, didReceiveError: TerminalClientError.connectionTimeout)
            }

            disconnect()

            if config.autoReconnect {
                reconnect()
            }
        }
    }

    // MARK: - Connection Timeout

    private func scheduleConnectionTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + config.connectionTimeout) { [weak self] in
            guard let self = self else { return }

            let currentState = self.stateQueue.sync { self.connectionState }

            guard currentState == .connecting else { return }

            print("Connection timeout")

            self.stateQueue.async {
                self.webSocketTask?.cancel()
                self.webSocketTask = nil
                self.updateState(.failed(TerminalClientError.connectionTimeout))

                if self.config.autoReconnect {
                    self.reconnect()
                }
            }
        }
    }

    // MARK: - Receive Loop

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)

                // 继续接收
                let shouldContinue = self.stateQueue.sync { self.connectionState == .connected }
                if shouldContinue {
                    self.receiveLoop()
                }

            case .failure(let error):
                print("Receive error: \(error)")

                self.stateQueue.async {
                    self.updateState(.disconnected)
                }

                self.delegateQueue.async {
                    self.delegate?.client(self, didReceiveError: error)
                }

                // 处理重连
                if self.config.autoReconnect {
                    self.reconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleTextMessage(text)

        case .data(let data):
            handleBinaryMessage(data)

        @unknown default:
            break
        }
    }

    private func handleTextMessage(_ text: String) {
        // 检查是否为 relay 状态消息（JSON 文本）
        if let jsonData = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let type = json["type"] as? String,
           type.hasPrefix("relay_") {
            RelaySessionManager.shared.handleRelayMessage(json)
            return
        }

        guard let data = text.data(using: .utf8) else { return }
        handleBinaryMessage(data)
    }

    private func handleBinaryMessage(_ data: Data) {
        receiveBuffer.append(data)

        // 限制缓冲区大小
        if receiveBuffer.count > config.receiveBufferSize {
            receiveBuffer.removeAll()
            delegateQueue.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.client(self, didReceiveError: TerminalClientError.decodeFailed("Buffer overflow"))
            }
            return
        }

        // 解码多个帧
        let (frames, remaining) = decodeFrames(receiveBuffer)
        receiveBuffer = remaining

        // 处理每个帧
        for frame in frames {
            handleFrame(frame)
        }
    }

    private func handleFrame(_ frame: Frame) {
        switch frame {
        case .pong:
            lastPongTime = Date()

        case .sessionCreated(let sessionId):
            handleSessionCreated(sessionId)

        case .sessionClosed(let sessionId):
            handleSessionClosed(sessionId)

        case .sessionOutput(let sessionId, let screenFrame):
            handleSessionOutput(sessionId, frame: screenFrame)

        case .cursorUpdate(let cursorFrame):
            handleCursorUpdate(cursorFrame)

        case .modeUpdate(let modeFrame):
            handleModeUpdate(modeFrame)

        case .error(let message):
            handleError(message)

        case .rawOutput(let sessionId, let data):
            handleRawOutput(sessionId, data: data)

        default:
            break
        }
    }

    private func handleRawOutput(_ sessionId: String, data: Data) {
        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.client(self, didReceiveRawOutput: data, forSession: sessionId)
        }
    }

    private func handleSessionCreated(_ sessionId: String) {
        stateQueue.async {
            // 创建会话记录
            let session = TerminalSession(
                id: sessionId,
                command: "shell",
                isActive: true,
                createdAt: Date(),
                lastActivity: Date()
            )
            self.activeSessions[sessionId] = session
        }

        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.client(self, didCreateSession: sessionId)
        }

        // 恢复所有待发送的回调（使用第一个匹配的）
        stateQueue.async {
            if let continuation = self.sessionCreationContinuations.popFirst() {
                continuation.value.resume(returning: sessionId)
            }
        }
    }

    private func handleSessionClosed(_ sessionId: String) {
        stateQueue.async {
            self.activeSessions.removeValue(forKey: sessionId)
            self.subscribedSessions.remove(sessionId)
        }

        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.client(self, didCloseSession: sessionId)
        }
    }

    private func handleSessionOutput(_ sessionId: String, frame: ScreenFrame) {
        stateQueue.async {
            if var session = self.activeSessions[sessionId] {
                session.lastActivity = Date()
                self.activeSessions[sessionId] = session
            }
        }

        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.client(self, didReceiveOutput: frame, forSession: sessionId)
        }
    }

    private func handleCursorUpdate(_ cursor: CursorFrame) {
        // 光标更新通常附带会话信息，这里简化处理
        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            // 使用默认会话 ID，实际应该从帧中获取
            self.delegate?.client(self, didUpdateCursor: cursor, forSession: "")
        }
    }

    private func handleModeUpdate(_ mode: ModeFrame) {
        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.client(self, didUpdateMode: mode, forSession: "")
        }
    }

    private func handleError(_ message: String) {
        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            let error = TerminalClientError.handshakeFailed(message)
            self.delegate?.client(self, didReceiveError: error)
        }
    }

    // MARK: - State Management

    private func updateState(_ newState: ConnectionState) {
        let oldState = connectionState
        connectionState = newState

        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.client(self, didChangeState: newState)
        }

        // 状态转换处理
        switch (oldState, newState) {
        case (_, .connected):
            startHeartbeat()
            flushPendingFrames()

        case (.connected, _):
            stopHeartbeat()

        default:
            break
        }
    }

    /// Must be called from stateQueue context (called by updateState which runs on stateQueue)
    private func flushPendingFrames() {
        // Already on stateQueue — access directly without sync
        let frames = pendingFrames
        pendingFrames.removeAll()

        guard !frames.isEmpty else { return }

        Task {
            for frame in frames {
                try? await sendFrame(frame)
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension TerminalWebSocketClient: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocolString: String?
    ) {
        print("WebSocket connected with protocol: \(protocolString ?? "none")")

        stateQueue.async { [weak self] in
            guard let self = self else { return }

            if self.isReconnecting {
                self.isReconnecting = false
                self.reconnectAttempts = 0
            }

            self.updateState(.connected)

            // 重新订阅所有会话
            let sessionIds = Array(self.subscribedSessions)
            if !sessionIds.isEmpty {
                Task {
                    try? await self.subscribe(toSessionIds: sessionIds)
                }
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("WebSocket disconnected: closeCode=\(closeCode.rawValue)")

        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) }
        let error: Error? = {
            switch closeCode {
            case .normalClosure:
                return nil
            case .goingAway:
                return nil
            default:
                return TerminalClientError.handshakeFailed(reasonStr ?? "Code: \(closeCode.rawValue)")
            }
        }()

        stateQueue.async { [weak self] in
            guard let self = self else { return }
            self.updateState(.disconnected)
        }

        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            if let error = error {
                self.delegate?.client(self, didReceiveError: error)
            }
        }

        // 自动重连
        if config.autoReconnect && closeCode != .goingAway {
            reconnect()
        }
    }
}

// MARK: - KeyCode Support

enum KeyCode {
    case enter
    case tab
    case backspace
    case escape
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    case insert
    case delete
    case f(UInt8)
    case character(Character)

    /// 编码为 ANSI 转义序列
    func encode() -> Data {
        switch self {
        case .enter:
            return Data("\n".utf8)
        case .tab:
            return Data("\t".utf8)
        case .backspace:
            return Data([0x7F])  // DEL
        case .escape:
            return Data([0x1B])  // ESC
        case .up:
            return Data("\u{1B}[A".utf8)
        case .down:
            return Data("\u{1B}[B".utf8)
        case .right:
            return Data("\u{1B}[C".utf8)
        case .left:
            return Data("\u{1B}[D".utf8)
        case .home:
            return Data("\u{1B}[H".utf8)
        case .end:
            return Data("\u{1B}[F".utf8)
        case .pageUp:
            return Data("\u{1B}[5~".utf8)
        case .pageDown:
            return Data("\u{1B}[6~".utf8)
        case .insert:
            return Data("\u{1B}[2~".utf8)
        case .delete:
            return Data("\u{1B}[3~".utf8)
        case .f(let n):
            return encodeFKey(n)
        case .character(let char):
            return Data(String(char).utf8)
        }
    }

    private func encodeFKey(_ n: UInt8) -> Data {
        switch n {
        case 1...12:
            let codes = [
                "OP", "OQ", "OR", "OS",  // F1-F4
                "[15~", "[17~", "[18~", "[19~",  // F5-F8
                "[20~", "[21~", "[23~", "[24~"   // F9-F12
            ]
            let index = Int(n - 1)
            if index < codes.count {
                return Data("\u{1B}\(codes[index])".utf8)
            }
        default:
            break
        }
        return Data()
    }
}

// MARK: - Protocol Encoding/Decoding (使用二进制编码器)

/// 编码帧为二进制数据（使用高效的二进制编码器）
private func encodeFrame(_ frame: Frame) -> Data {
    let encoder = BinaryProtocolEncoder()
    return encoder.encodeFrame(frame)
}

/// 编码帧数据（已废弃，保留用于兼容性）
private func encodeFrameData(_ frame: Frame) throws -> Data {
    return encodeFrame(frame)
}

/// 获取帧类型标记（已废弃，保留用于兼容性）
private func getFrameTypeMarker(_ frame: Frame) -> UInt8 {
    switch frame {
    case .input: return 0x01
    case .subscribe: return 0x02
    case .createSession: return 0x03
    case .resizeSession: return 0x04
    case .closeSession: return 0x05
    case .sessionOutput: return 0x10
    case .cursorUpdate: return 0x11
    case .modeUpdate: return 0x12
    case .sessionCreated: return 0x13
    case .sessionClosed: return 0x14
    case .error: return 0x15
    case .rawOutput: return 0x16
    case .ping: return 0x20
    case .pong: return 0x21
    }
}

/// 从数据中解码多个帧（使用高效的二进制解码器）
private func decodeFrames(_ data: Data) -> ([Frame], Data) {
    return BinaryProtocolDecoder.decodeFrames(data)
}

/// 解码帧
private func decodeFrame(_ data: Data) throws -> Frame {
    guard data.count >= 5 else {
        throw TerminalClientError.decodeFailed("Incomplete data")
    }

    let frameType = data[0]
    let len = Int(UInt32(littleEndian: data[1..<5].withUnsafeBytes { $0.load(as: UInt32.self) }))

    guard data.count >= 5 + len else {
        throw TerminalClientError.decodeFailed("Incomplete data")
    }

    let frameData = data[5..<(5 + len)]

    return try decodeFrameData(frameType, data: frameData)
}

/// 解码帧数据
private func decodeFrameData(_ frameType: UInt8, data: Data) throws -> Frame {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TerminalClientError.decodeFailed("Invalid JSON")
    }

    switch frameType {
    case 0x01:  // Input
        guard let arr = json["Input"] as? [Any],
              let sessionId = arr.first as? String,
              let base64 = arr[safe: 1] as? String,
              let inputData = Data(base64Encoded: base64) else {
            throw TerminalClientError.decodeFailed("Invalid Input frame")
        }
        return .input(sessionId: sessionId, data: inputData)

    case 0x02:  // Subscribe
        guard let sessionIds = json["Subscribe"] as? [String] else {
            throw TerminalClientError.decodeFailed("Invalid Subscribe frame")
        }
        return .subscribe(sessionIds)

    case 0x03:  // CreateSession
        guard let reqDict = json["CreateSession"] as? [String: Any],
              let command = reqDict["command"] as? String,
              let args = reqDict["args"] as? [String] else {
            throw TerminalClientError.decodeFailed("Invalid CreateSession frame")
        }
        let cwd = reqDict["cwd"] as? String
        let env = reqDict["env"] as? [String: String]
        let req = CreateSessionRequest(command: command, args: args, cwd: cwd, env: env)
        return .createSession(req)

    case 0x04:  // ResizeSession
        guard let arr = json["ResizeSession"] as? [Any],
              let sessionId = arr.first as? String,
              let cols = arr[safe: 1] as? UInt16,
              let rows = arr[safe: 2] as? UInt16 else {
            throw TerminalClientError.decodeFailed("Invalid ResizeSession frame")
        }
        return .resizeSession(sessionId: sessionId, cols: cols, rows: rows)

    case 0x05:  // CloseSession
        guard let sessionId = json["CloseSession"] as? String else {
            throw TerminalClientError.decodeFailed("Invalid CloseSession frame")
        }
        return .closeSession(sessionId: sessionId)

    case 0x10:  // SessionOutput
        guard let arr = json["SessionOutput"] as? [Any],
              let sessionId = arr.first as? String,
              let frameDict = arr[safe: 1] as? [String: Any] else {
            throw TerminalClientError.decodeFailed("Invalid SessionOutput frame")
        }
        let screenFrame = try decodeScreenFrame(frameDict)
        return .sessionOutput(sessionId: sessionId, frame: screenFrame)

    case 0x11:  // CursorUpdate
        guard let cursorDict = json["CursorUpdate"] as? [String: Any] else {
            throw TerminalClientError.decodeFailed("Invalid CursorUpdate frame")
        }
        let cursor = try decodeCursorFrame(cursorDict)
        return .cursorUpdate(cursor)

    case 0x12:  // ModeUpdate
        guard let modeDict = json["ModeUpdate"] as? [String: Any] else {
            throw TerminalClientError.decodeFailed("Invalid ModeUpdate frame")
        }
        let mode = try decodeModeFrame(modeDict)
        return .modeUpdate(mode)

    case 0x13:  // SessionCreated
        guard let sessionId = json["SessionCreated"] as? String else {
            throw TerminalClientError.decodeFailed("Invalid SessionCreated frame")
        }
        return .sessionCreated(sessionId)

    case 0x14:  // SessionClosed
        guard let sessionId = json["SessionClosed"] as? String else {
            throw TerminalClientError.decodeFailed("Invalid SessionClosed frame")
        }
        return .sessionClosed(sessionId)

    case 0x15:  // Error
        guard let msg = json["Error"] as? String else {
            throw TerminalClientError.decodeFailed("Invalid Error frame")
        }
        return .error(msg)

    case 0x20:  // Ping
        return .ping

    case 0x21:  // Pong
        return .pong

    default:
        throw TerminalClientError.decodeFailed("Unknown frame type: \(frameType)")
    }
}

/// 解码 ScreenFrame
private func decodeScreenFrame(_ dict: [String: Any]) throws -> ScreenFrame {
    guard let seq = dict["seq"] as? UInt64,
          let cols = dict["cols"] as? UInt16,
          let rows = dict["rows"] as? UInt16,
          let regionsArray = dict["dirty_regions"] as? [[String: Any]] else {
        throw TerminalClientError.decodeFailed("Invalid ScreenFrame")
    }

    let dirtyRegions = try regionsArray.map { regionDict -> ProtocolDirtyRegion in
        guard let x = regionDict["x"] as? UInt16,
              let y = regionDict["y"] as? UInt16,
              let width = regionDict["width"] as? UInt16,
              let height = regionDict["height"] as? UInt16,
              let cellsArray = regionDict["cells"] as? [[String: Any]] else {
            throw TerminalClientError.decodeFailed("Invalid ProtocolDirtyRegion")
        }

        let cells = try cellsArray.map { cellDict -> ProtocolCellData in
            try decodeProtocolCellData(cellDict)
        }

        return ProtocolDirtyRegion(x: x, y: y, width: width, height: height, cells: cells)
    }

    return ScreenFrame(seq: seq, cols: cols, rows: rows, dirtyRegions: dirtyRegions)
}

/// 解码 ProtocolCellData
private func decodeProtocolCellData(_ dict: [String: Any]) throws -> ProtocolCellData {
    guard let char = dict["char"] as? String else {
        throw TerminalClientError.decodeFailed("Invalid CellData")
    }

    let fgColor: Color
    let bgColor: Color

    if let fgDict = dict["fg_color"] as? [String: Any] {
        fgColor = try decodeColor(fgDict)
    } else {
        fgColor = .default
    }

    if let bgDict = dict["bg_color"] as? [String: Any] {
        bgColor = try decodeColor(bgDict)
    } else {
        bgColor = .default
    }

    let attrsRaw = (dict["attrs"] as? [String: Any])?["bits"] as? UInt16 ?? 0
    let attrs = CellAttrs(rawValue: attrsRaw)

    return CellData(char: char, fgColor: fgColor, bgColor: bgColor, attrs: attrs)
}

/// 解码 Color
private func decodeColor(_ dict: [String: Any]) throws -> Color {
    if let idx = dict["Indexed"] as? UInt8 {
        return .indexed(idx)
    } else if let idx = dict["Palette"] as? UInt8 {
        return .palette(idx)
    } else if let rgbDict = dict["Rgb"] as? [String: UInt8] {
        return .rgb(r: rgbDict["r"] ?? 0, g: rgbDict["g"] ?? 0, b: rgbDict["b"] ?? 0)
    }
    return .default
}

/// 解码 CursorFrame
private func decodeCursorFrame(_ dict: [String: Any]) throws -> CursorFrame {
    guard let x = dict["x"] as? UInt16,
          let y = dict["y"] as? UInt16,
          let visible = dict["visible"] as? Bool,
          let style = dict["style"] as? UInt8,
          let cursorStyle = CursorStyle(rawValue: style) else {
        throw TerminalClientError.decodeFailed("Invalid CursorFrame")
    }
    return CursorFrame(x: x, y: y, visible: visible, style: cursorStyle)
}

/// 解码 ModeFrame
private func decodeModeFrame(_ dict: [String: Any]) throws -> ModeFrame {
    guard let mode = dict["mode"] as? UInt8,
          let modeValue = Mode(rawValue: mode),
          let active = dict["active"] as? Bool else {
        throw TerminalClientError.decodeFailed("Invalid ModeFrame")
    }
    return ModeFrame(mode: modeValue, active: active)
}

// MARK: - Array Safe Access

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
