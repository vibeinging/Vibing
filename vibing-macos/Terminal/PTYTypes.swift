//
//  PTYTypes.swift
//  VibeTerminal
//
//  PTY 终端相关类型定义
//

import Foundation

// MARK: - 终端单元格

/// PTY 终端单元格
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

// MARK: - 光标状态

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

// MARK: - 终端状态

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

// MARK: - 脏区域

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
