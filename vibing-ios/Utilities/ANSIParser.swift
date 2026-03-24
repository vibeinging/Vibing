//
//  ANSIParser.swift
//  VibeTerminal
//
//  ANSI 转义序列解析器
//

import Foundation

class ANSIParser {

    // MARK: - 解析结果
    enum ParseAction {
        case print(Character)
        case cursorMove(Int, Int)           // x, y
        case cursorUp(Int)
        case cursorDown(Int)
        case cursorForward(Int)
        case cursorBack(Int)
        case clearScreen
        case clearLine
        case clearToEnd
        case setFgColor(UInt8, UInt8, UInt8)
        case setBgColor(UInt8, UInt8, UInt8)
        case setDefaultColor
        case setStyle(UInt16)              // 样式标志
        case resetStyle
        case scrollUp(Int)
        case scrollDown(Int)
        case newline
        case carriageReturn
        case bell
        case tab
        case backspace
    }

    // MARK: - 解析状态
    private enum State {
        case normal
        case escape
        case csi    // Control Sequence Introducer
        case osc    // Operating System Command
        case dcs    // Device Control String
    }

    private var state: State = .normal
    private var buffer: String = ""

    // 当前样式
    private(set) var currentFgColor: (UInt8, UInt8, UInt8) = (212, 212, 212)
    private(set) var currentBgColor: (UInt8, UInt8, UInt8) = (28, 28, 28)
    private(set) var currentStyle: UInt16 = 0

    // MARK: - 公共接口
    func parse(_ text: String) -> [ParseAction] {
        var actions: [ParseAction] = []

        for char in text {
            actions.append(contentsOf: parse(char))
        }

        return actions
    }

    // MARK: - 核心解析
    private func parse(_ char: Character) -> [ParseAction] {
        switch state {
        case .normal:
            return parseNormal(char)

        case .escape:
            return parseEscape(char)

        case .csi:
            return parseCSI(char)

        case .osc:
            return parseOSC(char)

        case .dcs:
            return parseDCS(char)
        }
    }

    private func parseNormal(_ char: Character) -> [ParseAction] {
        switch char {
        case "\u{1B}":  // ESC
            state = .escape
            buffer = ""
            return []

        case "\n":
            return [.newline]

        case "\r":
            return [.carriageReturn]

        case "\t":
            return [.tab]

        case "\u{7}":  // BEL
            return [.bell]

        case "\u{8}":  // BS
            return [.backspace]

        default:
            return [.print(char)]
        }
    }

    private func parseEscape(_ char: Character) -> [ParseAction] {
        buffer.append(char)

        // 检查完整的转义序列
        if let sequence = parseEscapeSequence(buffer) {
            buffer = ""
            state = .normal
            return sequence
        }

        // 超过合理长度，重置
        if buffer.count > 10 {
            buffer = ""
            state = .normal
            return []
        }

        return []
    }

    private func parseCSI(_ char: Character) -> [ParseAction] {
        buffer.append(char)

        // CSI 序列以 ... 结尾
        if char == "@" || (char >= "A" && char <= "z") || (char >= "a" && char <= "z") {
            let actions = parseCSISequence(buffer)
            buffer = ""
            state = .normal
            return actions
        }

        return []
    }

    private func parseOSC(_ char: Character) -> [ParseAction] {
        // OSC 以 ... ST (\u{9C}) 或 BEL (\u{7}) 结束
        if char == "\u{9C}" || char == "\u{7}" {
            // TODO: 解析 OSC 序列
            buffer = ""
            state = .normal
        } else {
            buffer.append(char)
        }

        return []
    }

    private func parseDCS(_ char: Character) -> [ParseAction] {
        // DCS 以 ... ST (\u{9C}) 结束
        if char == "\u{9C}" {
            // TODO: 解析 DCS 序列
            buffer = ""
            state = .normal
        } else {
            buffer.append(char)
        }

        return []
    }

    // MARK: - 转义序列解析
    private func parseEscapeSequence(_ seq: String) -> [ParseAction]? {
        if seq.count < 2 {
            return nil
        }

        let index = seq.index(seq.startIndex, offsetBy: 1)
        let second = seq[index]

        switch second {
        case "[":
            state = .csi
            return nil

        case "]":
            state = .osc
            return nil

        case "P":
            state = .dcs
            return nil

        case "M":
            // 设置颜色
            if seq.count == 5 {
                let r = UInt8(seq[seq.index(seq.startIndex, offsetBy: 2)])
                let g = UInt8(seq[seq.index(seq.startIndex, offsetBy: 3)])
                let b = UInt8(seq[seq.index(seq.startIndex, offsetBy: 4)])
                return [.setFgColor(r, g, b)]
            }

        default:
            // 其他转义序列
            return []
        }
    }

    private func parseCSISequence(_ seq: String) -> [ParseAction] {
        guard seq.last == "[" else {
            return []
        }

        // 提取参数和命令
        let params = seq.dropFirst().dropLast()
        let parts = params.components(separatedBy: ";")
        let command = seq.last!

        return interpretCSI(parts: parts, command: command)
    }

    private func interpretCSI(parts: [String], command: Character) -> [ParseAction] {
        let p1 = parts.count > 0 ? Int(parts[0]) : nil

        switch command {
        case "A":  // 光标上移
            let n = p1 ?? 1
            return [.cursorUp(n)]

        case "B":  // 光标下移
            let n = p1 ?? 1
            return [.cursorDown(n)]

        case "C":  // 光标前移
            let n = p1 ?? 1
            return [.cursorForward(n)]

        case "D":  // 光标后退
            let n = p1 ?? 1
            return [.cursorBack(n)]

        case "E":  // 光标移到下一行开头
            return [.carriageReturn, .cursorDown(p1 ?? 1)]

        case "F":  // 光标移到上一行开头
            return [.carriageReturn, .cursorUp(p1 ?? 1)]

        case "G":  // 设置列位置
            let n = p1 ?? 1
            return [.cursorMove(n - 1, 0)]

        case "H", "f":  // 设置光标位置
            let row = p1 ?? 1
            let col = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
            return [.cursorMove(col - 1, row - 1)]

        case "J":  // 清屏
            let n = p1 ?? 0
            switch n {
            case 0: return [.clearToEnd]
            case 1: return [.clearLine]
            case 2: return [.clearScreen]
            case 3: return [.clearScreen]
            default: return []
            }

        case "K":  // 清除行
            let n = p1 ?? 0
            switch n {
            case 0: return [.clearToEnd]
            case 1: return [.clearLine]
            case 2: return [.clearLine]
            default: return []
            }

        case "m":  // 设置样式/颜色
            return parseSGR(parts: parts)

        case "r":  // 滚动
            let n = p1 ?? 1
            return n > 0 ? [.scrollDown(n)] : [.scrollUp(abs(n))]

        default:
            return []
        }
    }

    // MARK: - SGR 解析
    private func parseSGR(parts: [String]) -> [ParseAction] {
        var actions: [ParseAction] = []

        for part in parts {
            guard let code = Int(part) else { continue }

            switch code {
            case 0:
                actions.append(.resetStyle)
                actions.append(.setDefaultColor)

            case 1:
                currentStyle.insert(.bold)
                actions.append(.setStyle(currentStyle))

            case 3:
                currentStyle.insert(.italic)
                actions.append(.setStyle(currentStyle))

            case 4:
                currentStyle.insert(.underline)
                actions.append(.setStyle(currentStyle))

            case 7:
                currentStyle.insert(.reverse)
                actions.append(.setStyle(currentStyle))

            case 22:
                currentStyle.remove(.bold)
                actions.append(.setStyle(currentStyle))

            case 23:
                currentStyle.remove(.italic)
                currentStyle.remove(.underline)
                actions.append(.setStyle(currentStyle))

            case 27:
                currentStyle.remove(.reverse)
                actions.append(.setStyle(currentStyle))

            case 30...37:
                let color = ansiColor(code - 30)
                currentFgColor = color
                actions.append(.setFgColor(color.0, color.1, color.2))

            case 38:
                // 真彩色或256色
                if parts.count > 1 {
                    let mode = parts[1]
                    if mode == "5" && parts.count > 2 {
                        // 256色
                        if let colorCode = Int(parts[2]) {
                            let color = indexedColor(colorCode)
                            currentFgColor = color
                            actions.append(.setFgColor(color.0, color.1, color.2))
                        }
                    } else if mode == "2" && parts.count > 4 {
                        // 真彩色
                        if let r = UInt8(parts[2]),
                           let g = UInt8(parts[3]),
                           let b = UInt8(parts[4]) {
                            currentFgColor = (r, g, b)
                            actions.append(.setFgColor(r, g, b))
                        }
                    }
                }

            case 39:
                actions.append(.setDefaultColor)

            case 40...47:
                let color = ansiColor(code - 40)
                currentBgColor = color
                actions.append(.setBgColor(color.0, color.1, color.2))

            case 48:
                // 背景色，类似前景色
                if parts.count > 1 {
                    let mode = parts[1]
                    if mode == "5" && parts.count > 2 {
                        if let colorCode = Int(parts[2]) {
                            let color = indexedColor(colorCode)
                            currentBgColor = color
                            actions.append(.setBgColor(color.0, color.1, color.2))
                        }
                    } else if mode == "2" && parts.count > 4 {
                        if let r = UInt8(parts[2]),
                           let g = UInt8(parts[3]),
                           let b = UInt8(parts[4]) {
                            currentBgColor = (r, g, b)
                            actions.append(.setBgColor(r, g, b))
                        }
                    }
                }

            case 49:
                actions.append(.setDefaultColor)

            default:
                break
            }
        }

        return actions
    }

    // MARK: - 辅助方法
    private func ansiColor(_ index: UInt8) -> (UInt8, UInt8, UInt8) {
        let colors: [(UInt8, UInt8, UInt8)] = [
            (0x00, 0x00, 0x00),   // 黑
            (0xcd, 0x00, 0x00),   // 红
            (0x00, 0xcd, 0x00),   // 绿
            (0xcd, 0xcd, 0x00),   // 黄
            (0x00, 0x00, 0xee),   // 蓝
            (0xcd, 0x00, 0xcd),   // 品红
            (0x00, 0xcd, 0xcd),   // 青
            (0xe5, 0xe5, 0xe5),   // 白
        ]

        if index < 8 {
            return colors[Int(index)]
        } else {
            // 高亮度（简单处理）
            return colors[Int(index - 8)]
        }
    }

    private func indexedColor(_ index: Int) -> (UInt8, UInt8, UInt8) {
        // 256 色模式
        if index < 16 {
            return ansiColor(UInt8(index))
        } else if index < 232 {
            // 6x6x6 cube
            let n = index - 16
            let r = (n / 36) % 6
            let g = (n / 6) % 6
            let b = n % 6

            let v: [UInt8] = [0, 0x5f, 0x87, 0xaf, 0xd7, 0xff]
            return (v[r], v[g], v[b])
        } else {
            // 灰度
            let n = index - 232
            let v = 8 + n * 10
            return (UInt8(v), UInt8(v), UInt8(v))
        }
    }

    // MARK: - 样式操作
    private struct Attrs {
        static let bold: UInt16 = 1 << 0
        static let italic: UInt16 = 1 << 1
        static let underline: UInt16 = 1 << 2
        static let reverse: UInt16 = 1 << 3
        static let blink: UInt16 = 1 << 4

        static func has(_ attrs: UInt16, _ flag: UInt16) -> Bool {
            return (attrs & flag) != 0
        }

        static func insert(_ attrs: inout UInt16, _ flag: UInt16) {
            attrs |= flag
        }

        static func remove(_ attrs: inout UInt16, _ flag: UInt16) {
            attrs &= ~flag
        }
    }
}
