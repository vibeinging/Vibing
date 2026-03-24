//
//  BinaryProtocolEncoder.swift
//  VibeTerminal
//
//  协议编码器/解码器 - 使用 JSON payload 与 Rust serde_json 兼容
//
//  帧格式：
//  - [1字节] 帧类型
//  - [4字节] 数据长度（小端序）
//  - [N字节] JSON 数据
//

import Foundation

// MARK: - 编码器

final class BinaryProtocolEncoder {

    func encodeFrame(_ frame: Frame) -> Data {
        let frameType: UInt8
        let jsonPayload: Any

        switch frame {
        case .input(let sessionId, let data):
            frameType = 0x01
            // serde_json: {"Input": ["sessionId", [bytes]]}
            jsonPayload = ["Input": [sessionId, Array(data)] as [Any]]

        case .subscribe(let sessionIds):
            frameType = 0x02
            jsonPayload = ["Subscribe": sessionIds]

        case .createSession(let req):
            frameType = 0x03
            var reqDict: [String: Any] = [
                "command": req.command,
                "args": req.args
            ]
            if let cwd = req.cwd {
                reqDict["cwd"] = cwd
            } else {
                reqDict["cwd"] = NSNull()
            }
            if let env = req.env {
                let envPairs = env.map { [$0.key, $0.value] }
                reqDict["env"] = envPairs
            } else {
                reqDict["env"] = NSNull()
            }
            jsonPayload = ["CreateSession": reqDict]

        case .resizeSession(let sessionId, let cols, let rows):
            frameType = 0x04
            jsonPayload = ["ResizeSession": [sessionId, cols, rows] as [Any]]

        case .closeSession(let sessionId):
            frameType = 0x05
            jsonPayload = ["CloseSession": sessionId]

        case .ping:
            frameType = 0x20
            jsonPayload = "Ping"

        case .pong:
            frameType = 0x21
            jsonPayload = "Pong"

        // 以下帧类型通常只由服务端发送，客户端不需要编码
        case .sessionOutput, .cursorUpdate, .modeUpdate, .sessionCreated, .sessionClosed, .error, .rawOutput:
            frameType = 0xFF
            jsonPayload = NSNull()
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: jsonPayload)) ?? Data()

        // 构建帧：[type][length LE][json_data]
        var result = Data(capacity: 5 + jsonData.count)
        result.append(frameType)
        var len = UInt32(jsonData.count).littleEndian
        withUnsafeBytes(of: &len) { result.append(contentsOf: $0) }
        result.append(jsonData)

        return result
    }
}

// MARK: - 解码器

final class BinaryProtocolDecoder {
    private var data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    var remaining: Int {
        data.count - offset
    }

    func decodeFrame() throws -> Frame {
        guard remaining >= 5 else {
            throw ProtocolError.incompleteData
        }

        let frameType = data[data.startIndex + offset]
        let lenOffset = data.startIndex + offset + 1
        // Safe unaligned read
        var rawLen: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &rawLen) { dest in
            data.copyBytes(to: dest, from: lenOffset..<lenOffset+4)
        }
        let len = Int(UInt32(littleEndian: rawLen))

        offset += 5

        guard remaining >= len else {
            throw ProtocolError.incompleteData
        }

        let payloadStart = data.startIndex + offset
        let frameData = data[payloadStart..<payloadStart + len]
        offset += len

        // RawOutput 使用自定义二进制编码（非 JSON）
        if frameType == 0x16 {
            return try decodeRawOutput(Data(frameData))
        }

        return try decodeJSONPayload(frameType, data: Data(frameData))
    }

    /// 解码 RawOutput 帧（自定义二进制格式）
    /// 格式: [2B session_id_len][session_id bytes][raw PTY bytes]
    private func decodeRawOutput(_ data: Data) throws -> Frame {
        guard data.count >= 2 else {
            throw ProtocolError.incompleteData
        }
        let sidLen = Int(UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8))
        guard data.count >= 2 + sidLen else {
            throw ProtocolError.incompleteData
        }
        let sessionId = String(data: data[data.startIndex + 2 ..< data.startIndex + 2 + sidLen], encoding: .utf8) ?? ""
        let rawData = data[data.startIndex + 2 + sidLen ..< data.endIndex]
        return .rawOutput(sessionId: sessionId, data: Data(rawData))
    }

    /// 从 serde_json 格式的 JSON 解码帧
    private func decodeJSONPayload(_ type: UInt8, data: Data) throws -> Frame {
        // Ping/Pong 特殊处理
        if type == 0x20 { return .ping }
        if type == 0x21 { return .pong }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // 尝试作为简单字符串解析 (如 "Ping")
            if let str = String(data: data, encoding: .utf8) {
                if str.contains("Ping") { return .ping }
                if str.contains("Pong") { return .pong }
            }
            throw ProtocolError.serializationError("Invalid JSON payload")
        }

        // 根据 serde_json enum 格式解析
        if let sessionId = json["SessionCreated"] as? String {
            return .sessionCreated(sessionId)
        }
        if let sessionId = json["SessionClosed"] as? String {
            return .sessionClosed(sessionId)
        }
        if let msg = json["Error"] as? String {
            return .error(msg)
        }

        if let arr = json["SessionOutput"] as? [Any],
           let sessionId = arr.first as? String,
           let frameDict = arr[safe: 1] as? [String: Any] {
            let screenFrame = try decodeScreenFrame(frameDict)
            return .sessionOutput(sessionId: sessionId, frame: screenFrame)
        }

        if let cursorDict = json["CursorUpdate"] as? [String: Any] {
            let cursor = try decodeCursorFrame(cursorDict)
            return .cursorUpdate(cursor)
        }

        if let modeDict = json["ModeUpdate"] as? [String: Any] {
            let mode = try decodeModeFrame(modeDict)
            return .modeUpdate(mode)
        }

        if let arr = json["Input"] as? [Any],
           let sessionId = arr.first as? String {
            let bytes = (arr[safe: 1] as? [UInt8]) ?? []
            return .input(sessionId: sessionId, data: Data(bytes))
        }

        if let sessionIds = json["Subscribe"] as? [String] {
            return .subscribe(sessionIds)
        }

        throw ProtocolError.unknownFrameType(type)
    }

    // MARK: - Screen Frame 解码

    private func decodeScreenFrame(_ dict: [String: Any]) throws -> ScreenFrame {
        let seq = (dict["seq"] as? NSNumber)?.uint64Value ?? 0
        let cols = (dict["cols"] as? NSNumber)?.uint16Value ?? 80
        let rows = (dict["rows"] as? NSNumber)?.uint16Value ?? 24
        let regionsArray = dict["dirty_regions"] as? [[String: Any]] ?? []

        let dirtyRegions = try regionsArray.map { regionDict -> ProtocolDirtyRegion in
            let x = (regionDict["x"] as? NSNumber)?.uint16Value ?? 0
            let y = (regionDict["y"] as? NSNumber)?.uint16Value ?? 0
            let width = (regionDict["width"] as? NSNumber)?.uint16Value ?? 0
            let height = (regionDict["height"] as? NSNumber)?.uint16Value ?? 0
            let cellsArray = regionDict["cells"] as? [[String: Any]] ?? []

            let cells = try cellsArray.map { cellDict -> ProtocolCellData in
                try decodeCellData(cellDict)
            }

            return ProtocolDirtyRegion(x: x, y: y, width: width, height: height, cells: cells)
        }

        return ScreenFrame(seq: seq, cols: cols, rows: rows, dirtyRegions: dirtyRegions)
    }

    private func decodeCellData(_ dict: [String: Any]) throws -> ProtocolCellData {
        let char = dict["char"] as? String ?? " "

        let fgColor: Color
        if let fgDict = dict["fg_color"] as? [String: Any] {
            fgColor = decodeColor(fgDict)
        } else if let fg = dict["fg_color"] as? String, fg == "Default" {
            fgColor = .default
        } else {
            fgColor = .default
        }

        let bgColor: Color
        if let bgDict = dict["bg_color"] as? [String: Any] {
            bgColor = decodeColor(bgDict)
        } else if let bg = dict["bg_color"] as? String, bg == "Default" {
            bgColor = .default
        } else {
            bgColor = .default
        }

        let attrsRaw = (dict["attrs"] as? [String: Any])?["bits"] as? UInt16 ?? 0
        let attrs = CellAttrs(rawValue: attrsRaw)

        return CellData(char: char, fgColor: fgColor, bgColor: bgColor, attrs: attrs)
    }

    private func decodeColor(_ dict: [String: Any]) -> Color {
        if let idx = dict["Indexed"] as? UInt8 {
            return .indexed(idx)
        }
        if let idx = (dict["Indexed"] as? NSNumber)?.uint8Value {
            return .indexed(idx)
        }
        if let idx = dict["Palette"] as? UInt8 {
            return .palette(idx)
        }
        if let idx = (dict["Palette"] as? NSNumber)?.uint8Value {
            return .palette(idx)
        }
        if let rgbDict = dict["Rgb"] as? [String: Any] {
            let r = (rgbDict["r"] as? NSNumber)?.uint8Value ?? 0
            let g = (rgbDict["g"] as? NSNumber)?.uint8Value ?? 0
            let b = (rgbDict["b"] as? NSNumber)?.uint8Value ?? 0
            return .rgb(r: r, g: g, b: b)
        }
        return .default
    }

    private func decodeCursorFrame(_ dict: [String: Any]) throws -> CursorFrame {
        let x = (dict["x"] as? NSNumber)?.uint16Value ?? 0
        let y = (dict["y"] as? NSNumber)?.uint16Value ?? 0
        let visible = dict["visible"] as? Bool ?? true

        let style: CursorStyle
        if let styleDict = dict["style"] as? String {
            switch styleDict {
            case "Block": style = .block
            case "Underline": style = .underline
            case "Bar": style = .bar
            default: style = .block
            }
        } else if let styleRaw = (dict["style"] as? NSNumber)?.uint8Value {
            style = CursorStyle(rawValue: styleRaw) ?? .block
        } else {
            style = .block
        }

        return CursorFrame(x: x, y: y, visible: visible, style: style)
    }

    private func decodeModeFrame(_ dict: [String: Any]) throws -> ModeFrame {
        let modeRaw = (dict["mode"] as? NSNumber)?.uint8Value ?? 0
        let mode = Mode(rawValue: modeRaw) ?? .normal
        let active = dict["active"] as? Bool ?? true
        return ModeFrame(mode: mode, active: active)
    }
}

// MARK: - 批量解码

extension BinaryProtocolDecoder {
    static func decodeFrames(_ data: Data) -> ([Frame], Data) {
        var frames: [Frame] = []
        var remaining = data

        while !remaining.isEmpty {
            guard remaining.count >= 5 else { break }

            let lenStart = remaining.startIndex + 1
            var rawLen: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &rawLen) { dest in
                remaining.copyBytes(to: dest, from: lenStart..<lenStart+4)
            }
            let len = Int(UInt32(littleEndian: rawLen))
            let frameLen = 5 + len

            guard remaining.count >= frameLen else { break }

            let frameData = Data(remaining[remaining.startIndex..<remaining.startIndex + frameLen])
            let decoder = BinaryProtocolDecoder(data: frameData)
            if let frame = try? decoder.decodeFrame() {
                frames.append(frame)
            }

            remaining = Data(remaining.dropFirst(frameLen))
        }

        return (frames, remaining)
    }
}
