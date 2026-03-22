//
//  LocalPTYConnection.swift
//  VibeTerminal
//
//  使用共享内存的本地 PTY 连接
//
//  替代 TCP WebSocket 连接，实现零拷贝的高性能通信
//

import Foundation
import Combine

// MARK: - 本地 PTY 连接

final class LocalPTYConnection: NSObject {
    // MARK: - Published Properties

    @Published private(set) var isConnected = false
    @Published private(set) var connectionState: ConnectionState = .disconnected

    // MARK: - Private Properties

    private let sessionId: String
    private let config: LocalPTYConfig

    private var sharedMemory: SharedMemoryBuffer?
    private var readTimer: Timer?
    private let readQueue = DispatchQueue(label: "com.vibeterminal.localpty.read", qos: .userInitiated)

    // 回调
    var onDataReceived: ((Data) -> Void)?
    var onStateChanged: ((ConnectionState) -> Void)?

    // MARK: - Initialization

    init(sessionId: String, config: LocalPTYConfig = .default) {
        self.sessionId = sessionId
        self.config = config
        super.init()
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection Management

    /// 连接到本地 PTY 服务器
    func connect() {
        guard !isConnected else { return }

        updateState(.connecting)

        // 尝试打开共享内存
        do {
            let buffer = try SharedMemoryPool.shared.buffer(
                named: sessionId,
                create: false  // 由服务器创建
            )
            self.sharedMemory = buffer
            self.isConnected = true
            updateState(.connected)

            // 启动读取定时器
            startReading()

        } catch {
            updateState(.failed(error))
        }
    }

    /// 断开连接
    func disconnect() {
        isConnected = false
        stopReading()
        sharedMemory = nil
        updateState(.disconnected)
    }

    // MARK: - Data Transfer

    /// 发送数据到 PTY
    func send(_ data: Data) {
        guard let buffer = sharedMemory else { return }

        do {
            try buffer.write(data)
        } catch {
            print("Failed to write to shared memory: \(error)")
        }
    }

    /// 发送文本
    func send(_ text: String) {
        if let data = text.data(using: .utf8) {
            send(data)
        }
    }

    /// 发送按键
    func send(key: LocalKeyCode) {
        send(key.encode())
    }

    // MARK: - Reading

    private func startReading() {
        readTimer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { [weak self] _ in
            self?.readAvailableData()
        }
    }

    private func stopReading() {
        readTimer?.invalidate()
        readTimer = nil
    }

    private func readAvailableData() {
        guard let buffer = sharedMemory else { return }

        if buffer.hasData {
            do {
                let data = try buffer.read()
                if !data.isEmpty {
                    onDataReceived?(data)
                }
            } catch {
                print("Failed to read from shared memory: \(error)")
            }
        }
    }

    // MARK: - State Management

    private func updateState(_ state: ConnectionState) {
        connectionState = state
        onStateChanged?(state)
    }
}

// MARK: - LocalKeyCode

enum LocalKeyCode {
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

    func encode() -> Data {
        switch self {
        case .enter:
            return Data("\n".utf8)
        case .tab:
            return Data("\t".utf8)
        case .backspace:
            return Data([0x7F])
        case .escape:
            return Data([0x1B])
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
                "OP", "OQ", "OR", "OS",
                "[15~", "[17~", "[18~", "[19~",
                "[20~", "[21~", "[23~", "[24~"
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

// MARK: - LocalPTYConfig

struct LocalPTYConfig {
    var shell: String = "/bin/bash"
    var args: [String] = ["--login"]
    var env: [(String, String)] = []
    var cols: UInt16 = 80
    var rows: UInt16 = 24

    static let `default` = LocalPTYConfig()
}
