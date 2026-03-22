//
//  BinaryProtocolEncoder.swift
//  VibeTerminal
//
//  高效二进制协议编码器 - 替代 JSON 序列化
//
//  格式：
//  - [1字节] 帧类型
//  - [4字节] 数据长度（小端序）
//  - [N字节] 二进制数据
//
//  性能优化：
//  - 直接内存操作，避免 JSON 解析
//  - 预分配缓冲区
//  - 使用小端序（跨平台一致）
//

import Foundation

// MARK: - 二进制编码器

final class BinaryProtocolEncoder {
    private var buffer: Data
    private var startPos: Int = 0

    init(capacity: Int = 4096) {
        self.buffer = Data(capacity: capacity)
    }

    // MARK: - 编码帧

    func encodeFrame(_ frame: Frame) -> Data {
        buffer.removeAll(keepingCapacity: false)

        let frameType: UInt8
        var frameData: Data

        switch frame {
        case .input(let sessionId, let data):
            frameType = 0x01
            frameData = encodeInput(sessionId: sessionId, data: data)

        case .subscribe(let sessionIds):
            frameType = 0x02
            frameData = encodeSubscribe(sessionIds)

        case .createSession(let req):
            frameType = 0x03
            frameData = encodeCreateSession(req)

        case .resizeSession(let sessionId, let cols, let rows):
            frameType = 0x04
            frameData = encodeResize(sessionId: sessionId, cols: cols, rows: rows)

        case .closeSession(let sessionId):
            frameType = 0x05
            frameData = encodeCloseSession(sessionId)

        case .sessionOutput(let sessionId, let frame):
            frameType = 0x10
            frameData = encodeSessionOutput(sessionId: sessionId, frame: frame)

        case .cursorUpdate(let cursor):
            frameType = 0x11
            frameData = encodeCursorUpdate(cursor)

        case .modeUpdate(let mode):
            frameType = 0x12
            frameData = encodeModeUpdate(mode)

        case .sessionCreated(let sessionId):
            frameType = 0x13
            frameData = encodeSessionCreated(sessionId)

        case .sessionClosed(let sessionId):
            frameType = 0x14
            frameData = encodeSessionClosed(sessionId)

        case .error(let msg):
            frameType = 0x15
            frameData = encodeError(msg)

        case .ping:
            frameType = 0x20
            frameData = Data()

        case .pong:
            frameType = 0x21
            frameData = Data()
        }

        // 构建完整帧：[类型][长度][数据]
        buffer.append(frameType)
        var len = UInt32(frameData.count).littleEndian
        withUnsafeBytes(of: &len) { buffer.append(contentsOf: $0) }
        buffer.append(frameData)

        return Data(buffer)
    }

    // MARK: - 输入帧编码

    private func encodeInput(sessionId: String, data: Data) -> Data {
        var result = Data()
        result.append(encodeString(sessionId))
        result.append(encodeBytes(data))
        return result
    }

    // MARK: - 订阅帧编码

    private func encodeSubscribe(_ sessionIds: [String]) -> Data {
        var result = Data()
        result.append(encodeUInt16(UInt16(sessionIds.count)))
        for id in sessionIds {
            result.append(encodeString(id))
        }
        return result
    }

    // MARK: - 创建会话帧编码

    private func encodeCreateSession(_ req: CreateSessionRequest) -> Data {
        var result = Data()
        result.append(encodeString(req.command))
        result.append(encodeStringArray(req.args))
        result.append(encodeOptionalString(req.cwd))
        result.append(encodeStringDict(req.env))
        return result
    }

    // MARK: - 调整大小帧编码

    private func encodeResize(sessionId: String, cols: UInt16, rows: UInt16) -> Data {
        var result = Data()
        result.append(encodeString(sessionId))
        result.append(encodeUInt16(cols))
        result.append(encodeUInt16(rows))
        return result
    }

    // MARK: - 关闭会话帧编码

    private func encodeCloseSession(_ sessionId: String) -> Data {
        return encodeString(sessionId)
    }

    // MARK: - 会话输出帧编码

    private func encodeSessionOutput(sessionId: String, frame: ScreenFrame) -> Data {
        var result = Data()
        result.append(encodeString(sessionId))
        result.append(encodeUInt64(frame.seq))
        result.append(encodeUInt16(frame.cols))
        result.append(encodeUInt16(frame.rows))

        // 编码脏区域
        result.append(encodeUInt16(UInt16(frame.dirtyRegions.count)))
        for region in frame.dirtyRegions {
            result.append(encodeDirtyRegion(region))
        }

        return result
    }

    // MARK: - 脏区域编码

    private func encodeDirtyRegion(_ region: ProtocolDirtyRegion) -> Data {
        var result = Data()
        result.append(encodeUInt16(region.x))
        result.append(encodeUInt16(region.y))
        result.append(encodeUInt16(region.width))
        result.append(encodeUInt16(region.height))

        // 编码单元格
        result.append(encodeUInt32(UInt32(region.cells.count)))
        for cell in region.cells {
            result.append(encodeCell(cell))
        }

        return result
    }

    // MARK: - 单元格编码

    private func encodeCell(_ cell: CellData) -> Data {
        var result = Data()

        // 字符（UTF-8）
        result.append(encodeString(cell.char))

        // 前景色
        result.append(encodeColor(cell.fgColor))

        // 背景色
        result.append(encodeColor(cell.bgColor))

        // 属性
        result.append(encodeUInt16(cell.attrs.rawValue))

        return result
    }

    // MARK: - 颜色编码

    private func encodeColor(_ color: Color) -> Data {
        var result = Data()

        switch color {
        case .default:
            result.append(0 as UInt8)

        case .indexed(let v):
            result.append(1 as UInt8)
            result.append(v)

        case .palette(let v):
            result.append(2 as UInt8)
            result.append(v)

        case .rgb(let r, let g, let b):
            result.append(3 as UInt8)
            result.append(r)
            result.append(g)
            result.append(b)
        }

        return result
    }

    // MARK: - 光标更新帧编码

    private func encodeCursorUpdate(_ cursor: CursorFrame) -> Data {
        var result = Data()
        result.append(encodeUInt16(cursor.x))
        result.append(encodeUInt16(cursor.y))
        result.append(cursor.visible ? 1 as UInt8 : 0)
        result.append(cursor.style.rawValue)
        return result
    }

    // MARK: - 模式更新帧编码

    private func encodeModeUpdate(_ mode: ModeFrame) -> Data {
        var result = Data()
        result.append(mode.mode.rawValue)
        result.append(mode.active ? 1 as UInt8 : 0)
        return result
    }

    // MARK: - 会话创建帧编码

    private func encodeSessionCreated(_ sessionId: String) -> Data {
        return encodeString(sessionId)
    }

    // MARK: - 会话关闭帧编码

    private func encodeSessionClosed(_ sessionId: String) -> Data {
        return encodeString(sessionId)
    }

    // MARK: - 错误帧编码

    private func encodeError(_ msg: String) -> Data {
        return encodeString(msg)
    }

    // MARK: - 基础类型编码

    private func encodeUInt8(_ value: UInt8) -> Data {
        return Data([value])
    }

    private func encodeUInt16(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: MemoryLayout<UInt16>.size)
    }

    private func encodeUInt32(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: MemoryLayout<UInt32>.size)
    }

    private func encodeUInt64(_ value: UInt64) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: MemoryLayout<UInt64>.size)
    }

    private func encodeBytes(_ value: Data) -> Data {
        var result = Data()
        var len = UInt32(value.count).littleEndian
        withUnsafeBytes(of: &len) { result.append(contentsOf: $0) }
        result.append(value)
        return result
    }

    private func encodeString(_ value: String) -> Data {
        guard let data = value.data(using: .utf8) else {
            return encodeUInt32(0)
        }
        return encodeBytes(data)
    }

    private func encodeOptionalString(_ value: String?) -> Data {
        guard let v = value else {
            return encodeUInt8(0)
        }
        var result = Data()
        result.append(1 as UInt8)
        result.append(encodeString(v))
        return result
    }

    private func encodeStringArray(_ value: [String]) -> Data {
        var result = Data()
        result.append(encodeUInt16(UInt16(value.count)))
        for s in value {
            result.append(encodeString(s))
        }
        return result
    }

    private func encodeStringDict(_ value: [String: String]?) -> Data {
        guard let dict = value else {
            return encodeUInt8(0)
        }
        var result = Data()
        result.append(1 as UInt8)
        result.append(encodeUInt16(UInt16(dict.count)))
        for (k, v) in dict {
            result.append(encodeString(k))
            result.append(encodeString(v))
        }
        return result
    }
}

// MARK: - 二进制解码器

final class BinaryProtocolDecoder {
    private var data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    var remaining: Int {
        data.count - offset
    }

    // MARK: - 解码帧

    func decodeFrame() throws -> Frame {
        guard remaining >= 5 else {
            throw ProtocolError.incompleteData
        }

        let frameType = data[offset]
        let len = Int(UInt32(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: offset + 1, as: UInt32.self) }))

        offset += 5

        guard remaining >= len else {
            throw ProtocolError.incompleteData
        }

        let frameData = Data(data[offset..<(offset + len)])
        offset += len

        let decoder = BinaryProtocolDecoder(data: frameData)
        return try decoder.decodeFrameData(frameType)
    }

    // MARK: - 解码帧数据

    private func decodeFrameData(_ type: UInt8) throws -> Frame {
        switch type {
        case 0x01: return try decodeInput()
        case 0x02: return try decodeSubscribe()
        case 0x03: return try decodeCreateSession()
        case 0x04: return try decodeResize()
        case 0x05: return try decodeCloseSession()
        case 0x10: return try decodeSessionOutput()
        case 0x11: return try decodeCursorUpdate()
        case 0x12: return try decodeModeUpdate()
        case 0x13: return try decodeSessionCreated()
        case 0x14: return try decodeSessionClosed()
        case 0x15: return try decodeError()
        case 0x20: return .ping
        case 0x21: return .pong
        default:
            throw ProtocolError.unknownFrameType(type)
        }
    }

    // MARK: - 解码各个帧类型

    private func decodeInput() throws -> Frame {
        let sessionId = try decodeString()
        let data = try decodeBytes()
        return .input(sessionId: sessionId, data: data)
    }

    private func decodeSubscribe() throws -> Frame {
        let count = try decodeUInt16()
        var sessionIds: [String] = []
        sessionIds.reserveCapacity(Int(count))
        for _ in 0..<count {
            sessionIds.append(try decodeString())
        }
        return .subscribe(sessionIds)
    }

    private func decodeCreateSession() throws -> Frame {
        let command = try decodeString()
        let args = try decodeStringArray()
        let cwd = try decodeOptionalString()
        let env = try decodeStringDict()
        let req = CreateSessionRequest(command: command, args: args, cwd: cwd, env: env)
        return .createSession(req)
    }

    private func decodeResize() throws -> Frame {
        let sessionId = try decodeString()
        let cols = try decodeUInt16()
        let rows = try decodeUInt16()
        return .resizeSession(sessionId: sessionId, cols: cols, rows: rows)
    }

    private func decodeCloseSession() throws -> Frame {
        let sessionId = try decodeString()
        return .closeSession(sessionId: sessionId)
    }

    private func decodeSessionOutput() throws -> Frame {
        let sessionId = try decodeString()
        let seq = try decodeUInt64()
        let cols = try decodeUInt16()
        let rows = try decodeUInt16()

        let regionCount = try decodeUInt16()
        var regions: [ProtocolDirtyRegion] = []
        regions.reserveCapacity(Int(regionCount))

        for _ in 0..<regionCount {
            regions.append(try decodeDirtyRegion())
        }

        let frame = ScreenFrame(seq: seq, cols: cols, rows: rows, dirtyRegions: regions)
        return .sessionOutput(sessionId: sessionId, frame: frame)
    }

    private func decodeDirtyRegion() throws -> ProtocolDirtyRegion {
        let x = try decodeUInt16()
        let y = try decodeUInt16()
        let width = try decodeUInt16()
        let height = try decodeUInt16()

        let cellCount = try decodeUInt32()
        var cells: [CellData] = []
        cells.reserveCapacity(Int(cellCount))

        for _ in 0..<cellCount {
            cells.append(try decodeCell())
        }

        return ProtocolDirtyRegion(x: x, y: y, width: width, height: height, cells: cells)
    }

    private func decodeCell() throws -> CellData {
        let char = try decodeString()
        let fgColor = try decodeColor()
        let bgColor = try decodeColor()
        let attrsRaw = try decodeUInt16()
        let attrs = CellAttrs(rawValue: attrsRaw)

        return CellData(char: char, fgColor: fgColor, bgColor: bgColor, attrs: attrs)
    }

    private func decodeColor() throws -> Color {
        let type = try decodeUInt8()

        switch type {
        case 0:
            return .default
        case 1:
            let v = try decodeUInt8()
            return .indexed(v)
        case 2:
            let v = try decodeUInt8()
            return .palette(v)
        case 3:
            let r = try decodeUInt8()
            let g = try decodeUInt8()
            let b = try decodeUInt8()
            return .rgb(r: r, g: g, b: b)
        default:
            return .default
        }
    }

    private func decodeCursorUpdate() throws -> Frame {
        let x = try decodeUInt16()
        let y = try decodeUInt16()
        let visible = try decodeUInt8() != 0
        let styleRaw = try decodeUInt8()
        let style = CursorStyle(rawValue: styleRaw) ?? .block

        let cursor = CursorFrame(x: x, y: y, visible: visible, style: style)
        return .cursorUpdate(cursor)
    }

    private func decodeModeUpdate() throws -> Frame {
        let modeRaw = try decodeUInt8()
        let mode = Mode(rawValue: modeRaw) ?? .normal
        let active = try decodeUInt8() != 0

        let modeFrame = ModeFrame(mode: mode, active: active)
        return .modeUpdate(modeFrame)
    }

    private func decodeSessionCreated() throws -> Frame {
        let sessionId = try decodeString()
        return .sessionCreated(sessionId)
    }

    private func decodeSessionClosed() throws -> Frame {
        let sessionId = try decodeString()
        return .sessionClosed(sessionId)
    }

    private func decodeError() throws -> Frame {
        let msg = try decodeString()
        return .error(msg)
    }

    // MARK: - 基础类型解码

    private func decodeUInt8() throws -> UInt8 {
        guard remaining >= 1 else { throw ProtocolError.incompleteData }
        let value = data[offset]
        offset += 1
        return value
    }

    private func decodeUInt16() throws -> UInt16 {
        guard remaining >= 2 else { throw ProtocolError.incompleteData }
        let value = UInt16(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) })
        offset += 2
        return value
    }

    private func decodeUInt32() throws -> UInt32 {
        guard remaining >= 4 else { throw ProtocolError.incompleteData }
        let value = UInt32(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) })
        offset += 4
        return value
    }

    private func decodeUInt64() throws -> UInt64 {
        guard remaining >= 8 else { throw ProtocolError.incompleteData }
        let value = UInt64(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt64.self) })
        offset += 8
        return value
    }

    private func decodeBytes() throws -> Data {
        let len = try decodeUInt32()
        guard remaining >= Int(len) else { throw ProtocolError.incompleteData }
        let value = Data(data[offset..<(offset + Int(len))])
        offset += Int(len)
        return value
    }

    private func decodeString() throws -> String {
        let data = try decodeBytes()
        guard let str = String(data: data, encoding: .utf8) else {
            throw ProtocolError.serializationError("Invalid UTF-8")
        }
        return str
    }

    private func decodeOptionalString() throws -> String? {
        let hasValue = try decodeUInt8()
        return hasValue != 0 ? try decodeString() : nil
    }

    private func decodeStringArray() throws -> [String] {
        let count = try decodeUInt16()
        var result: [String] = []
        result.reserveCapacity(Int(count))
        for _ in 0..<count {
            result.append(try decodeString())
        }
        return result
    }

    private func decodeStringDict() throws -> [String: String]? {
        let hasValue = try decodeUInt8()
        guard hasValue != 0 else { return nil }

        let count = try decodeUInt16()
        var result: [String: String] = [:]
        result.reserveCapacity(Int(count))

        for _ in 0..<count {
            let key = try decodeString()
            let value = try decodeString()
            result[key] = value
        }

        return result
    }
}

// MARK: - 批量解码

extension BinaryProtocolDecoder {
    /// 从数据中解码多个完整帧
    static func decodeFrames(_ data: Data) -> ([Frame], Data) {
        var frames: [Frame] = []
        var remaining = data

        while !remaining.isEmpty {
            // 检查是否有完整的帧头
            guard remaining.count >= 5 else {
                break
            }

            // 读取帧长度
            let len = Int(UInt32(littleEndian: remaining.withUnsafeBytes { $0.load(fromByteOffset: 1, as: UInt32.self) }))
            let frameLen = 5 + len

            // 检查是否有完整的帧
            guard remaining.count >= frameLen else {
                break
            }

            // 解码帧
            let frameData = Data(remaining[0..<frameLen])
            if let decoder = try? BinaryProtocolDecoder(data: frameData) {
                if let frame = try? decoder.decodeFrame() {
                    frames.append(frame)
                }
            }

            remaining = remaining.dropFirst(frameLen)
        }

        return (frames, remaining)
    }
}
