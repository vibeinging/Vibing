//
//  TerminalProtocol.swift
//  VibeTerminal
//
//  终端协议定义 - 与 vibe-terminal-server (Rust) 对应
//
//  协议格式：
//  - [1字节] 帧类型标记
//  - [4字节] 数据长度 (小端序)
//  - [N字节] 数据内容 (JSON 序列化，与服务器 bincode 兼容)
//

import Foundation

// MARK: - 协议错误

enum ProtocolError: Error, LocalizedError {
    case invalidFormat(String)
    case incompleteData
    case serializationError(String)
    case unknownFrameType(UInt8)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg):
            return "Invalid format: \(msg)"
        case .incompleteData:
            return "Incomplete data"
        case .serializationError(let msg):
            return "Serialization error: \(msg)"
        case .unknownFrameType(let t):
            return "Unknown frame type: \(t)"
        }
    }
}

// MARK: - 帧类型标记 (对应服务器 protocol.rs)

enum FrameTypeMarker: UInt8 {
    // 客户端 -> 服务器
    case input = 0x01
    case subscribe = 0x02
    case createSession = 0x03
    case resizeSession = 0x04
    case closeSession = 0x05

    // 服务器 -> 客户端
    case sessionOutput = 0x10
    case cursorUpdate = 0x11
    case modeUpdate = 0x12
    case sessionCreated = 0x13
    case sessionClosed = 0x14
    case error = 0x15

    // 心跳
    case ping = 0x20
    case pong = 0x21
}

// MARK: - 协议帧

enum Frame {
    // ========== 客户端 -> 服务器 ==========

    /// 用户输入数据
    case input(sessionId: String, data: Data)

    /// 订阅指定会话的输出
    case subscribe([String])

    /// 创建新会话请求
    case createSession(CreateSessionRequest)

    /// 调整会话终端大小
    case resizeSession(sessionId: String, cols: UInt16, rows: UInt16)

    /// 关闭会话
    case closeSession(sessionId: String)

    // ========== 服务器 -> 客户端 ==========

    /// 会话输出数据（增量屏幕更新）
    case sessionOutput(sessionId: String, frame: ScreenFrame)

    /// 光标状态更新
    case cursorUpdate(CursorFrame)

    /// 模式状态更新
    case modeUpdate(ModeFrame)

    /// 会话创建成功通知
    case sessionCreated(String)

    /// 会话关闭通知
    case sessionClosed(String)

    /// 错误消息
    case error(String)

    // ========== 心跳 ==========

    case ping
    case pong
}

// MARK: - 创建会话请求

struct CreateSessionRequest: Codable {
    /// 要执行的命令
    let command: String

    /// 命令参数
    let args: [String]

    /// 工作目录
    let cwd: String?

    /// 环境变量 (使用字典结构以便于 Codable)
    let env: [String: String]?

    /// 创建一个 Shell 会话请求
    static func shell() -> CreateSessionRequest {
        CreateSessionRequest(
            command: "sh",
            args: ["-l"],
            cwd: nil,
            env: nil
        )
    }

    /// 创建指定命令的会话请求
    static func command(_ command: String, args: [String] = []) -> CreateSessionRequest {
        CreateSessionRequest(
            command: command,
            args: args,
            cwd: nil,
            env: nil
        )
    }

    /// 设置工作目录
    func withCwd(_ cwd: String) -> CreateSessionRequest {
        CreateSessionRequest(
            command: self.command,
            args: self.args,
            cwd: cwd,
            env: self.env
        )
    }

    /// 设置环境变量
    func withEnv(_ env: [String: String]) -> CreateSessionRequest {
        CreateSessionRequest(
            command: self.command,
            args: self.args,
            cwd: self.cwd,
            env: env
        )
    }
}

// MARK: - 屏幕帧

struct ScreenFrame: Codable {
    /// 序列号，用于同步
    let seq: UInt64

    /// 终端列数
    let cols: UInt16

    /// 终端行数
    let rows: UInt16

    /// 脏区域列表（只包含变化的部分）
    let dirtyRegions: [ProtocolDirtyRegion]

    /// 创建一个空的屏幕帧
    static func empty(seq: UInt64, cols: UInt16, rows: UInt16) -> ScreenFrame {
        ScreenFrame(
            seq: seq,
            cols: cols,
            rows: rows,
            dirtyRegions: []
        )
    }

    /// 创建一个全屏刷新帧
    static func full(seq: UInt64, cols: UInt16, rows: UInt16, cells: [ProtocolCellData]) -> ScreenFrame {
        ScreenFrame(
            seq: seq,
            cols: cols,
            rows: rows,
            dirtyRegions: [
                ProtocolDirtyRegion(
                    x: 0,
                    y: 0,
                    width: cols,
                    height: rows,
                    cells: cells
                )
            ]
        )
    }

    /// CodingKeys 用于处理蛇形命名
    enum CodingKeys: String, CodingKey {
        case seq
        case cols
        case rows
        case dirtyRegions = "dirty_regions"
    }
}

// MARK: - 脏区域

// 使用不同的名称避免与 TerminalMetalView 中的 DirtyRegion 冲突
struct ProtocolDirtyRegion: Codable {
    /// 区域起始 X 坐标（列）
    let x: UInt16

    /// 区域起始 Y 坐标（行）
    let y: UInt16

    /// 区域宽度（列数）
    let width: UInt16

    /// 区域高度（行数）
    let height: UInt16

    /// 区域内所有单元格的数据（按行优先顺序）
    let cells: [ProtocolCellData]

    /// 创建一个空区域
    static func empty(x: UInt16, y: UInt16, width: UInt16, height: UInt16) -> ProtocolDirtyRegion {
        ProtocolDirtyRegion(
            x: x,
            y: y,
            width: width,
            height: height,
            cells: []
        )
    }

    /// 获取区域的结束列（不包含）
    var endX: UInt16 {
        x + width
    }

    /// 获取区域的结束行（不包含）
    var endY: UInt16 {
        y + height
    }

    /// 检查区域是否为空
    var isEmpty: Bool {
        width == 0 || height == 0 || cells.isEmpty
    }
}

// MARK: - 单元格数据

typealias ProtocolCellData = CellData

struct CellData: Codable {
    /// 字符内容（使用 String 以支持 Unicode 和组合字符）
    let char: String

    /// 前景色
    let fgColor: ProtocolColor

    /// 背景色
    let bgColor: ProtocolColor

    /// 单元格属性
    let attrs: CellAttrs

    /// 创建一个空白单元格（使用默认样式）
    static func blank() -> CellData {
        CellData(
            char: " ",
            fgColor: .default,
            bgColor: .default,
            attrs: .empty
        )
    }

    /// 创建一个带有指定字符的单元格
    static func new(_ char: String) -> CellData {
        CellData(
            char: char,
            fgColor: .default,
            bgColor: .default,
            attrs: .empty
        )
    }

    /// 获取前景色 RGBA
    var fgRGBA: SIMD4<UInt8> {
        fgColor.toRGBA()
    }

    /// 获取背景色 RGBA
    var bgRGBA: SIMD4<UInt8> {
        bgColor.toRGBA()
    }

    /// CodingKeys 用于处理蛇形命名
    enum CodingKeys: String, CodingKey {
        case char
        case fgColor = "fg_color"
        case bgColor = "bg_color"
        case attrs
    }
}

// MARK: - 颜色

typealias ProtocolColor = Color

enum Color: Codable {
    /// 默认颜色（由终端主题决定）
    case `default`

    /// 16 色索引色（0-15：标准色 + 高亮色）
    case indexed(UInt8)

    /// 256 色索引色（16-231：6x6x6 色立方，232-255：灰度）
    case palette(UInt8)

    /// RGB 真彩色
    case rgb(r: UInt8, g: UInt8, b: UInt8)

    // 标准 16 色
    static let black = Color.indexed(0)
    static let red = Color.indexed(1)
    static let green = Color.indexed(2)
    static let yellow = Color.indexed(3)
    static let blue = Color.indexed(4)
    static let magenta = Color.indexed(5)
    static let cyan = Color.indexed(6)
    static let white = Color.indexed(7)

    // 高亮色
    static let brightBlack = Color.indexed(8)
    static let brightRed = Color.indexed(9)
    static let brightGreen = Color.indexed(10)
    static let brightYellow = Color.indexed(11)
    static let brightBlue = Color.indexed(12)
    static let brightMagenta = Color.indexed(13)
    static let brightCyan = Color.indexed(14)
    static let brightWhite = Color.indexed(15)

    /// 从 RGB 值创建颜色
    static func rgb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Color {
        .rgb(r: r, g: g, b: b)
    }

    /// 从 8 位调色板索引创建颜色
    static func from8bit(_ index: UInt8) -> Color {
        if index < 16 {
            return .indexed(index)
        } else {
            return .palette(index)
        }
    }

    /// 转换为 (r, g, b) 元组
    func toRGB() -> (UInt8, UInt8, UInt8) {
        switch self {
        case .default:
            return (229, 229, 229)

        case .indexed(let idx):
            let colors: [(UInt8, UInt8, UInt8)] = [
                // Normal colors
                (0x00, 0x00, 0x00), // 0: Black
                (0x99, 0x3E, 0x3E), // 1: Red
                (0x3E, 0x99, 0x3E), // 2: Green
                (0x99, 0x99, 0x3E), // 3: Brown/Yellow
                (0x3E, 0x3E, 0x99), // 4: Blue
                (0x99, 0x3E, 0x99), // 5: Magenta
                (0x3E, 0x99, 0x99), // 6: Cyan
                (0x99, 0x99, 0x99), // 7: White
                // Intense colors
                (0x3E, 0x3E, 0x3E), // 8: Bright Black (Gray)
                (0xFF, 0x67, 0x67), // 9: Bright Red
                (0x67, 0xFF, 0x67), // 10: Bright Green
                (0xFF, 0xFF, 0x67), // 11: Bright Yellow
                (0x67, 0x67, 0xFF), // 12: Bright Blue
                (0xFF, 0x67, 0xFF), // 13: Bright Magenta
                (0x67, 0xFF, 0xFF), // 14: Bright Cyan
                (0xFF, 0xFF, 0xFF), // 15: Bright White
            ]
            if Int(idx) < colors.count {
                return colors[Int(idx)]
            }
            return (0x99, 0x99, 0x99)

        case .palette(let idx):
            if idx < 232 {
                // 6x6x6 色立方
                let v: [UInt8] = [0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff]
                let offset = Int(idx) - 16
                let cubeSize = 6
                let r = v[(offset / (cubeSize * cubeSize)) % cubeSize]
                let g = v[(offset / cubeSize) % cubeSize]
                let b = v[offset % cubeSize]
                return (r, g, b)
            } else {
                // 灰度：232-255
                let offset = idx - 232
                let value = 8 + offset * 10
                return (value, value, value)
            }

        case .rgb(let r, let g, let b):
            return (r, g, b)
        }
    }

    /// 转换为 SIMD4<UInt8> RGBA
    func toRGBA() -> SIMD4<UInt8> {
        let (r, g, b) = toRGB()
        return SIMD4(r, g, b, 255)
    }

    // Codable 实现
    enum CodingKeys: String, CodingKey {
        case type, value, r, g, b
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .default:
            try container.encode(0 as UInt8, forKey: .type)
        case .indexed(let v):
            try container.encode(1 as UInt8, forKey: .type)
            try container.encode(v, forKey: .value)
        case .palette(let v):
            try container.encode(2 as UInt8, forKey: .type)
            try container.encode(v, forKey: .value)
        case .rgb(let r, let g, let b):
            try container.encode(3 as UInt8, forKey: .type)
            try container.encode(r, forKey: .r)
            try container.encode(g, forKey: .g)
            try container.encode(b, forKey: .b)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(UInt8.self, forKey: .type)
        switch type {
        case 0:
            self = .default
        case 1:
            let v = try container.decode(UInt8.self, forKey: .value)
            self = .indexed(v)
        case 2:
            let v = try container.decode(UInt8.self, forKey: .value)
            self = .palette(v)
        case 3:
            let r = try container.decode(UInt8.self, forKey: .r)
            let g = try container.decode(UInt8.self, forKey: .g)
            let b = try container.decode(UInt8.self, forKey: .b)
            self = .rgb(r: r, g: g, b: b)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Invalid color type"
            )
        }
    }
}

// MARK: - 单元格属性

struct CellAttrs: Codable, OptionSet {
    let rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// 加粗 (ANSI 1)
    static let bold = CellAttrs(rawValue: 0x0001)

    /// 暗淡 (ANSI 2)
    static let dim = CellAttrs(rawValue: 0x0002)

    /// 斜体 (ANSI 3)
    static let italic = CellAttrs(rawValue: 0x0004)

    /// 下划线 (ANSI 4)
    static let underline = CellAttrs(rawValue: 0x0008)

    /// 双下划线 (ANSI 21)
    static let doubleUnderline = CellAttrs(rawValue: 0x0010)

    /// 眨眼 (ANSI 5)
    static let blink = CellAttrs(rawValue: 0x0020)

    /// 快速眨眼 (ANSI 6)
    static let rapidBlink = CellAttrs(rawValue: 0x0040)

    /// 反色 (ANSI 7)
    static let reverse = CellAttrs(rawValue: 0x0080)

    /// 隐藏 (ANSI 8)
    static let hidden = CellAttrs(rawValue: 0x0100)

    /// 删除线 (ANSI 9)
    static let strikethrough = CellAttrs(rawValue: 0x0200)

    /// 创建空的属性集
    static let empty = CellAttrs(rawValue: 0)

    /// 是否为空
    var isEmpty: Bool {
        rawValue == 0
    }

    /// 是否包含加粗
    var isBold: Bool {
        contains(.bold)
    }

    /// 是否包含下划线
    var isUnderline: Bool {
        contains(.underline) || contains(.doubleUnderline)
    }

    /// 是否包含反色
    var isReverse: Bool {
        contains(.reverse)
    }

    // Codable 自定义实现
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(UInt16.self)
        self.init(rawValue: rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - 光标帧

struct CursorFrame: Codable {
    /// 光标列位置（0-based）
    let x: UInt16

    /// 光标行位置（0-based）
    let y: UInt16

    /// 光标是否可见
    let visible: Bool

    /// 光标样式
    let style: CursorStyle

    /// 创建一个新的光标帧
    static func new(x: UInt16, y: UInt16) -> CursorFrame {
        CursorFrame(
            x: x,
            y: y,
            visible: true,
            style: .block
        )
    }

    /// 设置可见性
    func withVisible(_ visible: Bool) -> CursorFrame {
        CursorFrame(x: x, y: y, visible: visible, style: style)
    }

    /// 设置样式
    func withStyle(_ style: CursorStyle) -> CursorFrame {
        CursorFrame(x: x, y: y, visible: visible, style: style)
    }

    /// 隐藏光标
    static func hide() -> CursorFrame {
        CursorFrame(
            x: 0,
            y: 0,
            visible: false,
            style: .block
        )
    }
}

// MARK: - 光标样式

enum CursorStyle: UInt8, Codable {
    /// 块状光标
    case block = 0

    /// 下划线光标
    case underline = 1

    /// 竖条光标
    case bar = 2
}

// MARK: - 模式帧

struct ModeFrame: Codable {
    /// 当前模式
    let mode: Mode

    /// 模式是否激活
    let active: Bool

    /// 创建一个新的模式帧
    static func new(_ mode: Mode) -> ModeFrame {
        ModeFrame(mode: mode, active: true)
    }

    /// 设置激活状态
    func withActive(_ active: Bool) -> ModeFrame {
        ModeFrame(mode: mode, active: active)
    }
}

// MARK: - 编辑模式

enum Mode: UInt8, Codable {
    /// 普通模式
    case normal = 0

    /// Plan 模式
    case plan = 1

    /// Agent 模式
    case agent = 2

    /// 编辑模式
    case edit = 3
}

// MARK: - 完整状态帧

struct FullStateFrame {
    /// 序列号
    let seq: UInt64

    /// 终端列数
    let cols: UInt16

    /// 终端行数
    let rows: UInt16

    /// 所有单元格数据（扁平化数组）
    let cells: [CellData]

    /// 光标信息
    let cursor: CursorFrame
}
