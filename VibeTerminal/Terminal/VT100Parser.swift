//
//  VT100Parser.swift
//  VibeTerminal
//
//  VT100/ANSI 转义序列解析器
//

import Foundation

// MARK: - 解析动作

enum VT100Action {
    // 字符输出
    case print(Character)

    // 光标移动
    case cursorUp(Int)
    case cursorDown(Int)
    case cursorForward(Int)
    case cursorBackward(Int)
    case cursorNextLine(Int)
    case cursorPreviousLine(Int)
    case cursorHorizontalAbsolute(Int)
    case cursorPosition(Int, Int)  // row, col (1-based)
    case saveCursor
    case restoreCursor

    // 屏幕编辑
    case eraseDisplay(EraseMode)
    case eraseLine(EraseLineMode)
    case insertLines(Int)
    case deleteLines(Int)
    case deleteChars(Int)
    case eraseChars(Int)
    case insertChars(Int)

    // 滚动
    case scrollUp(Int)
    case scrollDown(Int)
    case setScrollRegion(Int, Int)  // top, bottom (1-based)

    // 属性设置
    case setGraphics([Int])  // SGR 参数
    case resetGraphics

    // 模式设置
    case setMode(Bool, [Int])  // private, params

    // 设备属性
    case deviceAttributes
    case queryCursorPosition

    // 标签
    case setWindowTitle(String)
    case setIconName(String)

    // 控制字符
    case bell
    case backspace
    case tab
    case lineFeed
    case carriageReturn
    case shiftOut
    case shiftIn

    // 特殊
    case newline
    case ignore
}

/// 清除屏幕模式
enum EraseMode {
    case toEnd      // 从光标到屏幕末尾
    case fromStart  // 从屏幕开始到光标
    case all        // 整个屏幕
    case savedLines // 包括滚动缓冲
}

/// 清除行模式
enum EraseLineMode {
    case toEnd      // 从光标到行尾
    case fromStart  // 从行首到光标
    case all        // 整行
}

// MARK: - VT100 解析器

class VT100Parser {
    // MARK: - 属性

    private(set) var state: PTYTerminalState
    private var parserState: ParserState = .ground
    private var paramsBuffer: String = ""
    private var stringBuffer: String = ""
    private var escapeBuffer: [UInt8] = []

    // 保存的光标状态
    private var savedCursor: SavedCursorState = SavedCursorState()

    // 当前属性
    private(set) var currentFGColor: PTYColorRGB = .defaultFG
    private(set) var currentBGColor: PTYColorRGB = .defaultBG
    private(set) var currentAttributes: PTYCellAttributes = []

    // MARK: - 初始化

    init(cols: Int, rows: Int) {
        self.state = PTYTerminalState(cols: cols, rows: rows)
    }

    // MARK: - 公共接口

    /// 处理输入数据，返回脏区域
    func process(_ data: Data) -> [PTYDirtyRegion] {
        var actions: [VT100Action] = []
        var dirtyRegions: [PTYDirtyRegion] = []

        for byte in data {
            actions.append(contentsOf: processByte(byte))
        }

        // 应用所有动作
        for action in actions {
            if let regions = applyAction(action) {
                dirtyRegions.append(contentsOf: regions)
            }
        }

        return mergeDirtyRegions(dirtyRegions)
    }

    /// 处理字符串
    func process(_ string: String) -> [PTYDirtyRegion] {
        if let data = string.data(using: .utf8) {
            return process(data)
        }
        return []
    }

    /// 重置解析器状态
    func reset() {
        parserState = .ground
        paramsBuffer = ""
        stringBuffer = ""
        escapeBuffer = []
        state = PTYTerminalState(cols: state.cols, rows: state.rows)
        currentFGColor = .defaultFG
        currentBGColor = .defaultBG
        currentAttributes = []
        savedCursor = SavedCursorState()
    }

    /// 调整终端大小
    func resize(cols: Int, rows: Int) {
        state.resize(cols: cols, rows: rows)
    }

    // MARK: - 字节处理

    private func processByte(_ byte: UInt8) -> [VT100Action] {
        switch parserState {
        case .ground:
            return processGround(byte)

        case .escape:
            return processEscape(byte)

        case .escapeIntermediate:
            return processEscapeIntermediate(byte)

        case .csiEntry:
            return processCsiEntry(byte)

        case .csiParam:
            return processCsiParam(byte)

        case .csiIntermediate:
            return processCsiIntermediate(byte)

        case .csiIgnore:
            return processCsiIgnore(byte)

        case .oscString:
            return processOscString(byte)

        case .dcsEntry, .dcsParam, .dcsPassthrough, .dcsIgnore:
            return processDcs(byte)

        case .sosPmApcString:
            return processSosPmApc(byte)
        }
    }

    // MARK: - Ground 状态

    private func processGround(_ byte: UInt8) -> [VT100Action] {
        switch byte {
        case 0x00...0x17, 0x19, 0x1C...0x1F:
            // C0 控制字符
            return handleControl(byte)

        case 0x1B:
            // ESC
            parserState = .escape
            escapeBuffer = []
            return []

        case 0x7F:
            // DEL - 忽略
            return []

        case 0x80...0x8F, 0x91...0x97, 0x99, 0x9A, 0x9C:
            // C1 控制字符
            return handleControl(byte)

        case 0x98, 0x9E, 0x9F:
            // 忽略
            return []

        default:
            // 可打印字符
            if byte >= 32 && byte < 127 {
                return [.print(Character(UnicodeScalar(Int(byte))!))]
            }
            return []
        }
    }

    private func handleControl(_ byte: UInt8) -> [VT100Action] {
        switch byte {
        case 0x07:  // BEL
            return [.bell]

        case 0x08:  // BS
            return [.backspace]

        case 0x09:  // HT
            return [.tab]

        case 0x0A:  // LF
            return [.lineFeed]

        case 0x0D:  // CR
            return [.carriageReturn]

        case 0x0E:  // SO
            return [.shiftOut]

        case 0x0F:  // SI
            return [.shiftIn]

        case 0x84:  // IND
            return [.lineFeed]

        case 0x85:  // NEL
            return [.carriageReturn, .lineFeed]

        case 0x88:  // HTS
            return []

        case 0x8D:  // RI
            return [.cursorUp(1)]

        default:
            return []
        }
    }

    // MARK: - Escape 状态

    private func processEscape(_ byte: UInt8) -> [VT100Action] {
        escapeBuffer.append(byte)

        switch byte {
        case 0x5B:  // [ - CSI
            parserState = .csiEntry
            paramsBuffer = ""
            return []

        case 0x5D:  // ] - OSC
            parserState = .oscString
            stringBuffer = ""
            return []

        case 0x50:  // P - DCS
            parserState = .dcsEntry
            paramsBuffer = ""
            return []

        case 0x58, 0x5E, 0x5F:  // X, ^, _ - SOS/PM/APC
            parserState = .sosPmApcString
            stringBuffer = ""
            return []

        case 0x37:  // 7 - 保存光标
            parserState = .ground
            return [.saveCursor]

        case 0x38:  // 8 - 恢复光标
            parserState = .ground
            return [.restoreCursor]

        case 0x63:  // c - RIS
            parserState = .ground
            return [.eraseDisplay(.all), .resetGraphics]

        case 0x4D:  // M - 反向索引
            parserState = .ground
            return [.scrollUp(1)]

        case 0x3E:  // > - 应用程序键盘模式
            parserState = .ground
            return []

        case 0x3D:  // = - 应用程序光标键模式
            parserState = .ground
            return []

        case 0x20...0x2F:  // 中间字符
            parserState = .escapeIntermediate
            return []

        case 0x30...0x4F, 0x51...0x57, 0x59, 0x5A, 0x5C, 0x60...0x7E:
            // 完整的 ESC 序列
            parserState = .ground
            return parseEscapeSequence([0x1B] + escapeBuffer)

        default:
            // 超时或无效
            parserState = .ground
            return []
        }
    }

    private func parseEscapeSequence(_ bytes: [UInt8]) -> [VT100Action] {
        guard bytes.count >= 2 else { return [] }

        switch bytes[1] {
        case 0x37:  // DECSC
            return [.saveCursor]

        case 0x38:  // DECRC
            return [.restoreCursor]

        case 0x63:  // RIS
            return [.eraseDisplay(.all), .resetGraphics]

        default:
            return []
        }
    }

    // MARK: - Escape Intermediate

    private func processEscapeIntermediate(_ byte: UInt8) -> [VT100Action] {
        switch byte {
        case 0x20...0x2F:
            // 继续收集
            return []

        case 0x30...0x7E:
            // 终止符
            parserState = .ground
            return []

        default:
            parserState = .ground
            return []
        }
    }

    // MARK: - CSI Entry

    private func processCsiEntry(_ byte: UInt8) -> [VT100Action] {
        switch byte {
        case 0x20...0x2F:
            // 中间字符
            parserState = .csiIntermediate
            return []

        case 0x30...0x39, 0x3B:
            // 参数字符
            paramsBuffer.append(Character(UnicodeScalar(byte)))
            parserState = .csiParam
            return []

        case 0x3C...0x3F:
            // 私有参数
            paramsBuffer.append(Character(UnicodeScalar(byte)))
            parserState = .csiParam
            return []

        default:
            // 直接执行
            paramsBuffer.append(Character(UnicodeScalar(byte)))
            parserState = .ground
            return parseCsiSequence(paramsBuffer)
        }
    }

    // MARK: - CSI Param

    private func processCsiParam(_ byte: UInt8) -> [VT100Action] {
        switch byte {
        case 0x20...0x2F:
            parserState = .csiIntermediate
            return []

        case 0x30...0x3F:
            paramsBuffer.append(Character(UnicodeScalar(byte)))
            return []

        default:
            paramsBuffer.append(Character(UnicodeScalar(byte)))
            parserState = .ground
            return parseCsiSequence(paramsBuffer)
        }
    }

    // MARK: - CSI Intermediate

    private func processCsiIntermediate(_ byte: UInt8) -> [VT100Action] {
        switch byte {
        case 0x20...0x2F:
            paramsBuffer.append(Character(UnicodeScalar(byte)))
            return []

        case 0x40...0x7E:
            paramsBuffer.append(Character(UnicodeScalar(byte)))
            parserState = .ground
            return parseCsiSequence(paramsBuffer)

        default:
            parserState = .csiIgnore
            return []
        }
    }

    // MARK: - CSI Ignore

    private func processCsiIgnore(_ byte: UInt8) -> [VT100Action] {
        switch byte {
        case 0x40...0x7E:
            parserState = .ground
            return []

        default:
            return []
        }
    }

    // MARK: - OSC String

    private func processOscString(_ byte: UInt8) -> [VT100Action] {
        // OSC 以 ST (ESC \) 或 BEL 结束
        if byte == 0x07 || (byte == 0x1B && escapeBuffer.last == Some(0x5C)) {
            parserState = .ground
            escapeBuffer = []
            return parseOscSequence(stringBuffer)
        } else if byte == 0x1B {
            escapeBuffer.append(byte)
        } else {
            stringBuffer.append(Character(UnicodeScalar(byte)))
        }
        return []
    }

    // MARK: - DCS

    private func processDcs(_ byte: UInt8) -> [VT100Action] {
        // DCS 暂时忽略
        if byte == 0x1B {
            escapeBuffer = [byte]
        } else if byte == 0x5C && escapeBuffer.last == Some(0x1B) {
            parserState = .ground
            escapeBuffer = []
        }
        return []
    }

    // MARK: - SOS/PM/APC

    private func processSosPmApc(_ byte: UInt8) -> [VT100Action] {
        // 忽略
        if byte == 0x1B {
            escapeBuffer = [byte]
        } else if byte == 0x5C {
            parserState = .ground
            escapeBuffer = []
        }
        return []
    }

    // MARK: - CSI 序列解析

    private func parseCsiSequence(_ seq: String) -> [VT100Action] {
        guard let last = seq.last else { return [] }

        // 提取参数
        let paramsStr = String(seq.dropLast())
        let params = parseCsiParams(paramsStr)

        switch last {
        case "A":
            // CUU - 光标上移
            return [.cursorUp(params[0])]

        case "B":
            // CUD - 光标下移
            return [.cursorDown(params[0])]

        case "C":
            // CUF - 光标前移
            return [.cursorForward(params[0])]

        case "D":
            // CUB - 光标后退
            return [.cursorBackward(params[0])]

        case "E":
            // CNL - 光标到下一行
            return [.carriageReturn, .cursorDown(params[0])]

        case "F":
            // CPL - 光标到上一行
            return [.carriageReturn, .cursorUp(params[0])]

        case "G":
            // CHA - 光标水平绝对位置
            return [.cursorHorizontalAbsolute(params[0])]

        case "H", "f":
            // CUP/HVP - 光标位置
            let row = params[0]
            let col = params.count > 1 ? params[1] : 1
            return [.cursorPosition(row, col)]

        case "I":
            // CHT - 光标前向制表
            let count = params[0] > 0 ? params[0] : 1
            return [.tab]

        case "J":
            // ED - 擦除显示
            let mode = params[0]
            switch mode {
            case 0: return [.eraseDisplay(.toEnd)]
            case 1: return [.eraseDisplay(.fromStart)]
            case 2: return [.eraseDisplay(.all)]
            case 3: return [.eraseDisplay(.savedLines)]
            default: return []
            }

        case "K":
            // EL - 擦除行
            let mode = params[0]
            switch mode {
            case 0: return [.eraseLine(.toEnd)]
            case 1: return [.eraseLine(.fromStart)]
            case 2: return [.eraseLine(.all)]
            default: return []
            }

        case "L":
            // IL - 插入行
            return [.insertLines(params[0])]

        case "M":
            // DL - 删除行
            return [.deleteLines(params[0])]

        case "P":
            // DCH - 删除字符
            return [.deleteChars(params[0])]

        case "X":
            // ECH - 擦除字符
            return [.eraseChars(params[0])]

        case "Z":
            // CBT - 光标后向制表
            return []

        case "@":
            // ICH - 插入字符
            return [.insertChars(params[0])]

        case "m":
            // SGR - 设置图形模式
            return [.setGraphics(params)]

        case "r":
            // DECSTBM - 设置滚动区域
            let top = params[0] > 0 ? params[0] : 1
            let bottom = params.count > 1 && params[1] > 0 ? params[1] : state.rows
            return [.setScrollRegion(top, bottom)]

        case "c":
            // DA - 设备属性
            return [.deviceAttributes]

        case "n":
            // DSR - 设备状态报告
            if params[0] == 6 {
                return [.queryCursorPosition]
            }
            return []

        case "q":
            // DECSCA - 选择属性变更
            return []

        case "h", "l":
            // DECSET/DECRST - 模式设置
            let isSet = last == "h"
            let isPrivate = paramsStr.hasPrefix("?")
            if isPrivate {
                let privateParams = paramsStr.dropFirst().split(separator: ";").compactMap { Int($0) }
                return [.setMode(isSet, privateParams)]
            }
            return []

        case "s":
            // SCOSC - 保存光标
            return [.saveCursor]

        case "u":
            // SCORC - 恢复光标
            return [.restoreCursor]

        case "t":
            // 窗口操作
            return []

        default:
            return []
        }
    }

    private func parseCsiParams(_ str: String) -> [Int] {
        return str.split(separator: ";").map { part in
            Int(part) ?? (part.isEmpty ? 0 : 1)
        }
    }

    // MARK: - OSC 序列解析

    private func parseOscSequence(_ str: String) -> [VT100Action] {
        guard let first = str.first else { return [] }

        let content = String(str.dropFirst())

        switch String(first) {
        case "0", "2":
            // 设置窗口和图标标题
            return [.setWindowTitle(content)]

        case "1":
            // 设置图标标题
            return [.setIconName(content)]

        case "4":
            // 设置颜色
            return []

        case "10":
            // 设置前景色
            return []

        case "11":
            // 设置背景色
            return []

        default:
            return []
        }
    }

    // MARK: - 应用动作

    private func applyAction(_ action: VT100Action) -> [PTYDirtyRegion]? {
        switch action {
        case .print(let char):
            return writeChar(char)

        case .cursorUp(let n):
            return moveCursor(dx: 0, dy: -n)

        case .cursorDown(let n):
            return moveCursor(dx: 0, dy: n)

        case .cursorForward(let n):
            return moveCursor(dx: n, dy: 0)

        case .cursorBackward(let n):
            return moveCursor(dx: -n, dy: 0)

        case .cursorNextLine(let n):
            state.setCursorX(0)
            return moveCursor(dx: 0, dy: n)

        case .cursorPreviousLine(let n):
            state.setCursorX(0)
            return moveCursor(dx: 0, dy: -n)

        case .cursorHorizontalAbsolute(let n):
            let newX = max(0, min(n - 1, state.cols - 1))
            state.setCursorX(newX)
            return [PTYDirtyRegion(x: newX, y: state.cursor.y, cols: 1, rows: 1)]

        case .cursorPosition(let row, let col):
            let newRow = max(0, min(row - 1, state.rows - 1))
            let newCol = max(0, min(col - 1, state.cols - 1))
            state.setCursor(x: newCol, y: newRow)
            return [PTYDirtyRegion(x: newCol, y: newRow, cols: 1, rows: 1)]

        case .saveCursor:
            savedCursor = SavedCursorState(
                x: state.cursor.x,
                y: state.cursor.y,
                fgColor: currentFGColor,
                bgColor: currentBGColor,
                attributes: currentAttributes
            )
            return nil

        case .restoreCursor:
            state.setCursor(x: savedCursor.x, y: savedCursor.y)
            currentFGColor = savedCursor.fgColor
            currentBGColor = savedCursor.bgColor
            currentAttributes = savedCursor.attributes
            return [PTYDirtyRegion(x: savedCursor.x, y: savedCursor.y, cols: 1, rows: 1)]

        case .eraseDisplay(let mode):
            return eraseDisplay(mode)

        case .eraseLine(let mode):
            return eraseLine(mode)

        case .insertLines(let count):
            return insertLines(count)

        case .deleteLines(let count):
            return deleteLines(count)

        case .deleteChars(let count):
            return deleteChars(count)

        case .eraseChars(let count):
            return eraseChars(count)

        case .insertChars:
            return nil

        case .scrollUp(let count):
            return scrollUp(count)

        case .scrollDown(let count):
            return scrollDown(count)

        case .setScrollRegion:
            return nil

        case .setGraphics(let params):
            return applyGraphics(params)

        case .resetGraphics:
            currentFGColor = .defaultFG
            currentBGColor = .defaultBG
            currentAttributes = []
            return nil

        case .setMode:
            return nil

        case .deviceAttributes, .queryCursorPosition, .setWindowTitle, .setIconName:
            return nil

        case .bell, .backspace, .tab, .lineFeed, .carriageReturn, .shiftOut, .shiftIn:
            return nil

        case .newline:
            return writeChar(Character("\n"))

        case .ignore:
            return nil
        }
    }

    // MARK: - 终端操作

    private func writeChar(_ char: Character) -> [PTYDirtyRegion]? {
        switch char {
        case "\n":
            var newY = state.cursor.y + 1
            if newY >= state.rows {
                scrollUp(1)
                newY = state.rows - 1
            }
            state.setCursorY(newY)
            return [PTYDirtyRegion(x: 0, y: newY, cols: state.cols, rows: 1)]

        case "\r":
            state.setCursorX(0)
            return [PTYDirtyRegion(x: 0, y: state.cursor.y, cols: state.cols, rows: 1)]

        case "\t":
            let tabStop = 8
            let newX = ((state.cursor.x / tabStop) + 1) * tabStop
            let clampedX = min(newX, state.cols - 1)
            state.setCursorX(clampedX)
            return [PTYDirtyRegion(x: clampedX, y: state.cursor.y, cols: 1, rows: 1)]

        case "\u{08}":  // Backspace
            let newX = max(0, state.cursor.x - 1)
            state.setCursorX(newX)
            return [PTYDirtyRegion(x: newX, y: state.cursor.y, cols: 1, rows: 1)]

        default:
            if state.cursor.y < state.rows && state.cursor.x < state.cols {
                let cell = PTYCell(
                    char: char,
                    fgColor: currentFGColor,
                    bgColor: currentBGColor,
                    attrs: currentAttributes
                )
                state.cells[state.cursor.y][state.cursor.x] = cell

                let dirtyX = state.cursor.x
                let dirtyY = state.cursor.y
                var newX = state.cursor.x + 1
                var newY = state.cursor.y

                if newX >= state.cols {
                    newX = 0
                    newY += 1
                    if newY >= state.rows {
                        scrollUp(1)
                        newY = state.rows - 1
                    }
                }

                state.setCursor(x: newX, y: newY)

                return [PTYDirtyRegion(x: dirtyX, y: dirtyY, cols: 1, rows: 1)]
            }
            return nil
        }
    }

    private func moveCursor(dx: Int, dy: Int) -> [PTYDirtyRegion] {
        let newX = max(0, min(state.cursor.x + dx, state.cols - 1))
        let newY = max(0, min(state.cursor.y + dy, state.rows - 1))
        state.setCursor(x: newX, y: newY)
        return [PTYDirtyRegion(x: newX, y: newY, cols: 1, rows: 1)]
    }

    private func eraseDisplay(_ mode: EraseMode) -> [PTYDirtyRegion] {
        switch mode {
        case .toEnd:
            for y in state.cursor.y..<state.rows {
                let startX = (y == state.cursor.y) ? state.cursor.x : 0
                for x in startX..<state.cols {
                    state.cells[y][x] = PTYCell()
                }
            }
            return [PTYDirtyRegion(x: state.cursor.x, y: state.cursor.y,
                                 cols: state.cols - state.cursor.x,
                                 rows: state.rows - state.cursor.y)]

        case .fromStart:
            for y in 0...state.cursor.y {
                let endX = (y == state.cursor.y) ? state.cursor.x + 1 : state.cols
                for x in 0..<endX {
                    state.cells[y][x] = PTYCell()
                }
            }
            return [PTYDirtyRegion(x: 0, y: 0, cols: state.cols, rows: state.cursor.y + 1)]

        case .all:
            for y in 0..<state.rows {
                for x in 0..<state.cols {
                    state.cells[y][x] = PTYCell()
                }
            }
            state.cursor.x = 0
            state.cursor.y = 0
            return [PTYDirtyRegion(x: 0, y: 0, cols: state.cols, rows: state.rows)]

        case .savedLines:
            // 清除滚动缓冲
            state.scrollback = []
            return eraseDisplay(.all)
        }
    }

    private func eraseLine(_ mode: EraseLineMode) -> [PTYDirtyRegion] {
        let y = state.cursor.y

        switch mode {
        case .toEnd:
            for x in state.cursor.x..<state.cols {
                state.cells[y][x] = PTYCell()
            }
            return [PTYDirtyRegion(x: state.cursor.x, y: y,
                                 cols: state.cols - state.cursor.x, rows: 1)]

        case .fromStart:
            for x in 0...state.cursor.x {
                state.cells[y][x] = PTYCell()
            }
            return [PTYDirtyRegion(x: 0, y: y, cols: state.cursor.x + 1, rows: 1)]

        case .all:
            for x in 0..<state.cols {
                state.cells[y][x] = PTYCell()
            }
            return [PTYDirtyRegion(x: 0, y: y, cols: state.cols, rows: 1)]
        }
    }

    private func scrollUp(_ count: Int) -> [PTYDirtyRegion] {
        let count = min(count, state.rows)
        let scrollLines = Array(state.cells[0..<count])
        state.addToScrollback(scrollLines)

        // 移动行
        for y in 0..<(state.rows - count) {
            state.cells[y] = state.cells[y + count]
        }

        // 清空底部行
        for y in (state.rows - count)..<state.rows {
            state.cells[y] = Array(repeating: PTYCell(), count: state.cols)
        }

        return [PTYDirtyRegion(x: 0, y: 0, cols: state.cols, rows: state.rows)]
    }

    private func scrollDown(_ count: Int) -> [PTYDirtyRegion] {
        let count = min(count, state.rows)

        // 移动行
        for y in stride(from: state.rows - 1 - count, through: 0, by: -1) {
            state.cells[y + count] = state.cells[y]
        }

        // 清空顶部行
        for y in 0..<count {
            state.cells[y] = Array(repeating: PTYCell(), count: state.cols)
        }

        return [PTYDirtyRegion(x: 0, y: 0, cols: state.cols, rows: state.rows)]
    }

    private func insertLines(_ count: Int) -> [PTYDirtyRegion] {
        let count = min(count, state.rows - state.cursor.y)
        let startY = state.cursor.y

        // 移动行
        for y in stride(from: state.rows - 1 - count, through: startY, by: -1) {
            state.cells[y + count] = state.cells[y]
        }

        // 清空新行
        for y in startY..<(startY + count) {
            state.cells[y] = Array(repeating: PTYCell(), count: state.cols)
        }

        return [PTYDirtyRegion(x: 0, y: startY, cols: state.cols, rows: count)]
    }

    private func deleteLines(_ count: Int) -> [PTYDirtyRegion] {
        let count = min(count, state.rows - state.cursor.y)
        let startY = state.cursor.y

        // 移动行
        for y in startY..<(state.rows - count) {
            state.cells[y] = state.cells[y + count]
        }

        // 清空底部行
        for y in (state.rows - count)..<state.rows {
            state.cells[y] = Array(repeating: PTYCell(), count: state.cols)
        }

        return [PTYDirtyRegion(x: 0, y: startY, cols: state.cols, rows: state.rows - startY)]
    }

    private func deleteChars(_ count: Int) -> [PTYDirtyRegion] {
        let count = min(count, state.cols - state.cursor.x)
        let row = state.cursor.y
        let startX = state.cursor.x

        // 移动字符
        for x in startX..<(state.cols - count) {
            state.cells[row][x] = state.cells[row][x + count]
        }

        // 清空末尾
        for x in (state.cols - count)..<state.cols {
            state.cells[row][x] = PTYCell()
        }

        return [PTYDirtyRegion(x: startX, y: row, cols: state.cols - startX, rows: 1)]
    }

    private func eraseChars(_ count: Int) -> [PTYDirtyRegion] {
        let count = min(count, state.cols - state.cursor.x)
        let y = state.cursor.y
        let startX = state.cursor.x

        for x in startX..<(startX + count) {
            state.cells[y][x] = PTYCell()
        }

        return [PTYDirtyRegion(x: startX, y: y, cols: count, rows: 1)]
    }

    // MARK: - SGR 处理

    private func applyGraphics(_ params: [Int]) -> [PTYDirtyRegion]? {
        guard !params.isEmpty else {
            // 默认是 0
            currentFGColor = .defaultFG
            currentBGColor = .defaultBG
            currentAttributes = []
            return nil
        }

        var i = 0
        while i < params.count {
            let code = params[i]

            switch code {
            case 0:
                currentFGColor = .defaultFG
                currentBGColor = .defaultBG
                currentAttributes = []

            case 1:
                currentAttributes.insert(.bold)

            case 2:
                currentAttributes.insert(.faint)

            case 3:
                currentAttributes.insert(.italic)

            case 4:
                currentAttributes.insert(.underline)

            case 5, 6:
                currentAttributes.insert(.blink)

            case 7:
                currentAttributes.insert(.reverse)

            case 8:
                currentAttributes.insert(.hidden)

            case 9:
                currentAttributes.insert(.strikethrough)

            case 22:
                currentAttributes.remove(.bold)
                currentAttributes.remove(.faint)

            case 23:
                currentAttributes.remove(.italic)
                currentAttributes.remove(.strikethrough)

            case 24:
                currentAttributes.remove(.underline)

            case 25:
                currentAttributes.remove(.blink)

            case 27:
                currentAttributes.remove(.reverse)

            case 28:
                currentAttributes.remove(.hidden)

            case 30...37:
                currentFGColor = ansiColor(UInt8(code - 30))

            case 38:
                // 真彩色或 256 色
                if i + 2 < params.count {
                    let mode = params[i + 1]
                    if mode == 5 && i + 2 < params.count {
                        // 256 色
                        currentFGColor = indexedColor(UInt8(params[i + 2]))
                        i += 2
                    } else if mode == 2 && i + 4 < params.count {
                        // 真彩色
                        currentFGColor = PTYColorRGB(
                            r: UInt8(params[i + 2]),
                            g: UInt8(params[i + 3]),
                            b: UInt8(params[i + 4])
                        )
                        i += 4
                    }
                }

            case 39:
                currentFGColor = .defaultFG

            case 40...47:
                currentBGColor = ansiColor(UInt8(code - 40))

            case 48:
                // 背景色
                if i + 2 < params.count {
                    let mode = params[i + 1]
                    if mode == 5 && i + 2 < params.count {
                        currentBGColor = indexedColor(UInt8(params[i + 2]))
                        i += 2
                    } else if mode == 2 && i + 4 < params.count {
                        currentBGColor = PTYColorRGB(
                            r: UInt8(params[i + 2]),
                            g: UInt8(params[i + 3]),
                            b: UInt8(params[i + 4])
                        )
                        i += 4
                    }
                }

            case 49:
                currentBGColor = .defaultBG

            case 90...97:
                currentFGColor = ansiColor(UInt8(code - 90 + 8))

            case 100...107:
                currentBGColor = ansiColor(UInt8(code - 100 + 8))

            default:
                break
            }

            i += 1
        }

        return nil
    }

    // MARK: - 颜色辅助

    private func ansiColor(_ index: UInt8) -> PTYColorRGB {
        let colors: [(UInt8, UInt8, UInt8)] = [
            (0x00, 0x00, 0x00),    // 黑
            (0x99, 0x3E, 0x3E),    // 红
            (0x3E, 0x99, 0x3E),    // 绿
            (0x99, 0x99, 0x3E),    // 黄
            (0x3E, 0x3E, 0x99),    // 蓝
            (0x99, 0x3E, 0x99),    // 品红
            (0x3E, 0x99, 0x99),    // 青
            (0x99, 0x99, 0x99),    // 白
            // 高亮
            (0x3E, 0x3E, 0x3E),
            (0xFF, 0x67, 0x67),
            (0x67, 0xFF, 0x67),
            (0xFF, 0xFF, 0x67),
            (0x67, 0x67, 0xFF),
            (0xFF, 0x67, 0xFF),
            (0x67, 0xFF, 0xFF),
            (0xFF, 0xFF, 0xFF),
        ]

        if index < 16 {
            return PTYColorRGB(r: colors[Int(index)].0,
                              g: colors[Int(index)].1,
                              b: colors[Int(index)].2)
        }
        return .defaultFG
    }

    private func indexedColor(_ index: UInt8) -> PTYColorRGB {
        if index < 16 {
            return ansiColor(index)
        } else if index < 232 {
            // 6x6x6 色立方
            let n = index - 16
            let r = (n / 36) % 6
            let g = (n / 6) % 6
            let b = n % 6

            let v: [UInt8] = [0x00, 0x5F, 0x87, 0xAF, 0xD7, 0xFF]
            return PTYColorRGB(r: v[Int(r)], g: v[Int(g)], b: v[Int(b)])
        } else {
            // 灰度
            let n = index - 232
            let v: UInt8 = 8 + n * 10
            return PTYColorRGB(r: v, g: v, b: v)
        }
    }

    // MARK: - 脏区域合并

    private func mergeDirtyRegions(_ regions: [PTYDirtyRegion]) -> [PTYDirtyRegion] {
        var merged: [PTYDirtyRegion] = []

        for region in regions {
            var didMerge = false

            for i in 0..<merged.count {
                if let newRegion = merged[i].merge(region) {
                    merged[i] = newRegion
                    didMerge = true
                    break
                }
            }

            if !didMerge {
                merged.append(region)
            }
        }

        return merged
    }
}

// MARK: - 保存的光标状态

private struct SavedCursorState {
    var x: Int = 0
    var y: Int = 0
    var fgColor: PTYColorRGB = .defaultFG
    var bgColor: PTYColorRGB = .defaultBG
    var attributes: PTYCellAttributes = []
}

// MARK: - 解析器状态

private enum ParserState {
    case ground              // 正常状态
    case escape              // 收到 ESC
    case escapeIntermediate  // ESC 后的中间字符
    case csiEntry            // CSI 入口 (ESC[)
    case csiParam            // CSI 参数
    case csiIntermediate     // CSI 中间字符
    case csiIgnore           // CSI 忽略
    case dcsEntry            // DCS 入口
    case dcsParam            // DCS 参数
    case dcsPassthrough      // DCS 透传
    case dcsIgnore           // DCS 忽略
    case oscString           // OSC 字符串
    case sosPmApcString      // SOS/PM/APC 字符串
}

// MARK: - 辅助扩展

private func Some<T>(_ value: T) -> T? {
    return value
}
