//
//  TerminalState.swift
//  VibeTerminal
//
//  终端屏幕状态管理
//

import Foundation
import Metal

// MARK: - 终端单元格
struct TerminalCell {
    var char: Character = " "
    var fgColor: SIMD4<UInt8> = SIMD4(212, 212, 212, 255)  // 默认前景色
    var bgColor: SIMD4<UInt8> = SIMD4(28, 28, 28, 255)     // 默认背景色
    var attrs: UInt16 = 0                                   // 样式标志

    // 样式标志位
    struct Attrs {
        static let bold: UInt16 = 1 << 0
        static let dim: UInt16 = 1 << 1
        static let italic: UInt16 = 1 << 2
        static let underline: UInt16 = 1 << 3
        static let blink: UInt16 = 1 << 4
        static let reverse: UInt16 = 1 << 5
        static let hidden: UInt16 = 1 << 6
        static let strikethrough: UInt16 = 1 << 7
    }

    var isBold: Bool { (attrs & Attrs.bold) != 0 }
    var isDim: Bool { (attrs & Attrs.dim) != 0 }
    var isItalic: Bool { (attrs & Attrs.italic) != 0 }
    var isUnderline: Bool { (attrs & Attrs.underline) != 0 }
    var isBlink: Bool { (attrs & Attrs.blink) != 0 }
    var isReverse: Bool { (attrs & Attrs.reverse) != 0 }
    var isHidden: Bool { (attrs & Attrs.hidden) != 0 }
    var isStrikethrough: Bool { (attrs & Attrs.strikethrough) != 0 }
}

// MARK: - 脏区域
struct DirtyRegion {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    func intersects(_ other: DirtyRegion) -> Bool {
        return x < other.x + other.width &&
               x + width > other.x &&
               y < other.y + other.height &&
               y + height > other.y
    }

    func merged(_ other: DirtyRegion) -> DirtyRegion {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        let maxX = max(x + width, other.x + other.width)
        let maxY = max(y + height, other.y + other.height)
        return DirtyRegion(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - 光标信息
struct CursorInfo {
    var x: Int
    var y: Int
    var visible: Bool = true
    var style: CursorStyle = .block

    enum CursorStyle {
        case block
        case underline
        case bar
    }
}

// MARK: - 终端屏幕
class TerminalState {
    private(set) var cols: Int
    private(set) var rows: Int
    private(set) var cells: [[TerminalCell]]

    // 光标状态
    private(set) var cursorX: Int = 0
    private(set) var cursorY: Int = 0
    private(set) var cursorVisible: Bool = true
    private(set) var cursorStyle: CursorInfo.CursorStyle = .block

    // 滚动区域
    var scrollTop: Int = 0
    var scrollBottom: Int = 0

    // 脏区域追踪
    private var dirtyRegions: [DirtyRegion] = []

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.cells = Array(repeating: Array(repeating: TerminalCell(), count: cols), count: rows)
        self.scrollBottom = rows - 1
    }

    // MARK: - 尺寸调整
    func resize(cols: Int, rows: Int) {
        var newCells = Array(repeating: Array(repeating: TerminalCell(), count: cols), count: rows)

        let copyRows = min(self.rows, rows)
        let copyCols = min(self.cols, cols)

        for y in 0..<copyRows {
            for x in 0..<copyCols {
                newCells[y][x] = cells[y][x]
            }
        }

        self.cells = newCells
        self.cols = cols
        self.rows = rows
        self.scrollBottom = rows - 1

        // 确保光标在范围内
        cursorX = min(cursorX, cols - 1)
        cursorY = min(cursorY, rows - 1)

        // 标记整个屏幕为脏区域
        markDirty(DirtyRegion(x: 0, y: 0, width: cols, height: rows))
    }

    // MARK: - 脏区域管理
    func markDirty(_ region: DirtyRegion) {
        // 与现有脏区域合并
        var merged = false
        for i in 0..<dirtyRegions.count {
            if dirtyRegions[i].intersects(region) {
                dirtyRegions[i] = dirtyRegions[i].merged(region)
                merged = true
                break
            }
        }
        if !merged {
            dirtyRegions.append(region)
        }
    }

    func markDirty(x: Int, y: Int, width: Int = 1, height: Int = 1) {
        markDirty(DirtyRegion(x: x, y: y, width: width, height: height))
    }

    func getAndClearDirtyRegions() -> [CGRect] {
        let regions = dirtyRegions.map { region -> CGRect in
            let cellWidth: CGFloat = 1.0 / CGFloat(cols)
            let cellHeight: CGFloat = 1.0 / CGFloat(rows)
            return CGRect(
                x: CGFloat(region.x) * cellWidth,
                y: CGFloat(region.y) * cellHeight,
                width: CGFloat(region.width) * cellWidth,
                height: CGFloat(region.height) * cellHeight
            )
        }
        dirtyRegions.removeAll()
        return regions
    }

    /// 获取原始的脏区域（单元格坐标系），用于优化渲染
    func getAndClearDirtyCellRegions() -> [DirtyRegion] {
        let regions = dirtyRegions
        dirtyRegions.removeAll()
        return regions
    }

    // MARK: - 内容操作
    func clearScreen() {
        for y in 0..<rows {
            for x in 0..<cols {
                cells[y][x] = TerminalCell()
            }
        }
        markDirty(DirtyRegion(x: 0, y: 0, width: cols, height: rows))
    }

    func clearLine(y: Int) {
        guard y < rows else { return }
        for x in 0..<cols {
            cells[y][x] = TerminalCell()
        }
        markDirty(x: 0, y: y, width: cols, height: 1)
    }

    func write(char: Character, atX x: Int, y: Int) {
        guard y < rows, x < cols else { return }
        cells[y][x].char = char
        markDirty(x: x, y: y)
    }

    func setCell(_ cell: TerminalCell, atX x: Int, y: Int) {
        guard y < rows, x < cols else { return }
        cells[y][x] = cell
        markDirty(x: x, y: y)
    }

    func getCell(x: Int, y: Int) -> TerminalCell? {
        guard y < rows, x < cols else { return nil }
        return cells[y][x]
    }

    // MARK: - 光标操作
    func setCursor(x: Int, y: Int) {
        let oldX = cursorX
        let oldY = cursorY

        cursorX = max(0, min(x, cols - 1))
        cursorY = max(0, min(y, rows - 1))

        // 标记新旧光标位置为脏区域
        markDirty(x: oldX, y: oldY)
        markDirty(x: cursorX, y: cursorY)
    }

    func setCursorVisible(_ visible: Bool) {
        cursorVisible = visible
        markDirty(x: cursorX, y: cursorY)
    }

    func setCursorStyle(_ style: CursorInfo.CursorStyle) {
        cursorStyle = style
        markDirty(x: cursorX, y: cursorY)
    }

    func getCursorInfo() -> CursorInfo {
        return CursorInfo(x: cursorX, y: cursorY, visible: cursorVisible, style: cursorStyle)
    }

    // MARK: - 滚动操作
    func scrollUp(amount: Int = 1) {
        let scrollHeight = scrollBottom - scrollTop + 1
        guard amount > 0 && amount < scrollHeight else { return }

        // 向上移动行
        for y in scrollTop..<(scrollBottom - amount + 1) {
            cells[y] = cells[y + amount]
        }

        // 清空底部的行
        for y in (scrollBottom - amount + 1)...scrollBottom {
            cells[y] = Array(repeating: TerminalCell(), count: cols)
        }

        markDirty(x: 0, y: scrollTop, width: cols, height: scrollHeight)
    }

    func scrollDown(amount: Int = 1) {
        let scrollHeight = scrollBottom - scrollTop + 1
        guard amount > 0 && amount < scrollHeight else { return }

        // 向下移动行
        for y in stride(from: scrollBottom, through: scrollTop + amount, by: -1) {
            cells[y] = cells[y - amount]
        }

        // 清空顶部的行
        for y in scrollTop..<(scrollTop + amount) {
            cells[y] = Array(repeating: TerminalCell(), count: cols)
        }

        markDirty(x: 0, y: scrollTop, width: cols, height: scrollHeight)
    }

    // MARK: - 批量更新
    func updateRegion(cells: [[TerminalCell]], x: Int, y: Int) {
        let height = cells.count
        let width = cells.first?.count ?? 0

        for dy in 0..<height {
            let targetY = y + dy
            guard targetY < rows else { continue }

            for dx in 0..<width {
                let targetX = x + dx
                guard targetX < cols else { continue }

                self.cells[targetY][targetX] = cells[dy][dx]
            }
        }

        markDirty(x: x, y: y, width: width, height: height)
    }

    // MARK: - 完整状态导出（用于初始同步）
    func exportAllCells() -> [[TerminalCell]] {
        return cells.map { $0.map { $0 } }
    }

    func importAllCells(_ importedCells: [[TerminalCell]], cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.cells = importedCells.map { row in
            Array(row.prefix(cols))
        }

        // 填充不足的行
        while cells.count < rows {
            cells.append(Array(repeating: TerminalCell(), count: cols))
        }

        // 标记全部为脏区域
        markDirty(DirtyRegion(x: 0, y: 0, width: cols, height: rows))
    }
}

// MARK: - SIMD4 扩展，用于颜色访问
extension SIMD4 where Scalar == UInt8 {
    var r: Scalar { self[0] }
    var g: Scalar { self[1] }
    var b: Scalar { self[2] }
    var a: Scalar { self[3] }
}
