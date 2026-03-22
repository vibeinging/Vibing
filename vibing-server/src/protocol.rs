//
//  protocol.rs
//  Vibe Terminal Server
//
//  同步协议定义 - 帧编码解码
//

use serde::{Deserialize, Serialize};
use std::fmt;

/// 会话 ID 类型
pub type SessionId = String;

/// 协议帧类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Frame {
    // ========== 客户端 -> 服务器 ==========
    /// 用户输入数据
    Input(SessionId, Vec<u8>),

    /// 订阅指定会话的输出
    Subscribe(Vec<SessionId>),

    /// 创建新会话请求
    CreateSession(CreateSessionRequest),

    /// 调整会话终端大小
    ResizeSession(SessionId, u16, u16),

    /// 关闭会话
    CloseSession(SessionId),

    // ========== 服务器 -> 客户端 ==========
    /// 会话输出数据（增量屏幕更新）
    SessionOutput(SessionId, ScreenFrame),

    /// 光标状态更新
    CursorUpdate(CursorFrame),

    /// 模式状态更新
    ModeUpdate(ModeFrame),

    /// 会话创建成功通知
    SessionCreated(SessionId),

    /// 会话关闭通知
    SessionClosed(SessionId),

    /// 错误消息
    Error(String),

    // ========== 心跳 ==========
    Ping,
    Pong,
}

impl fmt::Display for Frame {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Frame::Input(sid, _) => write!(f, "Input({})", sid),
            Frame::Subscribe(sids) => write!(f, "Subscribe({} sessions)", sids.len()),
            Frame::CreateSession(req) => write!(f, "CreateSession({})", req.command),
            Frame::ResizeSession(sid, w, h) => write!(f, "ResizeSession({}, {}x{})", sid, w, h),
            Frame::CloseSession(sid) => write!(f, "CloseSession({})", sid),
            Frame::SessionOutput(sid, frame) => {
                write!(f, "SessionOutput({}, seq={}, {} regions)", sid, frame.seq, frame.dirty_regions.len())
            }
            Frame::CursorUpdate(cursor) => write!(f, "CursorUpdate({}, {})", cursor.x, cursor.y),
            Frame::ModeUpdate(mode) => write!(f, "ModeUpdate(mode={}, active={})", mode.mode, mode.active),
            Frame::SessionCreated(sid) => write!(f, "SessionCreated({})", sid),
            Frame::SessionClosed(sid) => write!(f, "SessionClosed({})", sid),
            Frame::Error(msg) => write!(f, "Error({})", msg),
            Frame::Ping => write!(f, "Ping"),
            Frame::Pong => write!(f, "Pong"),
        }
    }
}

/// 创建会话请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateSessionRequest {
    /// 要执行的命令
    pub command: String,

    /// 命令参数
    pub args: Vec<String>,

    /// 工作目录
    pub cwd: Option<String>,

    /// 环境变量
    pub env: Option<Vec<(String, String)>>,
}

impl CreateSessionRequest {
    /// 创建一个新的 Shell 会话请求
    pub fn shell() -> Self {
        Self {
            command: "sh".to_string(),
            args: vec!["-l".to_string()],
            cwd: None,
            env: None,
        }
    }

    /// 创建指定命令的会话请求
    pub fn command(command: &str, args: Vec<String>) -> Self {
        Self {
            command: command.to_string(),
            args,
            cwd: None,
            env: None,
        }
    }

    /// 设置工作目录
    pub fn with_cwd(mut self, cwd: String) -> Self {
        self.cwd = Some(cwd);
        self
    }

    /// 设置环境变量
    pub fn with_env(mut self, env: Vec<(String, String)>) -> Self {
        self.env = Some(env);
        self
    }
}

/// 屏幕帧 - 增量更新
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScreenFrame {
    /// 序列号，用于同步
    pub seq: u64,

    /// 终端列数
    pub cols: u16,

    /// 终端行数
    pub rows: u16,

    /// 脏区域列表（只包含变化的部分）
    pub dirty_regions: Vec<DirtyRegion>,
}

impl ScreenFrame {
    /// 创建一个空的屏幕帧
    pub fn empty(seq: u64, cols: u16, rows: u16) -> Self {
        Self {
            seq,
            cols,
            rows,
            dirty_regions: Vec::new(),
        }
    }

    /// 创建一个全屏刷新帧
    pub fn full(seq: u64, cols: u16, rows: u16, cells: Vec<CellData>) -> Self {
        Self {
            seq,
            cols,
            rows,
            dirty_regions: vec![DirtyRegion {
                x: 0,
                y: 0,
                width: cols,
                height: rows,
                cells,
            }],
        }
    }
}

/// 脏区域 - 屏幕上的一个变化矩形区域
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirtyRegion {
    /// 区域起始 X 坐标（列）
    pub x: u16,

    /// 区域起始 Y 坐标（行）
    pub y: u16,

    /// 区域宽度（列数）
    pub width: u16,

    /// 区域高度（行数）
    pub height: u16,

    /// 区域内所有单元格的数据（按行优先顺序）
    pub cells: Vec<CellData>,
}

impl DirtyRegion {
    /// 创建一个空区域
    pub fn empty(x: u16, y: u16, width: u16, height: u16) -> Self {
        Self {
            x,
            y,
            width,
            height,
            cells: Vec::new(),
        }
    }

    /// 获取区域的结束列（不包含）
    #[inline]
    pub fn end_x(&self) -> u16 {
        self.x.saturating_add(self.width)
    }

    /// 获取区域的结束行（不包含）
    #[inline]
    pub fn end_y(&self) -> u16 {
        self.y.saturating_add(self.height)
    }

    /// 检查区域是否为空
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.width == 0 || self.height == 0 || self.cells.is_empty()
    }
}

/// 单元格数据 - 表示屏幕上的一个字符及其样式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CellData {
    /// 字符内容（使用 String 以支持 Unicode 和组合字符）
    pub char: String,

    /// 前景色
    #[serde(default)]
    pub fg_color: Color,

    /// 背景色
    #[serde(default)]
    pub bg_color: Color,

    /// 单元格属性
    #[serde(default)]
    pub attrs: CellAttrs,
}

impl CellData {
    /// 创建一个空白单元格（使用默认样式）
    pub fn blank() -> Self {
        Self {
            char: " ".to_string(),
            fg_color: Color::Default,
            bg_color: Color::Default,
            attrs: CellAttrs::empty(),
        }
    }

    /// 创建一个带有指定字符的单元格
    pub fn new(char: impl Into<String>) -> Self {
        Self {
            char: char.into(),
            fg_color: Color::Default,
            bg_color: Color::Default,
            attrs: CellAttrs::empty(),
        }
    }

    /// 设置前景色
    pub fn with_fg(mut self, color: Color) -> Self {
        self.fg_color = color;
        self
    }

    /// 设置背景色
    pub fn with_bg(mut self, color: Color) -> Self {
        self.bg_color = color;
        self
    }

    /// 设置属性
    pub fn with_attrs(mut self, attrs: CellAttrs) -> Self {
        self.attrs = attrs;
        self
    }

    /// 设置加粗
    pub fn bold(mut self) -> Self {
        self.attrs.insert(CellAttrs::BOLD);
        self
    }

    /// 设置下划线
    pub fn underline(mut self) -> Self {
        self.attrs.insert(CellAttrs::UNDERLINE);
        self
    }

    /// 设置反色
    pub fn reverse(mut self) -> Self {
        self.attrs.insert(CellAttrs::REVERSE);
        self
    }
}

impl Default for CellData {
    fn default() -> Self {
        Self::blank()
    }
}

/// 颜色表示
///
/// 参考 OpenTerm 的 ANSITextState.swift 实现
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Color {
    /// 默认颜色（由终端主题决定）
    Default,

    /// 16 色索引色（0-15：标准色 + 高亮色）
    Indexed(u8),

    /// 256 色索引色（16-231：6x6x6 色立方，232-255：灰度）
    Palette(u8),

    /// RGB 真彩色
    Rgb { r: u8, g: u8, b: u8 },
}

impl Color {
    /// 标准 16 色（参考 OpenTerm 的颜色表）
    pub const BLACK: Color = Color::Indexed(0);
    pub const RED: Color = Color::Indexed(1);
    pub const GREEN: Color = Color::Indexed(2);
    pub const YELLOW: Color = Color::Indexed(3);
    pub const BLUE: Color = Color::Indexed(4);
    pub const MAGENTA: Color = Color::Indexed(5);
    pub const CYAN: Color = Color::Indexed(6);
    pub const WHITE: Color = Color::Indexed(7);

    /// 高亮色
    pub const BRIGHT_BLACK: Color = Color::Indexed(8);
    pub const BRIGHT_RED: Color = Color::Indexed(9);
    pub const BRIGHT_GREEN: Color = Color::Indexed(10);
    pub const BRIGHT_YELLOW: Color = Color::Indexed(11);
    pub const BRIGHT_BLUE: Color = Color::Indexed(12);
    pub const BRIGHT_MAGENTA: Color = Color::Indexed(13);
    pub const BRIGHT_CYAN: Color = Color::Indexed(14);
    pub const BRIGHT_WHITE: Color = Color::Indexed(15);

    /// 从 ANSI 30-37, 39, 90-97 前景色代码创建颜色
    pub fn from_ansi_fg(code: u8) -> Option<Self> {
        match code {
            39 => Some(Color::Default),
            30..=37 => Some(Color::Indexed(code - 30)),
            90..=97 => Some(Color::Indexed(code - 82)),
            _ => None,
        }
    }

    /// 从 ANSI 40-47, 49, 100-107 背景色代码创建颜色
    pub fn from_ansi_bg(code: u8) -> Option<Self> {
        match code {
            49 => Some(Color::Default),
            40..=47 => Some(Color::Indexed(code - 40)),
            100..=107 => Some(Color::Indexed(code - 92)),
            _ => None,
        }
    }

    /// 从 8 位调色板索引创建颜色
    pub fn from_8bit(index: u8) -> Self {
        if index < 16 {
            Color::Indexed(index)
        } else {
            Color::Palette(index)
        }
    }

    /// 从 RGB 值创建颜色
    pub fn rgb(r: u8, g: u8, b: u8) -> Self {
        Color::Rgb { r, g, b }
    }

    /// 转换为 (r, g, b) 元组
    ///
    /// 参考 OpenTerm 的 indexedColor 函数实现
    pub fn to_rgb(&self) -> (u8, u8, u8) {
        match self {
            Color::Default => (229, 229, 229), // 默认前景色

            Color::Indexed(idx) => {
                // 标准 16 色（参考 OpenTerm 的 colors 数组）
                const STANDARD_COLORS: [(u8, u8, u8); 16] = [
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
                ];
                if let Some(&(r, g, b)) = STANDARD_COLORS.get(*idx as usize) {
                    (r, g, b)
                } else {
                    (0x99, 0x99, 0x99)
                }
            }

            Color::Palette(idx) => {
                // 16-231: 6x6x6 色立方
                // 232-255: 灰度渐变
                // 参考 OpenTerm 的 indexedColor 实现
                if *idx < 232 {
                    let offset = (*idx as usize) - 16;
                    let cube_size = 6;
                    let v: [u8; 6] = [0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff];
                    let r = v[(offset / (cube_size * cube_size)) % cube_size];
                    let g = v[(offset / cube_size) % cube_size];
                    let b = v[offset % cube_size];
                    (r, g, b)
                } else {
                    // 灰度：232-255
                    let offset = *idx - 232;
                    let value = 8 + offset * 10;
                    (value, value, value)
                }
            }

            Color::Rgb { r, g, b } => (*r, *g, *b),
        }
    }
}

impl Default for Color {
    fn default() -> Self {
        Color::Default
    }
}

/// 单元格属性位标志
///
/// 参考 OpenTerm 的 ANSIFontState 枚举
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct CellAttrs {
    bits: u16,
}

impl CellAttrs {
    /// 加粗 (ANSI 1)
    pub const BOLD: Self = Self { bits: 0x0001 };

    /// 暗淡 (ANSI 2)
    pub const DIM: Self = Self { bits: 0x0002 };

    /// 斜体 (ANSI 3)
    pub const ITALIC: Self = Self { bits: 0x0004 };

    /// 下划线 (ANSI 4)
    pub const UNDERLINE: Self = Self { bits: 0x0008 };

    /// 双下划线 (ANSI 21)
    pub const DOUBLE_UNDERLINE: Self = Self { bits: 0x0010 };

    /// 眨眼 (ANSI 5)
    pub const BLINK: Self = Self { bits: 0x0020 };

    /// 快速眨眼 (ANSI 6)
    pub const RAPID_BLINK: Self = Self { bits: 0x0040 };

    /// 反色 (ANSI 7)
    pub const REVERSE: Self = Self { bits: 0x0080 };

    /// 隐藏 (ANSI 8)
    pub const HIDDEN: Self = Self { bits: 0x0100 };

    /// 删除线 (ANSI 9)
    pub const STRIKETHROUGH: Self = Self { bits: 0x0200 };

    /// 创建空的属性集
    #[inline]
    pub const fn empty() -> Self {
        Self { bits: 0 }
    }

    /// 创建默认属性
    #[inline]
    pub fn default() -> Self {
        Self::empty()
    }

    /// 检查是否包含指定属性
    #[inline]
    pub fn contains(&self, other: Self) -> bool {
        (self.bits & other.bits) == other.bits
    }

    /// 插入属性
    #[inline]
    pub fn insert(&mut self, other: Self) {
        self.bits |= other.bits;
    }

    /// 移除属性
    #[inline]
    pub fn remove(&mut self, other: Self) {
        self.bits &= !other.bits;
    }

    /// 切换属性
    #[inline]
    pub fn toggle(&mut self, other: Self) -> bool {
        self.bits ^= other.bits;
        self.contains(other)
    }

    /// 是否为空
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.bits == 0
    }

    /// 从 ANSI SGR 参数解析属性
    pub fn from_ansi_sgr(codes: &[u16]) -> Vec<Self> {
        let mut attrs = Self::empty();
        for &code in codes {
            match code {
                0 => attrs = Self::empty(),     // Reset
                1 => attrs.insert(Self::BOLD),  // Bold
                2 => attrs.insert(Self::DIM),   // Dim
                3 => attrs.insert(Self::ITALIC), // Italic
                4 => attrs.insert(Self::UNDERLINE), // Underline
                5 => attrs.insert(Self::BLINK), // Blink
                6 => attrs.insert(Self::RAPID_BLINK), // Rapid blink
                7 => attrs.insert(Self::REVERSE), // Reverse
                8 => attrs.insert(Self::HIDDEN), // Hidden
                9 => attrs.insert(Self::STRIKETHROUGH), // Strikethrough
                21 => attrs.insert(Self::DOUBLE_UNDERLINE), // Double underline
                22 => { // Normal intensity (not bold, not dim)
                    attrs.remove(Self::BOLD);
                    attrs.remove(Self::DIM);
                }
                23 => attrs.remove(Self::ITALIC), // Not italic
                24 => { // Not underlined
                    attrs.remove(Self::UNDERLINE);
                    attrs.remove(Self::DOUBLE_UNDERLINE);
                }
                25 => { // Not blinking
                    attrs.remove(Self::BLINK);
                    attrs.remove(Self::RAPID_BLINK);
                }
                27 => attrs.remove(Self::REVERSE), // Not reverse
                28 => attrs.remove(Self::HIDDEN), // Not hidden
                29 => attrs.remove(Self::STRIKETHROUGH), // Not strikethrough
                _ => {}
            }
        }
        vec![attrs]
    }
}

/// 光标帧
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CursorFrame {
    /// 光标列位置（0-based）
    pub x: u16,

    /// 光标行位置（0-based）
    pub y: u16,

    /// 光标是否可见
    pub visible: bool,

    /// 光标样式
    pub style: CursorStyle,
}

impl CursorFrame {
    /// 创建一个新的光标帧
    pub fn new(x: u16, y: u16) -> Self {
        Self {
            x,
            y,
            visible: true,
            style: CursorStyle::Block,
        }
    }

    /// 设置可见性
    pub fn with_visible(mut self, visible: bool) -> Self {
        self.visible = visible;
        self
    }

    /// 设置样式
    pub fn with_style(mut self, style: CursorStyle) -> Self {
        self.style = style;
        self
    }

    /// 隐藏光标
    pub fn hide() -> Self {
        Self {
            x: 0,
            y: 0,
            visible: false,
            style: CursorStyle::Block,
        }
    }
}

impl Default for CursorFrame {
    fn default() -> Self {
        Self::new(0, 0)
    }
}

/// 光标样式
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CursorStyle {
    /// 块状光标
    Block = 0,

    /// 下划线光标
    Underline = 1,

    /// 竖条光标
    Bar = 2,
}

impl Default for CursorStyle {
    fn default() -> Self {
        CursorStyle::Block
    }
}

/// 模式帧
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModeFrame {
    /// 当前模式
    pub mode: Mode,

    /// 模式是否激活
    pub active: bool,
}

impl ModeFrame {
    /// 创建一个新的模式帧
    pub fn new(mode: Mode) -> Self {
        Self {
            mode,
            active: true,
        }
    }

    /// 设置激活状态
    pub fn with_active(mut self, active: bool) -> Self {
        self.active = active;
        self
    }
}

/// 编辑模式
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Mode {
    /// 普通模式
    Normal = 0,

    /// Plan 模式
    Plan = 1,

    /// Agent 模式
    Agent = 2,

    /// 编辑模式
    Edit = 3,
}

impl fmt::Display for Mode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Mode::Normal => write!(f, "Normal"),
            Mode::Plan => write!(f, "Plan"),
            Mode::Agent => write!(f, "Agent"),
            Mode::Edit => write!(f, "Edit"),
        }
    }
}

impl Default for Mode {
    fn default() -> Self {
        Mode::Normal
    }
}

// ========== 帧编码/解码 ==========

/// 协议错误类型
#[derive(Debug, Clone)]
pub enum ProtocolError {
    /// 数据格式错误
    InvalidFormat(String),

    /// 数据不完整
    IncompleteData,

    /// 序列化错误
    SerializationError(String),

    /// 帧类型未知
    UnknownFrameType(u8),
}

impl std::error::Error for ProtocolError {}

impl fmt::Display for ProtocolError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ProtocolError::InvalidFormat(msg) => write!(f, "Invalid format: {}", msg),
            ProtocolError::IncompleteData => write!(f, "Incomplete data"),
            ProtocolError::SerializationError(msg) => write!(f, "Serialization error: {}", msg),
            ProtocolError::UnknownFrameType(t) => write!(f, "Unknown frame type: {}", t),
        }
    }
}

impl From<bincode::Error> for ProtocolError {
    fn from(err: bincode::Error) -> Self {
        ProtocolError::SerializationError(err.to_string())
    }
}

/// 编码帧为二进制数据
///
/// 格式：
/// - [1字节] 帧类型
/// - [4字节] 数据长度 (小端序)
/// - [N字节] 数据内容 (bincode 序列化)
pub fn encode_frame(frame: &Frame) -> Vec<u8> {
    // 先序列化帧数据
    let frame_data = match bincode::serialize(frame) {
        Ok(data) => data,
        Err(_) => return vec![0xFF, 0x00, 0x00, 0x00, 0x00], // 错误标记
    };

    let len = frame_data.len() as u32;

    // 构建最终数据：类型(1) + 长度(4) + 数据(N)
    let mut result = Vec::with_capacity(5 + frame_data.len());

    // 帧类型标记（用于快速识别，实际数据还是用 bincode）
    let type_marker = match frame {
        Frame::Input(_, _) => 0x01,
        Frame::Subscribe(_) => 0x02,
        Frame::CreateSession(_) => 0x03,
        Frame::ResizeSession(_, _, _) => 0x04,
        Frame::CloseSession(_) => 0x05,
        Frame::SessionOutput(_, _) => 0x10,
        Frame::CursorUpdate(_) => 0x11,
        Frame::ModeUpdate(_) => 0x12,
        Frame::SessionCreated(_) => 0x13,
        Frame::SessionClosed(_) => 0x14,
        Frame::Error(_) => 0x15,
        Frame::Ping => 0x20,
        Frame::Pong => 0x21,
    };

    result.push(type_marker);
    result.extend_from_slice(&len.to_le_bytes());
    result.extend_from_slice(&frame_data);

    result
}

/// 从二进制数据解码帧
///
/// 格式：与 encode_frame 对应
pub fn decode_frame(data: &[u8]) -> Result<Frame, ProtocolError> {
    if data.len() < 5 {
        return Err(ProtocolError::IncompleteData);
    }

    let frame_type = data[0];
    let len = u32::from_le_bytes([data[1], data[2], data[3], data[4]]) as usize;

    if data.len() < 5 + len {
        return Err(ProtocolError::IncompleteData);
    }

    let frame_data = &data[5..5 + len];

    // 验证类型标记（可选，用于快速检测）
    match frame_type {
        0x01..=0x05 | 0x10..=0x15 | 0x20..=0x21 => {
            // 有效类型
        }
        _ => return Err(ProtocolError::UnknownFrameType(frame_type)),
    }

    // 使用 bincode 反序列化
    bincode::deserialize(frame_data).map_err(ProtocolError::from)
}

/// 编码多个帧
pub fn encode_frames(frames: &[Frame]) -> Vec<u8> {
    let mut result = Vec::new();
    for frame in frames {
        result.extend_from_slice(&encode_frame(frame));
    }
    result
}

/// 尝试从数据中解码多个帧
///
/// 返回 (解析出的帧列表, 剩余未解析的数据)
pub fn decode_frames(mut data: &[u8]) -> (Vec<Frame>, &[u8]) {
    let mut frames = Vec::new();

    while !data.is_empty() {
        match decode_frame(data) {
            Ok(frame) => {
                let frame_len = 5 + u32::from_le_bytes([data[1], data[2], data[3], data[4]]) as usize;
                if data.len() < frame_len {
                    break;
                }
                frames.push(frame);
                data = &data[frame_len..];
            }
            Err(ProtocolError::IncompleteData) => break,
            Err(_) => {
                // 跳过无效数据
                data = &data[1..];
            }
        }
    }

    (frames, data)
}

// ========== 测试辅助函数 ==========

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode_decode_input() {
        let frame = Frame::Input("session-123".to_string(), vec![0x41, 0x42, 0x43]);
        let encoded = encode_frame(&frame);
        let decoded = decode_frame(&encoded).unwrap();
        assert_eq!(frame, decoded);
    }

    #[test]
    fn test_encode_decode_session_output() {
        let frame = Frame::SessionOutput(
            "session-456".to_string(),
            ScreenFrame {
                seq: 42,
                cols: 80,
                rows: 24,
                dirty_regions: vec![DirtyRegion {
                    x: 0,
                    y: 0,
                    width: 10,
                    height: 1,
                    cells: vec![CellData::new('A').with_fg(Color::RED)],
                }],
            },
        );
        let encoded = encode_frame(&frame);
        let decoded = decode_frame(&encoded).unwrap();
        assert_eq!(frame, decoded);
    }

    #[test]
    fn test_encode_decode_ping_pong() {
        let ping = Frame::Ping;
        let pong = Frame::Pong;

        assert_eq!(decode_frame(&encode_frame(&ping)).unwrap(), ping);
        assert_eq!(decode_frame(&encode_frame(&pong)).unwrap(), pong);
    }

    #[test]
    fn test_encode_decode_error() {
        let frame = Frame::Error("Something went wrong".to_string());
        let encoded = encode_frame(&frame);
        let decoded = decode_frame(&encoded).unwrap();
        assert_eq!(frame, decoded);
    }

    #[test]
    fn test_multiple_frames() {
        let frames = vec![
            Frame::Ping,
            Frame::Pong,
            Frame::Input("test".to_string(), vec![0x01]),
        ];
        let encoded = encode_frames(&frames);
        let (decoded, remaining) = decode_frames(&encoded);
        assert_eq!(decoded.len(), 3);
        assert!(remaining.is_empty());
        assert_eq!(decoded[0], frames[0]);
        assert_eq!(decoded[1], frames[1]);
        assert_eq!(decoded[2], frames[2]);
    }

    #[test]
    fn test_color_rgb() {
        assert_eq!(Color::RED.to_rgb(), (0x99, 0x3E, 0x3E));
        assert_eq!(Color::GREEN.to_rgb(), (0x3E, 0x99, 0x3E));
        assert_eq!(Color::BRIGHT_RED.to_rgb(), (0xFF, 0x67, 0x67));
        assert_eq!(Color::rgb(255, 128, 0).to_rgb(), (255, 128, 0));
    }

    #[test]
    fn test_color_palette() {
        // 测试 6x6x6 色立方
        let color = Color::from_8bit(16); // 立方体起始颜色
        assert_eq!(color.to_rgb(), (0x00, 0x00, 0x00));

        let color = Color::from_8bit(21); // (1, 0, 0) in cube
        assert_eq!(color.to_rgb(), (0x5f, 0x00, 0x00));

        // 测试灰度
        let color = Color::from_8bit(232); // 灰度起始
        assert_eq!(color.to_rgb(), (8, 8, 8));

        let color = Color::from_8bit(255); // 灰度结束
        assert_eq!(color.to_rgb(), (238, 238, 238));
    }

    #[test]
    fn test_cell_attrs() {
        let mut attrs = CellAttrs::empty();
        assert!(attrs.is_empty());

        attrs.insert(CellAttrs::BOLD);
        attrs.insert(CellAttrs::UNDERLINE);
        assert!(attrs.contains(CellAttrs::BOLD));
        assert!(attrs.contains(CellAttrs::UNDERLINE));
        assert!(!attrs.contains(CellAttrs::ITALIC));

        attrs.remove(CellAttrs::BOLD);
        assert!(!attrs.contains(CellAttrs::BOLD));
        assert!(attrs.contains(CellAttrs::UNDERLINE));
    }

    #[test]
    fn test_create_session_request() {
        let req = CreateSessionRequest::shell();
        assert_eq!(req.command, "sh");
        assert_eq!(req.args, vec!["-l"]);

        let req = CreateSessionRequest::command("vim", vec!["file.txt".to_string()])
            .with_cwd("/home/user".to_string());
        assert_eq!(req.command, "vim");
        assert_eq!(req.cwd, Some("/home/user".to_string()));
    }
}
