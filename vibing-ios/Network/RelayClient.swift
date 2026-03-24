//
//  RelayClient.swift
//  VibeTerminal
//
//  中继客户端 - 通过中继服务器连接到终端
//  支持端到端加密，零知识架构
//

import Foundation
import Combine

// MARK: - 中继客户端委托

protocol RelayClientDelegate: AnyObject {
    /// 连接到中继服务器成功
    func relayClientDidConnect(_ client: RelayClient)

    /// 从中继服务器断开
    func relayClientDidDisconnect(_ client: RelayClient, error: Error?)

    /// 对端（host）已连接
    func relayClientPeerDidConnect(_ client: RelayClient)

    /// 对端（host）已断开
    func relayClientPeerDidDisconnect(_ client: RelayClient)

    /// 收到终端数据
    func relayClient(_ client: RelayClient, didReceiveData data: Data)

    /// 收到错误
    func relayClient(_ client: RelayClient, didReceiveError error: Error)
}

// MARK: - 中继客户端配置

struct RelayClientConfig {
    /// 中继服务器 URL
    var relayURL: String

    /// 会话 ID（16 字符）
    var sessionId: String

    /// 角色："client" 或 "host"
    var role: RelayRole

    /// 连接超时（秒）
    var connectionTimeout: TimeInterval = 10

    /// 心跳间隔（秒）
    var heartbeatInterval: TimeInterval = 30

    /// 自动重连
    var autoReconnect: Bool = true

    /// 重连延迟（秒）
    var reconnectDelay: TimeInterval = 2

    /// 预期的服务器指纹（可选，用于验证）
    var expectedFingerprint: String? = nil

    static func `default`(relayURL: String, sessionId: String, role: RelayRole) -> RelayClientConfig {
        RelayClientConfig(relayURL: relayURL, sessionId: sessionId, role: role)
    }
}

// MARK: - 中继角色

enum RelayRole: String {
    case host = "host"
    case client = "client"
}

// MARK: - 中继客户端错误

enum RelayClientError: Error, LocalizedError {
    case invalidURL
    case invalidSessionId
    case handshakeFailed(String)
    case peerNotFound
    case encryptionFailed
    case decryptionFailed
    case serverError(String)
    case notConnected
    case fingerprintMismatch

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid relay server URL"
        case .invalidSessionId:
            return "Session ID must be 16 alphanumeric characters"
        case .handshakeFailed(let msg):
            return "Handshake failed: \(msg)"
        case .peerNotFound:
            return "Peer not found - session may not exist"
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        case .serverError(let msg):
            return "Server error: \(msg)"
        case .notConnected:
            return "Not connected to relay server"
        case .fingerprintMismatch:
            return "Server fingerprint mismatch - security risk!"
        }
    }
}

// MARK: - 中继协议消息

struct RelayHandshake: Codable {
    let type: String
    let session_id: String
    let role: String

    init(sessionId: String, role: RelayRole) {
        self.type = "handshake"
        self.session_id = sessionId
        self.role = role.rawValue
    }
}

struct RelayServerHello: Codable {
    let type: String
    let server_fingerprint: String
    let timestamp: String
}

struct RelayPeerConnected: Codable {
    let type: String
}

struct RelayError: Codable {
    let type: String
    let error: String?

    var errorMessage: String {
        error ?? "Unknown error"
    }
}

struct RelayPing: Codable {
    let type: String

    init() {
        self.type = "ping"
    }
}

struct RelayPong: Codable {
    let type: String
}

// MARK: - 中继客户端

class RelayClient: NSObject {

    // MARK: - 属性

    private let config: RelayClientConfig
    private let keyManager: SessionKeyManager

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    private(set) var isConnected = false
    private(set) var isPeerConnected = false
    private var handshakeCompleted = false

    private var heartbeatTimer: Timer?
    private var reconnectAttempts = 0

    weak var delegate: RelayClientDelegate?
    private let delegateQueue = DispatchQueue.main

    // MARK: - 初始化

    init(config: RelayClientConfig) {
        self.config = config
        self.keyManager = SessionKeyManager()

        super.init()

        // 验证会话 ID
        guard isValidSessionId(config.sessionId) else {
            fatalError("Invalid session ID")
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.connectionTimeout
        self.urlSession = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
    }

    deinit {
        disconnect()
    }

    // MARK: - 连接管理

    /// 连接到中继服务器
    func connect() {
        guard !isConnected else { return }

        guard let url = URL(string: config.relayURL) else {
            notifyError(RelayClientError.invalidURL)
            return
        }

        let task = urlSession!.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        // 开始接收消息
        receiveMessage()

        print("[RelayClient] Connecting to \(config.relayURL)...")
    }

    /// 断开连接
    func disconnect() {
        isConnected = false
        isPeerConnected = false
        handshakeCompleted = false

        stopHeartbeat()

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        // 清除密钥
        keyManager.clearAll()
    }

    // MARK: - 消息发送

    /// 发送原始数据（会先加密）
    func sendData(_ data: Data) {
        guard isConnected, isPeerConnected else {
            print("[RelayClient] Cannot send - not connected or peer not ready")
            return
        }

        do {
            // 获取会话密钥
            let key = keyManager.getKey(for: config.sessionId)

            // 加密数据
            let encrypted = try EncryptedRelayMessage(message: data, key: key)

            // 作为二进制消息发送
            sendBinary(encrypted.data)

        } catch {
            print("[RelayClient] Encryption failed: \(error)")
            notifyError(RelayClientError.encryptionFailed)
        }
    }

    /// 发送文本消息（用于控制消息）
    func sendText(_ text: String) {
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                print("[RelayClient] Send error: \(error)")
                self?.notifyError(RelayClientError.serverError(error.localizedDescription))
            }
        }
    }

    /// 发送二进制消息
    private func sendBinary(_ data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                print("[RelayClient] Send error: \(error)")
                self?.notifyError(RelayClientError.serverError(error.localizedDescription))
            }
        }
    }

    /// 发送心跳 ping
    private func sendPing() {
        let ping = RelayPing()
        if let data = try? JSONEncoder().encode(ping),
           let text = String(data: data, encoding: .utf8) {
            sendText(text)
        }
    }

    // MARK: - 消息接收

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)

                // 继续接收
                if self.isConnected {
                    self.receiveMessage()
                }

            case .failure(let error):
                print("[RelayClient] Receive error: \(error)")
                self.handleDisconnect(error: error)
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
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "hello":
            handleServerHello(json)

        case "peer_connected":
            handlePeerConnected()

        case "pong":
            // 心跳响应，无需处理
            break

        case "error":
            handleError(json)

        default:
            print("[RelayClient] Unknown message type: \(type)")
        }
    }

    private func handleBinaryMessage(_ data: Data) {
        guard isPeerConnected else {
            print("[RelayClient] Received binary before peer connected")
            return
        }

        do {
            // 解密数据
            let key = keyManager.getKey(for: config.sessionId)
            let decrypted = try decryptMessage(data, key: key)

            // 通知代理
            delegateQueue.async { [weak self] in
                self?.delegate?.relayClient(self!, didReceiveData: decrypted)
            }

        } catch {
            print("[RelayClient] Decryption failed: \(error)")
            notifyError(RelayClientError.decryptionFailed)
        }
    }

    // MARK: - 协议处理

    private func handleServerHello(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let hello = try? JSONDecoder().decode(RelayServerHello.self, from: data) else {
            notifyError(RelayClientError.handshakeFailed("Invalid hello message"))
            return
        }

        // 验证服务器指纹（如果配置了）
        if let expected = config.expectedFingerprint {
            guard hello.server_fingerprint == expected else {
                notifyError(RelayClientError.fingerprintMismatch)
                return
            }
        }

        handshakeCompleted = true
        isConnected = true

        print("[RelayClient] Connected to relay (fingerprint: \(hello.server_fingerprint))")

        // 启动心跳
        startHeartbeat()

        // 通知代理
        delegateQueue.async { [weak self] in
            self?.delegate?.relayClientDidConnect(self!)
        }
    }

    private func handlePeerConnected() {
        isPeerConnected = true
        reconnectAttempts = 0

        print("[RelayClient] Peer connected!")

        delegateQueue.async { [weak self] in
            self?.delegate?.relayClientPeerDidConnect(self!)
        }
    }

    private func handleError(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let error = try? JSONDecoder().decode(RelayError.self, from: data) else {
            return
        }

        print("[RelayClient] Server error: \(error.errorMessage)")
        notifyError(RelayClientError.serverError(error.errorMessage))
    }

    private func handleDisconnect(error: Error) {
        let wasConnected = isConnected
        isConnected = false
        isPeerConnected = false
        handshakeCompleted = false

        stopHeartbeat()

        if wasConnected {
            delegateQueue.async { [weak self] in
                self?.delegate?.relayClientDidDisconnect(self!, error: error)
            }
        }

        // 自动重连
        if config.autoReconnect {
            scheduleReconnect()
        }
    }

    // MARK: - 心跳

    private func startHeartbeat() {
        stopHeartbeat()

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: config.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - 重连

    private func scheduleReconnect() {
        let delay = config.reconnectDelay * pow(2.0, Double(min(reconnectAttempts, 5)))

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reconnectAttempts += 1
            print("[RelayClient] Reconnecting... (attempt \(self?.reconnectAttempts ?? 0))")
            self?.connect()
        }
    }

    // MARK: - 握手发送

    /// 发送握手消息（连接后调用）
    private func sendHandshake() {
        let handshake = RelayHandshake(sessionId: config.sessionId, role: config.role)

        if let data = try? JSONEncoder().encode(handshake),
           let text = String(data: data, encoding: .utf8) {
            sendText(text)
        }
    }

    // MARK: - 通知

    private func notifyError(_ error: Error) {
        delegateQueue.async { [weak self] in
            self?.delegate?.relayClient(self!, didReceiveError: error)
        }
    }

    // MARK: - 验证

    private func isValidSessionId(_ sessionId: String) -> Bool {
        guard sessionId.count == 16 else { return false }
        return sessionId.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension RelayClient: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("[RelayClient] WebSocket connected")

        // 发送握手
        sendHandshake()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("[RelayClient] WebSocket closed: \(closeCode.rawValue)")

        let error: Error? = closeCode == .normalClosure ? nil : RelayClientError.serverError("Connection closed")
        handleDisconnect(error: error)
    }
}
