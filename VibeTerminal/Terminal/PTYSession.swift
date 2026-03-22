//
//  PTYSession.swift
//  VibeTerminal
//
//  PTY 会话管理 - 连接到本地 vibe-terminal-server
//

import Foundation
import Network

// MARK: - 终端状态模型

/// PTY 终端单元格 (与渲染层的 Cell 分离)
struct PTYCell: Equatable {
    var char: Character = " "
    var fgColor: PTYColorRGB = .defaultFG
    var bgColor: PTYColorRGB = .defaultBG
    var attrs: PTYCellAttributes = []

    static func == (lhs: PTYCell, rhs: PTYCell) -> Bool {
        lhs.char == rhs.char &&
        lhs.fgColor == rhs.fgColor &&
        lhs.bgColor == rhs.bgColor &&
        lhs.attrs == rhs.attrs
    }
}

/// RGB 颜色
struct PTYColorRGB: Codable, Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8

    static let defaultFG = PTYColorRGB(r: 212, g: 212, b: 212)
    static let defaultBG = PTYColorRGB(r: 28, g: 28, b: 28)
}

/// 单元格属性
struct PTYCellAttributes: OptionSet, Codable {
    let rawValue: UInt16

    static let bold = PTYCellAttributes(rawValue: 1 << 0)
    static let faint = PTYCellAttributes(rawValue: 1 << 1)
    static let italic = PTYCellAttributes(rawValue: 1 << 2)
    static let underline = PTYCellAttributes(rawValue: 1 << 3)
    static let blink = PTYCellAttributes(rawValue: 1 << 4)
    static let reverse = PTYCellAttributes(rawValue: 1 << 5)
    static let hidden = PTYCellAttributes(rawValue: 1 << 6)
    static let strikethrough = PTYCellAttributes(rawValue: 1 << 7)
}

/// 光标状态
struct PTYCursorState: Equatable {
    var x: Int = 0
    var y: Int = 0
    var visible: Bool = true
    var style: PTYCursorStyle = .block

    enum PTYCursorStyle: String, Codable {
        case block
        case underline
        case bar
    }
}

/// PTY 终端状态
struct PTYTerminalState {
    private(set) var cols: Int
    private(set) var rows: Int
    var cells: [[PTYCell]]
    var cursor: PTYCursorState
    var scrollback: [[PTYCell]]

    var maxScrollbackLines: Int = 1000

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.cells = Array(repeating: Array(repeating: PTYCell(), count: cols), count: rows)
        self.cursor = PTYCursorState()
        self.scrollback = []
    }

    mutating func resize(cols: Int, rows: Int) {
        guard cols != self.cols || rows != self.rows else { return }

        var newCells = Array(repeating: Array(repeating: PTYCell(), count: cols), count: rows)

        // 复制现有内容
        for y in 0..<min(self.rows, rows) {
            for x in 0..<min(self.cols, cols) {
                newCells[y][x] = cells[y][x]
            }
        }

        self.cells = newCells
        self.cols = cols
        self.rows = rows

        // 调整光标位置
        cursor.x = min(cursor.x, cols - 1)
        cursor.y = min(cursor.y, rows - 1)
    }

    mutating func addToScrollback(_ lines: [[PTYCell]]) {
        for line in lines {
            if scrollback.count >= maxScrollbackLines {
                scrollback.removeFirst()
            }
            scrollback.append(line)
        }
    }

    func getScrollbackLines(count: Int) -> [[PTYCell]] {
        let start = max(0, scrollback.count - count)
        return Array(scrollback[start...])
    }

    // MARK: - 光标控制辅助方法

    mutating func setCursor(x: Int, y: Int) {
        cursor.x = x
        cursor.y = y
    }

    mutating func setCursorX(_ x: Int) {
        cursor.x = x
    }

    mutating func setCursorY(_ y: Int) {
        cursor.y = y
    }
}

/// 脏区域 - 用于增量渲染
struct PTYDirtyRegion: Equatable {
    let x: Int
    let y: Int
    let cols: Int
    let rows: Int

    func contains(_ point: (x: Int, y: Int)) -> Bool {
        point.x >= x && point.x < x + cols &&
        point.y >= y && point.y < y + rows
    }

    func merge(_ other: PTYDirtyRegion) -> PTYDirtyRegion? {
        let x1 = min(x, other.x)
        let y1 = min(y, other.y)
        let x2 = max(x + cols, other.x + other.cols)
        let y2 = max(y + rows, other.y + other.rows)

        // 限制最大区域
        if x2 - x1 > 200 || y2 - y1 > 100 {
            return nil
        }

        return PTYDirtyRegion(x: x1, y: y1, cols: x2 - x1, rows: y2 - y1)
    }
}

// MARK: - 帧消息

/// 终端输出帧
struct TerminalFrame: Codable {
    let sessionId: String
    let sequence: UInt64
    let cols: UInt16
    let rows: UInt16
    let cursorX: UInt16
    let cursorY: UInt16
    let cells: [FrameCell]
    let dirtyRegions: [FrameDirtyRegion]

    struct FrameCell: Codable {
        let x: UInt16
        let y: UInt16
        let char: String
        let fgR: UInt8
        let fgG: UInt8
        let fgB: UInt8
        let bgR: UInt8
        let bgG: UInt8
        let bgB: UInt8
        let attrs: UInt16
    }

    struct FrameDirtyRegion: Codable {
        let x: UInt16
        let y: UInt16
        let cols: UInt16
        let rows: UInt16
    }

    func apply(to state: inout PTYTerminalState) -> [PTYDirtyRegion] {
        var dirtyRegions: [PTYDirtyRegion] = []

        // 调整大小（如果需要）
        if Int(cols) != state.cols || Int(rows) != state.rows {
            state.resize(cols: Int(cols), rows: Int(rows))
        }

        // 应用单元格更新
        for cell in cells {
            let x = Int(cell.x)
            let y = Int(cell.y)

            if y < state.rows && x < state.cols {
                state.cells[y][x] = PTYCell(
                    char: cell.char.first ?? " ",
                    fgColor: PTYColorRGB(r: cell.fgR, g: cell.fgG, b: cell.fgB),
                    bgColor: PTYColorRGB(r: cell.bgR, g: cell.bgG, b: cell.bgB),
                    attrs: PTYCellAttributes(rawValue: cell.attrs)
                )
            }
        }

        // 转换脏区域
        for region in self.dirtyRegions {
            dirtyRegions.append(PTYDirtyRegion(
                x: Int(region.x),
                y: Int(region.y),
                cols: Int(region.cols),
                rows: Int(region.rows)
            ))
        }

        // 更新光标位置
        state.cursor.x = Int(cursorX)
        state.cursor.y = Int(cursorY)

        return dirtyRegions
    }
}

// MARK: - PTY 配置

struct PTYConfig {
    var shell: String = "/bin/bash"
    var args: [String] = ["--login"]
    var env: [(String, String)] = []
    var cols: UInt16 = 80
    var rows: UInt16 = 24

    static let `default` = PTYConfig()
}

// MARK: - PTY 会话

/// PTY 会话错误
enum PTYError: Error, LocalizedError {
    case connectionFailed(String)
    case invalidResponse(String)
    case sessionClosed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .sessionClosed:
            return "Session closed"
        case .writeFailed(let msg):
            return "Write failed: \(msg)"
        }
    }
}

/// PTY 会话协议
protocol PTYSessionDelegate: AnyObject {
    func session(_ session: PTYSession, didReceiveFrame frame: TerminalFrame)
    func session(_ session: PTYSession, didChangeState state: PTYSession.State)
    func session(_ session: PTYSession, didReceiveError error: Error)
}

/// PTY 会话
class PTYSession {
    enum State {
        case disconnected
        case connecting
        case connected
        case failed(Error)
    }

    private(set) var state: State = .disconnected {
        didSet {
            delegate?.session(self, didChangeState: state)
        }
    }

    private(set) var sessionId: String?
    weak var delegate: PTYSessionDelegate?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.vibeterminal.pty")
    private var config: PTYConfig
    private var serverURL: URL
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    init(serverURL: URL, config: PTYConfig = .default) {
        self.serverURL = serverURL
        self.config = config
    }

    // MARK: - 连接管理

    func connect() {
        guard case .disconnected = state else { return }

        state = .connecting

        // 创建 WebSocket 连接
        let wsEndpoint = serverURL.appendingPathComponent("ws").absoluteString
        guard let url = URL(string: wsEndpoint) else {
            state = .failed(PTYError.connectionFailed("Invalid URL"))
            return
        }

        // 使用 URLSessionWebSocketTask
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        // 使用 NWConnection 替代（更适合低级协议）
        setupNWConnection()
    }

    private func setupNWConnection() {
        guard let host = serverURL.host else {
            state = .failed(PTYError.connectionFailed("Invalid host"))
            return
        }

        let portValue: UInt16
        if let port = serverURL.port {
            portValue = UInt16(port)
        } else if serverURL.scheme == "https" {
            portValue = 443
        } else if serverURL.scheme == "http" {
            portValue = 80
        } else {
            portValue = 8080
        }

        guard let port = NWEndpoint.Port(rawValue: portValue) else {
            state = .failed(PTYError.connectionFailed("Invalid port"))
            return
        }

        // 使用 TCP 连接
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: port,
            using: .tcp
        )

        self.connection = connection

        connection.stateUpdateHandler = { [weak self] nwState in
            guard let self = self else { return }

            switch nwState {
            case .ready:
                self.state = .connected
                self.reconnectAttempts = 0
                self.sendHandshake()
                self.startReceive()

            case .failed(let error):
                self.state = .failed(error)
                self.attemptReconnect()

            case .waiting(let error):
                self.state = .failed(PTYError.connectionFailed(error.localizedDescription))

            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func sendHandshake() {
        // 发送握手消息
        let handshake: [String: Any] = [
            "type": "handshake",
            "version": 1,
            "cols": config.cols,
            "rows": config.rows
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: handshake, options: []) else {
            return
        }

        send(data)
    }

    private func startReceive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.handleReceivedData(data)
            }

            if let error = error {
                self.delegate?.session(self, didReceiveError: error)
            }

            if !isComplete {
                self.startReceive()
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        // 解析帧消息
        if let frame = try? JSONDecoder().decode(TerminalFrame.self, from: data) {
            if sessionId == nil {
                sessionId = frame.sessionId
            }
            delegate?.session(self, didReceiveFrame: frame)
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        sessionId = nil
        state = .disconnected
    }

    // MARK: - 发送数据

    func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                self.delegate?.session(self, didReceiveError: PTYError.writeFailed(error.localizedDescription))
            }
        })
    }

    func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            send(data)
        }
    }

    func write(_ bytes: [UInt8]) {
        send(Data(bytes))
    }

    // MARK: - 窗口大小

    func resize(cols: UInt16, rows: UInt16) {
        config.cols = cols
        config.rows = rows

        let resize: [String: Any] = [
            "type": "resize",
            "cols": cols,
            "rows": rows
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: resize, options: []) else {
            return
        }

        send(data)
    }

    // MARK: - 重连

    private func attemptReconnect() {
        reconnectAttempts += 1

        guard reconnectAttempts < maxReconnectAttempts else {
            state = .failed(PTYError.connectionFailed("Max reconnect attempts reached"))
            return
        }

        // 延迟重连
        queue.asyncAfter(deadline: .now() + Double(reconnectAttempts)) { [weak self] in
            self?.connect()
        }
    }
}

// MARK: - 本地 PTY 服务器管理器

/// 本地 PTY 服务器管理器
class LocalPTYServer {
    static let shared = LocalPTYServer()

    private var process: Process?
    private let serverPath: String

    private init() {
        // 默认路径
        serverPath = "/usr/local/bin/vibe-terminal-server"
    }

    var isRunning: Bool {
        guard let process = process else { return false }
        return process.isRunning
    }

    func start(port: UInt16 = 8080) throws {
        guard !isRunning else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)

        // 设置参数
        process.arguments = ["--port", "\(port)"]

        // 设置输出
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // 启动
        try process.run()

        self.process = process

        // 等待服务器启动
        Thread.sleep(forTimeInterval: 0.5)
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    deinit {
        stop()
    }
}
