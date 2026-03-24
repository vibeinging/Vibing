//
//  TerminalSyncEngine.swift
//  VibeTerminal
//
//  终端状态同步引擎 - 处理与服务端的同步和帧更新
//

import Foundation
import Combine

// MARK: - Terminal Sync Engine Delegate
protocol TerminalSyncEngineDelegate: AnyObject {
    func syncEngine(_ engine: TerminalSyncEngine, didUpdateRegions regions: [CGRect])
    func syncEngine(_ engine: TerminalSyncEngine, didUpdateCursor position: CGPoint)
    func syncEngine(_ engine: TerminalSyncEngine, sessionDidCreate sessionId: UInt64)
    func syncEngine(_ engine: TerminalSyncEngine, sessionDidClose sessionId: UInt64)
    func syncEngine(_ engine: TerminalSyncEngine, didReceiveError error: Error)
}

// MARK: - Sync Engine Errors
enum SyncEngineError: Error, LocalizedError {
    case notConnected
    case sessionNotCreated
    case invalidFrame
    case sequenceMismatch(expected: UInt64, received: UInt64)
    case sessionClosed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .sessionNotCreated:
            return "Session has not been created"
        case .invalidFrame:
            return "Received invalid frame"
        case .sequenceMismatch(let expected, let received):
            return "Sequence mismatch: expected \(expected), received \(received)"
        case .sessionClosed:
            return "Session has been closed"
        }
    }
}

// MARK: - Terminal Sync Engine
class TerminalSyncEngine: NSObject {

    // MARK: - Properties

    private let webSocketClient: WebSocketClient
    private let terminalState: TerminalState
    private var currentSessionId: UInt64?
    private var expectedSeq: UInt64 = 0

    // 连接状态
    private(set) var isConnected = false
    private(set) var isSessionCreated = false

    // 同步配置
    private let maxSequenceGap: UInt64 = 100  // 最大允许序列号间隔
    private let requestFullStateThreshold: UInt64 = 10  // 丢帧阈值

    // 键盘输入转换表
    private let keyCodes: [KeyPressEvent.KeyType: UInt8] = [
        .enter: 13,
        .tab: 9,
        .backspace: 127,
        .escape: 27,
        .arrowUp: 0x80 + 0,
        .arrowDown: 0x80 + 1,
        .arrowLeft: 0x80 + 2,
        .arrowRight: 0x80 + 3,
        .home: 0x80 + 4,
        .end: 0x80 + 5,
        .pageUp: 0x80 + 6,
        .pageDown: 0x80 + 7,
        .delete: 0x80 + 8,
        .insert: 0x80 + 9
    ]

    // F 键码
    private let fKeyCodes: [UInt8] = [
        0x90,  // F1
        0x91,  // F2
        0x92,  // F3
        0x93,  // F4
        0x94,  // F5
        0x95,  // F6
        0x96,  // F7
        0x97,  // F8
        0x98,  // F9
        0x99,  // F10
        0x9A,  // F11
        0x9B   // F12
    ]

    weak var delegate: TerminalSyncEngineDelegate?

    // MARK: - Initialization

    init(webSocketClient: WebSocketClient, terminalState: TerminalState) {
        self.webSocketClient = webSocketClient
        self.terminalState = terminalState
        super.init()

        // 设置 WebSocket 代理
        webSocketClient.delegate = self
    }

    // MARK: - Connection Management

    /// 连接到指定 URL
    func connect(to url: URL) {
        guard !isConnected else { return }

        // 重置状态
        resetState()

        webSocketClient.connect()
    }

    /// 断开连接
    func disconnect() {
        webSocketClient.disconnect()
        resetState()
    }

    private func resetState() {
        currentSessionId = nil
        expectedSeq = 0
        isSessionCreated = false
        isConnected = false
    }

    // MARK: - Session Management

    /// 创建新的终端会话
    func createSession(cols: UInt16, rows: UInt16) async throws {
        guard isConnected else {
            throw SyncEngineError.notConnected
        }

        // 构建会话创建请求
        var data = Data()
        data.append(0xFF)  // 会话创建命令
        data.append(withUnsafeBytes(of: cols.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: rows.littleEndian) { Data($0) })

        try await sendInput(data)

        // 等待会话创建确认
        // 实际确认通过 didReceiveFrame 回调处理
    }

    /// 关闭当前会话
    func closeSession() {
        guard let sessionId = currentSessionId else { return }

        var data = Data()
        data.append(0xFE)  // 会话关闭命令
        data.append(withUnsafeBytes(of: sessionId.littleEndian) { Data($0) })

        webSocketClient.sendInput(data)
    }

    // MARK: - Input Sending

    /// 发送输入数据
    func sendInput(_ data: Data) async throws {
        guard isConnected, isSessionCreated else {
            throw SyncEngineError.sessionNotCreated
        }

        return try await withCheckedThrowingContinuation { continuation in
            // 包装输入数据
            var packet = Data()
            packet.append(0x01)  // 输入命令
            packet.append(withUnsafeBytes(of: currentSessionId!.littleEndian) { Data($0) })
            packet.append(data)

            webSocketClient.sendInput(packet)
            continuation.resume()
        }
    }

    /// 发送键盘事件
    func sendKey(_ keyCode: UInt8, modifiers: UInt8) async throws {
        guard isConnected, isSessionCreated else {
            throw SyncEngineError.sessionNotCreated
        }

        var data = Data()
        data.append(0x02)  // 键盘命令
        data.append(withUnsafeBytes(of: currentSessionId!.littleEndian) { Data($0) })
        data.append(keyCode)
        data.append(modifiers)

        webSocketClient.sendInput(data)
    }

    /// 处理 UIKit 键盘事件并发送
    func sendKeyPressEvent(_ event: KeyPressEvent) async throws {
        let (keyCode, modifiers) = convertKeyEvent(event)
        try await sendKey(keyCode, modifiers: modifiers)
    }

    // MARK: - Keyboard Input Conversion

    private func convertKeyEvent(_ event: KeyPressEvent) -> (UInt8, UInt8) {
        var modifiers: UInt8 = 0

        if event.modifiers.contains(.control) {
            modifiers |= 0x01
        }
        if event.modifiers.contains(.alt) {
            modifiers |= 0x02
        }
        if event.modifiers.contains(.shift) {
            modifiers |= 0x04
        }
        if event.modifiers.contains(.meta) {
            modifiers |= 0x08
        }

        switch event.key {
        case .character(let char):
            // 普通字符
            let scalar = char.unicodeScalars.first!
            let code = UInt8(scalar.value & 0xFF)
            return (code, modifiers)

        case .f(let index):
            // F1-F12
            let fIndex = min(max(index - 1, 0), fKeyCodes.count - 1)
            return (fKeyCodes[fIndex], modifiers)

        default:
            // 特殊键
            if let keyCode = keyCodes[event.key] {
                return (keyCode, modifiers)
            }
        }

        return (0, modifiers)
    }

    /// 将文本转换为输入数据
    func encodeTextInput(_ text: String) -> Data {
        return text.data(using: .utf8) ?? Data()
    }

    /// 发送文本输入
    func sendTextInput(_ text: String) async throws {
        let data = encodeTextInput(text)
        try await sendInput(data)
    }

    // MARK: - Frame Processing

    private func handleScreenFrame(_ frame: ScreenFrame) {
        // 检查序列号
        if frame.seq != expectedSeq {
            // 检测到丢帧
            let gap: UInt64
            if frame.seq > expectedSeq {
                gap = frame.seq - expectedSeq
            } else {
                // 序列号回滚（可能是服务器重启）
                gap = maxSequenceGap + 1
            }

            if gap > requestFullStateThreshold {
                // 请求完整状态重传
                requestFullState()
                return
            } else if gap <= maxSequenceGap {
                // 小间隔，尝试恢复
                expectedSeq = frame.seq + 1
            }
        } else {
            expectedSeq = frame.seq + 1
        }

        // 调整终端大小（如果需要）
        let newCols = Int(frame.cols)
        let newRows = Int(frame.rows)

        if newCols != terminalState.cols || newRows != terminalState.rows {
            terminalState.resize(cols: newCols, rows: newRows)
        }

        // 应用脏区域
        var dirtyRects: [CGRect] = []

        for region in frame.dirtyRegions {
            applyDirtyRegion(region)

            // 转换为 CGRect
            let cellWidth: CGFloat = 1.0 / CGFloat(terminalState.cols)
            let cellHeight: CGFloat = 1.0 / CGFloat(terminalState.rows)

            let rect = CGRect(
                x: CGFloat(region.x) * cellWidth,
                y: CGFloat(region.y) * cellHeight,
                width: CGFloat(region.width) * cellWidth,
                height: CGFloat(region.height) * cellHeight
            )
            dirtyRects.append(rect)
        }

        // 通知代理
        if !dirtyRects.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.syncEngine(self!, didUpdateRegions: dirtyRects)
            }
        }
    }

    private func applyDirtyRegion(_ region: ProtocolDirtyRegion) {
        let startX = Int(region.x)
        let startY = Int(region.y)
        let width = Int(region.width)
        let height = Int(region.height)

        for dy in 0..<height {
            let y = startY + dy
            guard y < terminalState.rows else { continue }

            for dx in 0..<width {
                let x = startX + dx
                guard x < terminalState.cols else { continue }

                let cellIndex = dy * Int(width) + dx
                guard cellIndex < region.cells.count else { continue }

                let cellData = region.cells[cellIndex]
                var cell = TerminalCell()
                cell.char = cellData.char.isEmpty ? " " : Character(cellData.char.first ?? " ")
                cell.fgColor = cellData.fgRGBA
                cell.bgColor = cellData.bgRGBA
                cell.attrs = cellData.attrs.rawValue

                terminalState.setCell(cell, atX: x, y: y)
            }
        }
    }

    private func handleCursorFrame(_ frame: CursorFrame) {
        terminalState.setCursor(x: Int(frame.x), y: Int(frame.y))
        terminalState.setCursorVisible(frame.visible)

        switch frame.style {
        case 0:
            terminalState.setCursorStyle(.block)
        case 1:
            terminalState.setCursorStyle(.underline)
        case 2:
            terminalState.setCursorStyle(.bar)
        default:
            terminalState.setCursorStyle(.block)
        }

        // 计算光标位置（归一化坐标）
        let cellWidth: CGFloat = 1.0 / CGFloat(terminalState.cols)
        let cellHeight: CGFloat = 1.0 / CGFloat(terminalState.rows)

        let position = CGPoint(
            x: CGFloat(frame.x) * cellWidth + cellWidth / 2,
            y: CGFloat(frame.y) * cellHeight + cellHeight / 2
        )

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.syncEngine(self!, didUpdateCursor: position)
        }
    }

    private func handleModeFrame(_ frame: ModeFrame) {
        // 模式变化通知
        // 可以扩展代理方法来处理模式变化
        print("Mode changed: \(frame.mode), active: \(frame.active)")
    }

    private func handleFullStateFrame(_ frame: FullStateFrame) {
        let newCols = Int(frame.cols)
        let newRows = Int(frame.rows)

        // 调整终端大小
        if newCols != terminalState.cols || newRows != terminalState.rows {
            terminalState.resize(cols: newCols, rows: newRows)
        }

        // 导入完整状态
        var cellGrid: [[TerminalCell]] = Array(
            repeating: Array(repeating: TerminalCell(), count: newCols),
            count: newRows
        )

        for (index, cellData) in frame.cells.enumerated() {
            let y = index / newCols
            let x = index % newCols

            guard y < newRows, x < newCols else { continue }

            var cell = TerminalCell()
            cell.char = cellData.char.isEmpty ? " " : Character(cellData.char.first ?? " ")
            cell.fgColor = cellData.fgRGBA
            cell.bgColor = cellData.bgRGBA
            cell.attrs = cellData.attrs.rawValue

            cellGrid[y][x] = cell
        }

        terminalState.importAllCells(cellGrid, cols: newCols, rows: newRows)

        // 更新光标
        terminalState.setCursor(x: Int(frame.cursor.x), y: Int(frame.cursor.y))
        terminalState.setCursorVisible(frame.cursor.visible)

        // 更新序列号
        expectedSeq = frame.seq + 1

        // 通知代理 - 整个屏幕更新
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.syncEngine(
                self!,
                didUpdateRegions: [CGRect(x: 0, y: 0, width: 1, height: 1)]
            )
        }
    }

    private func handleSessionCreated(_ sessionId: UInt64) {
        currentSessionId = sessionId
        isSessionCreated = true

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.syncEngine(self!, sessionDidCreate: sessionId)
        }
    }

    private func handleSessionClosed(_ sessionId: UInt64) {
        guard currentSessionId == sessionId else { return }

        currentSessionId = nil
        isSessionCreated = false

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.syncEngine(self!, sessionDidClose: sessionId)
        }
    }

    private func requestFullState() {
        guard let sessionId = currentSessionId else { return }

        var data = Data()
        data.append(0xFD)  // 请求完整状态
        data.append(withUnsafeBytes(of: sessionId.littleEndian) { Data($0) })

        webSocketClient.sendInput(data)
    }

    // MARK: - Ping/Pong

    private func sendPong() {
        var data = Data()
        data.append(UInt8(FrameType.pong.rawValue))
        webSocketClient.sendInput(data)
    }
}

// MARK: - WebSocketClientDelegate
extension TerminalSyncEngine: WebSocketClientDelegate {

    func didConnect() {
        isConnected = true
        print("TerminalSyncEngine: Connected to server")
    }

    func didDisconnect(error: Error?) {
        isConnected = false
        isSessionCreated = false
        currentSessionId = nil

        if let error = error {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.syncEngine(self!, didReceiveError: error)
            }
        }
    }

    func didReceiveFrame(_ frame: Any) {
        if let screenFrame = frame as? ScreenFrame {
            handleScreenFrame(screenFrame)
        } else if let cursorFrame = frame as? CursorFrame {
            handleCursorFrame(cursorFrame)
        } else if let modeFrame = frame as? ModeFrame {
            handleModeFrame(modeFrame)
        } else if let fullStateFrame = frame as? FullStateFrame {
            handleFullStateFrame(fullStateFrame)
        } else if let ping = frame as? String, ping == "ping" {
            sendPong()
        }
    }

    func didReceiveData(_ data: Data) {
        // 处理原始数据（可能是会话事件）
        guard data.count > 0 else { return }

        let command = data[0]

        switch command {
        case 0xFC:  // Session Created
            if data.count >= 9 {
                let sessionId = data.subdata(in: 1..<9).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
                handleSessionCreated(sessionId)
            }

        case 0xFB:  // Session Closed
            if data.count >= 9 {
                let sessionId = data.subdata(in: 1..<9).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
                handleSessionClosed(sessionId)
            }

        default:
            break
        }
    }
}

// MARK: - Data Extension for Little Endian
private extension Data {
    func toUInt64LE() -> UInt64 {
        guard count >= 8 else { return 0 }
        return subdata(in: 0..<8).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
    }
}
