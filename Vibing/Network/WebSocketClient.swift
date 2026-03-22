//
//  WebSocketClient.swift
//  VibeTerminal
//
//  WebSocket 客户端 - 与服务器端 server.rs 对应
//  支持自动重连、心跳机制、超时检测
//

import Foundation
import Combine

// MARK: - WebSocket 客户端委托

protocol WebSocketClientDelegate: AnyObject {
    /// 连接成功
    func webSocketDidConnect(_ client: WebSocketClient)

    /// 连接断开
    func webSocketDidDisconnect(_ client: WebSocketClient, error: Error?)

    /// 接收到帧
    func webSocket(_ client: WebSocketClient, didReceiveFrame frame: Frame)

    /// 接收到错误
    func webSocket(_ client: WebSocketClient, didReceiveError error: Error)
}

// MARK: - WebSocket 客户端错误

enum WebSocketClientError: Error, LocalizedError {
    case notConnected
    case invalidURL
    case sendFailed(String)
    case connectionTimeout
    case handshakeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .invalidURL:
            return "Invalid server URL"
        case .sendFailed(let msg):
            return "Send failed: \(msg)"
        case .connectionTimeout:
            return "Connection timeout"
        case .handshakeFailed(let msg):
            return "Handshake failed: \(msg)"
        }
    }
}

// MARK: - WebSocket 客户端配置

struct WebSocketClientConfig {
    /// 连接超时时间（秒）
    var connectionTimeout: TimeInterval = 10

    /// 心跳间隔（秒）
    var heartbeatInterval: TimeInterval = 30

    /// 心跳超时时间（秒），超过此时间未收到 pong 则断开
    var heartbeatTimeout: TimeInterval = 60

    /// 自动重连
    var autoReconnect: Bool = true

    /// 重连延迟（秒）
    var reconnectDelay: TimeInterval = 2

    /// 最大重连次数（0 表示无限重连）
    var maxReconnectAttempts: Int = 0

    /// 重连延迟的最大值（秒）
    var maxReconnectDelay: TimeInterval = 30

    static let `default` = WebSocketClientConfig()
}

// MARK: - WebSocket 客户端

class WebSocketClient: NSObject {

    // MARK: - 属性

    /// 服务器 URL
    private let url: URL

    /// 配置
    private let config: WebSocketClientConfig

    /// URLSession
    private var session: URLSession?

    /// WebSocket 任务
    private var task: URLSessionWebSocketTask?

    /// 是否已连接
    private(set) var isConnected = false

    /// 委托
    weak var delegate: WebSocketClientDelegate?

    /// 连接状态（用于主线程回调）
    private let delegateQueue = DispatchQueue.main

    /// 发送队列（线程安全）
    private let sendQueue = DispatchQueue(label: "com.vibing.websocket.send", qos: .userInitiated)

    /// 接收缓冲区（处理分包）
    private var receiveBuffer = Data()

    /// 心跳定时器
    private var heartbeatTimer: Timer?

    /// 最后收到 pong 的时间
    private var lastPongTime = Date()

    /// 重连次数
    private var reconnectAttempts = 0

    /// 是否正在重连
    private var isReconnecting = false

    /// 待发送的输入队列（连接断开时缓存）
    private var pendingInputs: [(sessionId: String, data: Data)] = []

    /// 待发送的订阅队列
    private var pendingSubscribes: [[String]] = []

    /// 订阅的会话列表
    private(set) var subscribedSessions = Set<String>()

    // MARK: - 初始化

    init(url: URL, config: WebSocketClientConfig = .default) {
        self.url = url
        self.config = config

        super.init()

        // 配置 URLSession
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.connectionTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: OperationQueue(
                name: "com.vibing.websocket.session",
                underlyingQueue: DispatchQueue(label: "com.vibing.websocket.session.queue")
            )
        )
    }

    deinit {
        disconnect()
        stopHeartbeat()
    }

    // MARK: - 连接管理

    /// 连接到服务器
    func connect() {
        guard !isConnected && !isReconnecting else { return }

        let task = session!.webSocketTask(with: url)
        self.task = task
        task.resume()

        // 启动接收循环
        receiveLoop()

        // 启动连接超时检测
        scheduleConnectionTimeout()
    }

    /// 断开连接
    func disconnect() {
        isReconnecting = false
        reconnectAttempts = 0

        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false

        stopHeartbeat()
    }

    /// 重新连接
    func reconnect() {
        disconnect()

        // 计算延迟（指数退避）
        let delay = min(
            config.reconnectDelay * pow(2.0, Double(reconnectAttempts)),
            config.maxReconnectDelay
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.isReconnecting = true
            self.connect()
        }
    }

    // MARK: - 消息发送

    /// 发送帧
    func sendFrame(_ frame: Frame) async throws {
        guard isConnected else {
            throw WebSocketClientError.notConnected
        }

        let data = encodeFrame(frame)

        return try await withCheckedThrowingContinuation { continuation in
            sendQueue.async { [weak self] in
                guard let self = self, let task = self.task else {
                    continuation.resume(throwing: WebSocketClientError.notConnected)
                    return
                }

                let message = URLSessionWebSocketTask.Message.data(data)

                task.send(message) { error in
                    if let error = error {
                        continuation.resume(throwing: WebSocketClientError.sendFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    /// 发送输入数据
    func sendInput(sessionId: String, data: Data) async throws {
        let frame = Frame.input(sessionId: sessionId, data: data)
        try await sendFrame(frame)
    }

    /// 发送订阅请求
    func sendSubscribe(sessionIds: [String]) async throws {
        let frame = Frame.subscribe(sessionIds)
        try await sendFrame(frame)

        // 更新订阅列表
        sessionIds.forEach { subscribedSessions.insert($0) }
    }

    /// 发送创建会话请求
    func sendCreateSession(_ request: CreateSessionRequest) async throws {
        let frame = Frame.createSession(request)
        try await sendFrame(frame)
    }

    /// 发送调整会话大小请求
    func sendResizeSession(sessionId: String, cols: UInt16, rows: UInt16) async throws {
        let frame = Frame.resizeSession(sessionId: sessionId, cols: cols, rows: rows)
        try await sendFrame(frame)
    }

    /// 发送关闭会话请求
    func sendCloseSession(sessionId: String) async throws {
        let frame = Frame.closeSession(sessionId: sessionId)
        try await sendFrame(frame)

        // 从订阅列表移除
        subscribedSessions.remove(sessionId)
    }

    // MARK: - 心跳机制

    private func startHeartbeat() {
        stopHeartbeat()

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
            guard let self = self, self.isConnected else { return }

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
            print("Heartbeat timeout, disconnecting...")
            delegateQueue.async { [weak self] in
                self?.delegate?.webSocketDidDisconnect(self!, error: WebSocketClientError.connectionTimeout)
            }
            disconnect()

            if config.autoReconnect {
                reconnect()
            }
        }
    }

    // MARK: - 连接超时检测

    private func scheduleConnectionTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + config.connectionTimeout) { [weak self] in
            guard let self = self, !self.isConnected, self.task != nil else { return }

            print("Connection timeout")
            self.task?.cancel()
            self.task = nil

            if self.config.autoReconnect {
                self.reconnect()
            }
        }
    }

    // MARK: - 接收循环

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)

                // 继续接收
                if self.isConnected {
                    self.receiveLoop()
                }

            case .failure(let error):
                print("Receive error: \(error)")
                self.isConnected = false

                self.delegateQueue.async {
                    self.delegate?.webSocketDidDisconnect(self, error: error)
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
        // 服务器可能发送文本格式的 JSON 消息（用于调试）
        guard let data = text.data(using: .utf8) else { return }
        handleBinaryMessage(data)
    }

    private func handleBinaryMessage(_ data: Data) {
        // 添加到接收缓冲区
        receiveBuffer.append(data)

        // 尝试解析多个帧
        let (frames, remaining) = decodeFrames(receiveBuffer)
        receiveBuffer = remaining

        // 在主线程回调
        delegateQueue.async { [weak self] in
            guard let self = self else { return }

            for frame in frames {
                self.handleFrame(frame)
            }
        }
    }

    private func handleFrame(_ frame: Frame) {
        switch frame {
        case .pong:
            // 更新心跳时间
            lastPongTime = Date()

        case .error(let message):
            delegate?.webSocket(self, didReceiveError: ProtocolError.serializationError(message))

        default:
            delegate?.webSocket(self, didReceiveFrame: frame)
        }
    }

    // MARK: - 重连处理

    private func handleReconnectSuccess() {
        isReconnecting = false
        reconnectAttempts = 0

        // 重新订阅会话
        let sessionIds = Array(subscribedSessions)
        if !sessionIds.isEmpty {
            Task { [weak self] in
                try? await self?.sendSubscribe(sessionIds: sessionIds)
            }
        }

        // 发送缓存的输入
        flushPendingInputs()
    }

    private func flushPendingInputs() {
        Task { [weak self] in
            guard let self = self else { return }

            let inputs = self.pendingInputs
            self.pendingInputs.removeAll()

            for input in inputs {
                try? await self.sendInput(sessionId: input.sessionId, data: input.data)
            }

            let subscribes = self.pendingSubscribes
            self.pendingSubscribes.removeAll()

            for sessionIds in subscribes {
                try? await self.sendSubscribe(sessionIds: sessionIds)
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketClient: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("WebSocket connected with protocol: \(protocol ?? "none")")
        isConnected = true

        // 启动心跳
        startHeartbeat()

        delegateQueue.async { [weak self] in
            guard let self = self else { return }

            if self.isReconnecting {
                self.handleReconnectSuccess()
            }

            self.delegate?.webSocketDidConnect(self)
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("WebSocket disconnected: \(closeCode.rawValue)")

        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) }
        let error = closeCode == .normalClosure
            ? nil
            : WebSocketClientError.handshakeFailed(reasonStr ?? "Unknown reason")

        isConnected = false
        stopHeartbeat()

        delegateQueue.async { [weak self] in
            self?.delegate?.webSocketDidDisconnect(self!, error: error)
        }

        // 处理重连
        if config.autoReconnect && closeCode != .goingAway {
            reconnect()
        }
    }
}

// MARK: - 便捷方法

extension WebSocketClient {

    /// 创建连接并返回
    static func connect(
        to urlString: String,
        config: WebSocketClientConfig = .default,
        delegate: WebSocketClientDelegate?
    ) throws -> WebSocketClient {
        guard let url = URL(string: urlString) else {
            throw WebSocketClientError.invalidURL
        }

        let client = WebSocketClient(url: url, config: config)
        client.delegate = delegate
        client.connect()

        return client
    }

    /// 创建默认 Shell 会话（不返回 sessionId）
    func createShellSession() async throws {
        let request = CreateSessionRequest.shell()
        try await sendCreateSession(request)
    }

    /// 创建 Shell 会话并返回 sessionId
    /// 注意：这需要等待 sessionCreated 帧返回，实际实现中通过委托回调
    func createShellSessionWithId() async throws -> String {
        // 这是一个临时实现，实际应该等待 sessionCreated 回调
        // 这里使用 continuation 来等待异步结果
        return try await withCheckedThrowingContinuation { continuation in
            // 创建一个临时观察者来等待 sessionCreated
            let observer = SessionCreatedObserver { sessionId in
                continuation.resume(returning: sessionId)
            }

            // 存储观察者以便在收到 sessionCreated 时使用
            sessionCreatedObserver = observer

            let request = CreateSessionRequest.shell()
            Task {
                try? await self.sendCreateSession(request)
            }

            // 设置超时
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 秒
                if !continuation.isResumed {
                    continuation.resume(throwing: WebSocketClientError.connectionTimeout)
                }
            }
        }
    }

    /// 调整会话终端大小
    func resizeSession(sessionId: String, cols: UInt16, rows: UInt16) async throws {
        try await sendResizeSession(sessionId: sessionId, cols: cols, rows: rows)
    }

    /// 创建命令会话
    func createCommandSession(_ command: String, args: [String] = []) async throws {
        let request = CreateSessionRequest.command(command, args: args)
        try await sendCreateSession(request)
    }

    // MARK: - Session Created Observer

    private var sessionCreatedObserver: SessionCreatedObserver?

    /// 处理会话创建通知（由代理调用）
    func handleSessionCreated(_ sessionId: String) {
        sessionCreatedObserver?.callback(sessionId)
        sessionCreatedObserver = nil
    }
}

// MARK: - Session Created Observer

private class SessionCreatedObserver {
    let callback: (String) -> Void

    init(callback: @escaping (String) -> Void) {
        self.callback = callback
    }
}
