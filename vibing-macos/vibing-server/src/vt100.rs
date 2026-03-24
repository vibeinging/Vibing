//
//  vt100.rs
//  Vibe Terminal Server
//
//  VT100/ANSI 转义序列解析器
//

use std::collections::VecDeque;

// ============================================================================
// 颜色系统
// ============================================================================

/// 终端颜色
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Color {
    /// 默认前景色
    DefaultForeground,
    /// 默认背景色
    DefaultBackground,
    /// 索引颜色 (0-255)
    Indexed(u8),
    /// RGB 真彩色
    Rgb(u8, u8, u8),
}

impl Color {
    /// 获取默认前景色
    pub fn default_fg() -> Self {
        Color::DefaultForeground
    }

    /// 获取默认背景色
    pub fn default_bg() -> Self {
        Color::DefaultBackground
    }

    /// 将索引颜色转换为 RGB
    pub fn to_rgb(&self) -> (u8, u8, u8) {
        match self {
            Color::DefaultForeground => (212, 212, 212),
            Color::DefaultBackground => (28, 28, 28),
            Color::Indexed(idx) => indexed_color_to_rgb(*idx),
            Color::Rgb(r, g, b) => (*r, *g, *b),
        }
    }
}

/// 标准颜色表 (参考 ANSITextState.swift)
const STANDARD_COLORS: [(u8, u8, u8); 16] = [
    // 标准颜色 (0-7)
    (0x00, 0x00, 0x00), // 黑色
    (0x99, 0x3E, 0x3E), // 红色
    (0x3E, 0x99, 0x3E), // 绿色
    (0x99, 0x99, 0x3E), // 黄色/棕色
    (0x3E, 0x3E, 0x99), // 蓝色
    (0x99, 0x3E, 0x99), // 品红
    (0x3E, 0x99, 0x99), // 青色
    (0x99, 0x99, 0x99), // 白色
    // 高亮颜色 (8-15)
    (0x3E, 0x3E, 0x3E), // 黑色 (亮)
    (0xFF, 0x67, 0x67), // 红色 (亮)
    (0x67, 0xFF, 0x67), // 绿色 (亮)
    (0xFF, 0xFF, 0x67), // 黄色 (亮)
    (0x67, 0x67, 0xFF), // 蓝色 (亮)
    (0xFF, 0x67, 0xFF), // 品红 (亮)
    (0x67, 0xFF, 0xFF), // 青色 (亮)
    (0xFF, 0xFF, 0xFF), // 白色 (亮)
];

/// 6x6x6 色立方体的值
const CUBE_VALUES: [u8; 6] = [0x00, 0x5F, 0x87, 0xAF, 0xD7, 0xFF];

/// 将索引颜色转换为 RGB
fn indexed_color_to_rgb(index: u8) -> (u8, u8, u8) {
    if index < 16 {
        let (r, g, b) = STANDARD_COLORS[index as usize];
        (r, g, b)
    } else if index < 232 {
        // 16-231: 6x6x6 色立方
        let offset = index - 16;
        let r = CUBE_VALUES[((offset / 36) % 6) as usize];
        let g = CUBE_VALUES[((offset / 6) % 6) as usize];
        let b = CUBE_VALUES[(offset % 6) as usize];
        (r, g, b)
    } else {
        // 232-255: 灰度
        let offset = index - 232;
        let value = 8 + offset * 10;
        (value, value, value)
    }
}

// ============================================================================
// 单元格属性
// ============================================================================

/// 单元格属性位标志
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct CellAttrs {
    pub flags: u16,
}

impl CellAttrs {
    /// 粗体
    pub const BOLD: u16 = 0x01;
    /// 暗淡
    pub const FAINT: u16 = 0x02;
    /// 斜体
    pub const ITALIC: u16 = 0x04;
    /// 下划线
    pub const UNDERLINE: u16 = 0x08;
    /// 闪烁
    pub const BLINK: u16 = 0x10;
    /// 反色
    pub const REVERSE: u16 = 0x20;
    /// 隐藏
    pub const HIDDEN: u16 = 0x40;
    /// 删除线
    pub const STRIKETHROUGH: u16 = 0x80;

    pub fn new() -> Self {
        Self { flags: 0 }
    }

    pub fn is_bold(&self) -> bool {
        self.flags & Self::BOLD != 0
    }

    pub fn is_faint(&self) -> bool {
        self.flags & Self::FAINT != 0
    }

    pub fn is_italic(&self) -> bool {
        self.flags & Self::ITALIC != 0
    }

    pub fn is_underline(&self) -> bool {
        self.flags & Self::UNDERLINE != 0
    }

    pub fn is_blink(&self) -> bool {
        self.flags & Self::BLINK != 0
    }

    pub fn is_reverse(&self) -> bool {
        self.flags & Self::REVERSE != 0
    }

    pub fn is_hidden(&self) -> bool {
        self.flags & Self::HIDDEN != 0
    }

    pub fn is_strikethrough(&self) -> bool {
        self.flags & Self::STRIKETHROUGH != 0
    }

    pub fn set(&mut self, flag: u16, value: bool) {
        if value {
            self.flags |= flag;
        } else {
            self.flags &= !flag;
        }
    }

    pub fn reset(&mut self) {
        self.flags = 0;
    }
}

// ============================================================================
// 单元格
// ============================================================================

/// 终端单元格
#[derive(Debug, Clone, PartialEq)]
pub struct Cell {
    pub char: char,
    pub fg_color: Color,
    pub bg_color: Color,
    pub attrs: CellAttrs,
}

impl Cell {
    pub fn new() -> Self {
        Self {
            char: ' ',
            fg_color: Color::default_fg(),
            bg_color: Color::default_bg(),
            attrs: CellAttrs::new(),
        }
    }

    pub fn with_char(mut self, c: char) -> Self {
        self.char = c;
        self
    }

    pub fn with_fg(mut self, color: Color) -> Self {
        self.fg_color = color;
        self
    }

    pub fn with_bg(mut self, color: Color) -> Self {
        self.bg_color = color;
        self
    }

    pub fn clear(&mut self) {
        self.char = ' ';
        self.fg_color = Color::default_fg();
        self.bg_color = Color::default_bg();
        self.attrs.reset();
    }
}

impl Default for Cell {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// 脏区域
// ============================================================================

/// 脏区域 - 用于增量更新
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirtyRegion {
    pub x: u16,
    pub y: u16,
    pub cols: u16,
    pub rows: u16,
}

impl DirtyRegion {
    pub fn new(x: u16, y: u16, cols: u16, rows: u16) -> Self {
        Self { x, y, cols, rows }
    }

    pub fn contains(&self, x: u16, y: u16) -> bool {
        x >= self.x && x < self.x + self.cols && y >= self.y && y < self.y + self.rows
    }

    /// 合并两个区域
    pub fn merge(&self, other: &DirtyRegion) -> Option<DirtyRegion> {
        let x1 = self.x.min(other.x);
        let y1 = self.y.min(other.y);
        let x2 = (self.x + self.cols).max(other.x + other.cols);
        let y2 = (self.y + self.rows).max(other.y + other.rows);

        // 限制最大区域大小，避免合并后区域过大
        if x2 - x1 > 200 || y2 - y1 > 100 {
            return None;
        }

        Some(DirtyRegion {
            x: x1,
            y: y1,
            cols: x2 - x1,
            rows: y2 - y1,
        })
    }
}

// ============================================================================
// 终端状态
// ============================================================================

/// 终端状态
#[derive(Debug, Clone)]
pub struct TerminalState {
    pub cols: u16,
    pub rows: u16,
    pub cells: Vec<Vec<Cell>>,
    pub cursor_x: u16,
    pub cursor_y: u16,
    pub scroll_top: u16,
    pub scroll_bottom: u16,
    pub attrs: CellAttrs,
    pub fg_color: Color,
    pub bg_color: Color,

    // 脏区域追踪
    dirty_regions: Vec<DirtyRegion>,
    // 滚动历史
    scrollback: VecDeque<Vec<Cell>>,
    scrollback_max: usize,
}

impl TerminalState {
    pub fn new(cols: u16, rows: u16) -> Self {
        let cells = vec![vec![Cell::new(); cols as usize]; rows as usize];

        Self {
            cols,
            rows,
            cells,
            cursor_x: 0,
            cursor_y: 0,
            scroll_top: 0,
            scroll_bottom: rows - 1,
            attrs: CellAttrs::new(),
            fg_color: Color::default_fg(),
            bg_color: Color::default_bg(),
            dirty_regions: Vec::new(),
            scrollback: VecDeque::with_capacity(1000),
            scrollback_max: 1000,
        }
    }

    pub fn resize(&mut self, cols: u16, rows: u16) {
        if cols == self.cols && rows == self.rows {
            return;
        }

        let mut new_cells = vec![vec![Cell::new(); cols as usize]; rows as usize];

        // 复制现有内容
        for (y, row) in new_cells.iter_mut().enumerate().take(self.rows as usize) {
            for (x, cell) in row.iter_mut().enumerate().take(self.cols as usize) {
                *cell = self.cells[y][x].clone();
            }
        }

        self.cells = new_cells;
        self.cols = cols;
        self.rows = rows;
        self.scroll_bottom = rows - 1;

        // 调整光标位置
        self.cursor_x = self.cursor_x.min(cols);
        self.cursor_y = self.cursor_y.min(rows);

        // 标记全屏为脏
        self.mark_dirty(0, 0, cols, rows);
    }

    /// 标记区域为脏
    pub fn mark_dirty(&mut self, x: u16, y: u16, cols: u16, rows: u16) {
        let region = DirtyRegion {
            x: x.min(self.cols),
            y: y.min(self.rows),
            cols: cols.min(self.cols - x.min(self.cols)),
            rows: rows.min(self.rows - y.min(self.rows)),
        };

        // 尝试合并到现有区域
        let mut merged = false;
        for existing in &mut self.dirty_regions {
            if let Some(merged_region) = existing.merge(&region) {
                *existing = merged_region;
                merged = true;
                break;
            }
        }

        if !merged && region.cols > 0 && region.rows > 0 {
            self.dirty_regions.push(region);
        }
    }

    /// 标记单个单元格为脏
    pub fn mark_cell_dirty(&mut self, x: u16, y: u16) {
        self.mark_dirty(x, y, 1, 1);
    }

    /// 获取并清除脏区域
    pub fn take_dirty_regions(&mut self) -> Vec<DirtyRegion> {
        std::mem::take(&mut self.dirty_regions)
    }

    /// 清除屏幕
    pub fn clear_screen(&mut self) {
        for row in &mut self.cells {
            for cell in row {
                cell.clear();
            }
        }
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.mark_dirty(0, 0, self.cols, self.rows);
    }

    /// 清除行
    pub fn clear_line(&mut self, mode: ClearLineMode) {
        let row = self.cursor_y as usize;
        let col = self.cursor_x as usize;

        match mode {
            ClearLineMode::Right => {
                for cell in &mut self.cells[row][col..] {
                    cell.clear();
                }
                self.mark_dirty(self.cursor_x, self.cursor_y, self.cols - self.cursor_x, 1);
            }
            ClearLineMode::Left => {
                for cell in &mut self.cells[row][..=col] {
                    cell.clear();
                }
                self.mark_dirty(0, self.cursor_y, self.cursor_x + 1, 1);
            }
            ClearLineMode::All => {
                for cell in &mut self.cells[row] {
                    cell.clear();
                }
                self.mark_dirty(0, self.cursor_y, self.cols, 1);
            }
        }
    }

    /// 清除区域
    pub fn clear(&mut self, mode: ClearMode) {
        match mode {
            ClearMode::ToEnd => {
                // 清除从光标到屏幕末尾
                for y in self.cursor_y..self.rows {
                    let start_x = if y == self.cursor_y { self.cursor_x } else { 0 };
                    for x in start_x..self.cols {
                        self.cells[y as usize][x as usize].clear();
                    }
                    self.mark_dirty(start_x, y, self.cols - start_x, 1);
                }
            }
            ClearMode::FromStart => {
                // 清除从屏幕开始到光标
                for y in 0..=self.cursor_y {
                    let end_x = if y == self.cursor_y { self.cursor_x + 1 } else { self.cols };
                    for x in 0..end_x {
                        self.cells[y as usize][x as usize].clear();
                    }
                    self.mark_dirty(0, y, end_x, 1);
                }
            }
            ClearMode::All => {
                self.clear_screen();
            }
        }
    }

    /// 向上滚动
    pub fn scroll_up(&mut self, count: u16) {
        let top = self.scroll_top as usize;
        let bottom = (self.scroll_bottom + 1) as usize;
        let count = count as usize;

        // 保存行到滚动历史
        for _ in 0..count.min(bottom - top) {
            if let Some(row) = self.cells.get(top) {
                if self.scrollback.len() >= self.scrollback_max {
                    self.scrollback.pop_front();
                }
                self.scrollback.push_back(row.clone());
            }
        }

        // 移动行
        for y in top..(bottom - count) {
            self.cells[y] = self.cells[y + count].clone();
        }

        // 清空底部行
        for y in (bottom - count)..bottom {
            for cell in &mut self.cells[y] {
                cell.clear();
            }
        }

        self.mark_dirty(self.scroll_top, 0, self.cols, self.scroll_bottom - self.scroll_top + 1);
    }

    /// 向下滚动
    pub fn scroll_down(&mut self, count: u16) {
        let top = self.scroll_top as usize;
        let bottom = (self.scroll_bottom + 1) as usize;
        let count = count as usize;

        // 移动行
        for y in ((top + count)..bottom).rev() {
            if y >= count {
                self.cells[y] = self.cells[y - count].clone();
            }
        }

        // 清空顶部行
        for y in top..(top + count) {
            for cell in &mut self.cells[y] {
                cell.clear();
            }
        }

        self.mark_dirty(self.scroll_top, 0, self.cols, self.scroll_bottom - self.scroll_top + 1);
    }

    /// 移动光标
    pub fn move_cursor(&mut self, x: u16, y: u16) {
        self.cursor_x = x.min(self.cols - 1);
        self.cursor_y = y.min(self.rows - 1);
    }

    /// 相对移动光标
    pub fn move_cursor_relative(&mut self, dx: i16, dy: i16) {
        let new_x = (self.cursor_x as i16 + dx).clamp(0, self.cols as i16 - 1) as u16;
        let new_y = (self.cursor_y as i16 + dy).clamp(0, self.rows as i16 - 1) as u16;
        self.cursor_x = new_x;
        self.cursor_y = new_y;
    }

    /// 设置光标位置 (1-based, 用于 ESC[H/f)
    pub fn set_cursor(&mut self, x: u16, y: u16) {
        // x 和 y 是 1-based, 0 表示保持原位
        let new_x = if x == 0 { self.cursor_x } else { x - 1 };
        let new_y = if y == 0 { self.cursor_y } else { y - 1 };
        self.move_cursor(new_x, new_y);
    }

    /// 设置滚动区域
    pub fn set_scroll_region(&mut self, top: u16, bottom: u16) {
        self.scroll_top = top.min(self.rows - 1);
        self.scroll_bottom = if bottom == 0 {
            self.rows - 1
        } else {
            bottom.min(self.rows - 1)
        };
    }

    /// 重置属性
    pub fn reset_attrs(&mut self) {
        self.attrs.reset();
        self.fg_color = Color::default_fg();
        self.bg_color = Color::default_bg();
    }

    /// 写入字符
    pub fn write_char(&mut self, c: char) {
        match c {
            '\r' => {
                self.cursor_x = 0;
            }
            '\n' => {
                self.cursor_y += 1;
                if self.cursor_y > self.scroll_bottom {
                    self.scroll_up(1);
                    self.cursor_y = self.scroll_bottom;
                }
            }
            '\t' => {
                // 制表符移动到下一个 8 的倍数
                let tab_size = 8;
                self.cursor_x = ((self.cursor_x / tab_size) + 1) * tab_size;
                if self.cursor_x >= self.cols {
                    self.cursor_x = 0;
                    self.cursor_y += 1;
                }
            }
            '\x08' => {
                // 退格
                if self.cursor_x > 0 {
                    self.cursor_x -= 1;
                }
            }
            _ => {
                // 普通字符
                if self.cursor_x < self.cols && self.cursor_y < self.rows {
                    let row = &mut self.cells[self.cursor_y as usize];
                    let cell = &mut row[self.cursor_x as usize];
                    cell.char = c;
                    cell.fg_color = self.fg_color;
                    cell.bg_color = self.bg_color;
                    cell.attrs = self.attrs;

                    self.mark_cell_dirty(self.cursor_x, self.cursor_y);

                    self.cursor_x += 1;
                    if self.cursor_x >= self.cols {
                        self.cursor_x = 0;
                        self.cursor_y += 1;
                        if self.cursor_y > self.scroll_bottom {
                            self.scroll_up(1);
                            self.cursor_y = self.scroll_bottom;
                        }
                    }
                }
            }
        }
    }

    /// 删除字符 (ECH)
    pub fn erase_chars(&mut self, count: u16) {
        let row = self.cursor_y as usize;
        let col = self.cursor_x as usize;
        let count = count as usize;

        for x in col..(col + count).min(self.cols as usize) {
            self.cells[row][x].clear();
        }

        self.mark_dirty(self.cursor_x, self.cursor_y, count as u16, 1);
    }

    /// 删除行 (DL)
    pub fn delete_lines(&mut self, count: u16) {
        let row = self.cursor_y as usize;
        let count = count as usize;
        let bottom = (self.scroll_bottom + 1) as usize;

        // 移动行
        for y in row..(bottom - count) {
            self.cells[y] = self.cells[y + count].clone();
        }

        // 清空底部行
        for y in (bottom - count)..bottom {
            for cell in &mut self.cells[y] {
                cell.clear();
            }
        }

        self.mark_dirty(self.cursor_x, self.cursor_y, self.cols - self.cursor_x, 1);
    }

    /// 插入行 (IL)
    pub fn insert_lines(&mut self, count: u16) {
        let row = self.cursor_y as usize;
        let count = count as usize;
        let bottom = (self.scroll_bottom + 1) as usize;

        // 移动行
        for y in ((row + count)..bottom).rev() {
            self.cells[y] = self.cells[y - count].clone();
        }

        // 清空新插入的行
        for y in row..(row + count) {
            for cell in &mut self.cells[y] {
                cell.clear();
            }
        }

        self.mark_dirty(0, self.cursor_y, self.cols, count as u16);
    }
}

/// 清除模式
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClearMode {
    ToEnd,      // 从光标到屏幕末尾
    FromStart,  // 从屏幕开始到光标
    All,        // 整个屏幕
}

/// 清除行模式
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClearLineMode {
    Right,  // 从光标到行尾
    Left,   // 从行首到光标
    All,    // 整行
}

// ============================================================================
// 解析器状态
// ============================================================================

/// 解析器状态
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ParserState {
    Ground,          // 正常状态
    Escape,          // 收到 ESC
    EscapeIntermediate, // ESC 后的中间字符
    CsiEntry,        // CSI 入口 (ESC[)
    CsiParam,        // CSI 参数
    CsiIntermediate, // CSI 中间字符
    CsiIgnore,       // CSI 忽略
    DcsEntry,        // DCS 入口
    DcsParam,        // DCS 参数
    DcsPassthrough,  // DCS 透传
    DcsIgnore,       // DCS 忽略
    OscString,       // OSC 字符串
    SosPmApcString,  // SOS/PM/APC 字符串
}

/// ANSI 转义序列动作
#[derive(Debug, Clone, PartialEq)]
enum AnsiAction {
    // 光标移动
    CursorUp(u16),
    CursorDown(u16),
    CursorForward(u16),
    CursorBackward(u16),
    CursorNextLine(u16),
    CursorPreviousLine(u16),
    CursorHorizontalAbs(u16),
    CursorPosition { row: u16, col: u16 },
    SaveCursor,
    RestoreCursor,

    // 屏幕编辑
    EraseDisplay(ClearMode),
    EraseLine(ClearLineMode),
    InsertLines(u16),
    DeleteLines(u16),
    DeleteChars(u16),
    EraseChars(u16),

    // 滚动
    SetScrollRegion { top: u16, bottom: u16 },

    // 属性
    SetGraphicsRgr(Vec<u16>),
    ResetGraphics,

    // 模式设置
    SetMode(bool, Vec<u16>),  // DECSET/DECRST

    // 设备属性
    DeviceAttributes,
    QueryCursorPosition,

    // 标签
    SetWindowTitle(String),

    // 忽略
    Ignore,
}

/// 解析 CSI 参数
fn parse_csi_params(params: &str) -> Vec<u16> {
    params
        .split(';')
        .map(|s| s.parse().unwrap_or(0))
        .collect()
}

// ============================================================================
// VT100 解析器
// ============================================================================

/// 保存的光标状态
#[derive(Debug, Clone)]
struct SavedCursorState {
    x: u16,
    y: u16,
    attrs: CellAttrs,
    fg_color: Color,
    bg_color: Color,
}

impl SavedCursorState {
    fn new() -> Self {
        Self {
            x: 0,
            y: 0,
            attrs: CellAttrs::new(),
            fg_color: Color::default_fg(),
            bg_color: Color::default_bg(),
        }
    }
}

/// VT100/ANSI 解析器
pub struct Vt100Parser {
    state: TerminalState,
    escape_buffer: Vec<u8>,
    parser_state: ParserState,
    params_buffer: String,
    string_buffer: String,
    saved: SavedCursorState,
}

impl Vt100Parser {
    pub fn new(cols: u16, rows: u16) -> Self {
        Self {
            state: TerminalState::new(cols, rows),
            escape_buffer: Vec::new(),
            parser_state: ParserState::Ground,
            params_buffer: String::new(),
            string_buffer: String::new(),
            saved: SavedCursorState::new(),
        }
    }

    /// 处理输入数据
    pub fn process(&mut self, data: &[u8]) -> Vec<DirtyRegion> {
        // 清除之前的脏区域
        self.state.dirty_regions.clear();

        // 处理每个字节
        for &byte in data {
            self.process_byte(byte);
        }

        self.state.take_dirty_regions()
    }

    /// 处理单个字节
    fn process_byte(&mut self, byte: u8) {
        match self.parser_state {
            ParserState::Ground => {
                match byte {
                    0x00..=0x17 | 0x19 | 0x1C..=0x1F => {
                        // 控制字符 (C0)
                        self.handle_control(byte);
                    }
                    0x1B => {
                        // ESC
                        self.parser_state = ParserState::Escape;
                        self.escape_buffer.clear();
                    }
                    0x7F => {
                        // DEL
                    }
                    0x80..=0x8F | 0x91..=0x97 | 0x99 | 0x9A | 0x9C => {
                        // 控制字符 (C1)
                        self.handle_control(byte);
                    }
                    0x98 | 0x9E | 0x9F => {
                        // G0 集合
                    }
                    _ => {
                        // 可打印字符
                        if let Ok(s) = std::str::from_utf8(&[byte]) {
                            for c in s.chars() {
                                self.state.write_char(c);
                            }
                        }
                    }
                }
            }
            ParserState::Escape => {
                self.escape_buffer.push(byte);
                match byte {
                    0x5B => {
                        // [ - CSI 序列
                        self.parser_state = ParserState::CsiEntry;
                        self.params_buffer.clear();
                    }
                    0x5D => {
                        // ] - OSC 序列
                        self.parser_state = ParserState::OscString;
                        self.string_buffer.clear();
                    }
                    0x50 => {
                        // P - DCS 序列
                        self.parser_state = ParserState::DcsEntry;
                        self.params_buffer.clear();
                    }
                    0x58 | 0x5E | 0x5F => {
                        // X, ^, _ - SOS/PM/APC
                        self.parser_state = ParserState::SosPmApcString;
                        self.string_buffer.clear();
                    }
                    0x4D => {
                        // M - 反向索引
                        self.state.scroll_up(1);
                        self.parser_state = ParserState::Ground;
                    }
                    0x37 => {
                        // 7 - 保存光标
                        self.action(AnsiAction::SaveCursor);
                        self.parser_state = ParserState::Ground;
                    }
                    0x38 => {
                        // 8 - 恢复光标
                        self.action(AnsiAction::RestoreCursor);
                        self.parser_state = ParserState::Ground;
                    }
                    0x63 => {
                        // c - RIS (重置)
                        self.state.clear_screen();
                        self.state.reset_attrs();
                        self.parser_state = ParserState::Ground;
                    }
                    _ => {
                        // 其他 ESC 序列，尝试执行
                        self.escape_buffer.push(0);
                        if let Some(action) = self.parse_escape_sequence(&self.escape_buffer) {
                            self.action(action);
                        }
                        self.parser_state = ParserState::Ground;
                    }
                }
            }
            ParserState::CsiEntry => {
                match byte {
                    0x20..=0x2F => {
                        // 中间字符
                        self.parser_state = ParserState::CsiIntermediate;
                    }
                    0x30..=0x39 | 0x3B => {
                        // 参数字符
                        self.params_buffer.push(byte as char);
                        self.parser_state = ParserState::CsiParam;
                    }
                    0x3C..=0x3F => {
                        // 私有参数
                        self.params_buffer.push(byte as char);
                        self.parser_state = ParserState::CsiParam;
                    }
                    _ => {
                        // 直接执行
                        self.params_buffer.push(byte as char);
                        if let Some(action) = self.parse_csi_sequence(&self.params_buffer) {
                            self.action(action);
                        }
                        self.parser_state = ParserState::Ground;
                    }
                }
            }
            ParserState::CsiParam => {
                match byte {
                    0x20..=0x2F => {
                        self.parser_state = ParserState::CsiIntermediate;
                    }
                    0x30..=0x3F => {
                        self.params_buffer.push(byte as char);
                    }
                    _ => {
                        self.params_buffer.push(byte as char);
                        if let Some(action) = self.parse_csi_sequence(&self.params_buffer) {
                            self.action(action);
                        }
                        self.parser_state = ParserState::Ground;
                    }
                }
            }
            ParserState::CsiIntermediate => {
                match byte {
                    0x20..=0x2F => {
                        self.params_buffer.push(byte as char);
                    }
                    0x40..=0x7E => {
                        self.params_buffer.push(byte as char);
                        if let Some(action) = self.parse_csi_sequence(&self.params_buffer) {
                            self.action(action);
                        }
                        self.parser_state = ParserState::Ground;
                    }
                    _ => {
                        self.parser_state = ParserState::CsiIgnore;
                    }
                }
            }
            ParserState::CsiIgnore => {
                match byte {
                    0x40..=0x7E => {
                        self.parser_state = ParserState::Ground;
                    }
                    _ => {}
                }
            }
            ParserState::OscString => {
                // OSC 结束于 ST (ESC \) 或 BEL
                if byte == 0x07 || (byte == 0x1B && self.escape_buffer.last() == Some(&0x5C)) {
                    if let Some(action) = self.parse_osc_sequence(&self.string_buffer) {
                        self.action(action);
                    }
                    self.parser_state = ParserState::Ground;
                    self.escape_buffer.clear();
                } else if byte == 0x1B {
                    self.escape_buffer.push(byte);
                } else {
                    self.string_buffer.push(byte as char);
                }
            }
            ParserState::DcsEntry | ParserState::DcsParam | ParserState::DcsPassthrough => {
                // DCS 序列，暂时忽略
                if byte == 0x1B {
                    self.escape_buffer.clear();
                    self.escape_buffer.push(byte);
                } else if byte == 0x5C && self.escape_buffer.last() == Some(&0x1B) {
                    self.parser_state = ParserState::Ground;
                }
            }
            ParserState::DcsIgnore => {
                if byte == 0x1B {
                    self.escape_buffer.clear();
                    self.escape_buffer.push(byte);
                } else if byte == 0x5C {
                    self.parser_state = ParserState::Ground;
                }
            }
            ParserState::SosPmApcString => {
                // 忽略这些序列
                if byte == 0x1B {
                    self.escape_buffer.clear();
                    self.escape_buffer.push(byte);
                } else if byte == 0x5C {
                    self.parser_state = ParserState::Ground;
                }
            }
            ParserState::EscapeIntermediate => {
                // ESC 后的中间字符，等待终止符
                match byte {
                    0x20..=0x2F => {
                        // 中间字符，继续等待
                    }
                    0x40..=0x7E => {
                        // 终止符，执行动作
                        self.parser_state = ParserState::Ground;
                    }
                    _ => {
                        // 无效字符，忽略
                        self.parser_state = ParserState::Ground;
                    }
                }
            }
        }
    }

    /// 处理控制字符
    fn handle_control(&mut self, byte: u8) {
        match byte {
            0x00 => {} // NUL
            0x07 => {} // BEL
            0x08 => self.state.write_char('\x08'), // BS
            0x09 => self.state.write_char('\t'),   // HT
            0x0A => self.state.write_char('\n'),   // LF
            0x0B => self.state.write_char('\n'),   // VT
            0x0C => self.state.write_char('\n'),   // FF
            0x0D => self.state.write_char('\r'),   // CR
            0x0E => {} // SO
            0x0F => {} // SI
            _ => {}
        }
    }

    /// 解析 ESC 序列
    fn parse_escape_sequence(&self, buffer: &[u8]) -> Option<AnsiAction> {
        if buffer.is_empty() {
            return None;
        }

        let byte = buffer[0];
        match byte {
            // 这里处理非 CSI 的 ESC 序列
            _ => None,
        }
    }

    /// 解析 CSI 序列
    fn parse_csi_sequence(&self, buffer: &str) -> Option<AnsiAction> {
        if buffer.is_empty() {
            return None;
        }

        // 获取最后一个字符（命令）
        let command = buffer.chars().last()?;
        let params = &buffer[..buffer.len() - 1];

        // 解析参数
        let nums: Vec<u16> = if params.is_empty() {
            vec![0]
        } else {
            params.split(';').map(|s| s.parse().unwrap_or(0)).collect()
        };

        match command {
            // 光标移动
            'A' => Some(AnsiAction::CursorUp(nums.get(0).copied().unwrap_or(1))),
            'B' => Some(AnsiAction::CursorDown(nums.get(0).copied().unwrap_or(1))),
            'C' => Some(AnsiAction::CursorForward(nums.get(0).copied().unwrap_or(1))),
            'D' => Some(AnsiAction::CursorBackward(nums.get(0).copied().unwrap_or(1))),
            'E' => Some(AnsiAction::CursorNextLine(nums.get(0).copied().unwrap_or(1))),
            'F' => Some(AnsiAction::CursorPreviousLine(nums.get(0).copied().unwrap_or(1))),
            'G' => Some(AnsiAction::CursorHorizontalAbs(nums.get(0).copied().unwrap_or(1))),
            'H' | 'f' => {
                let row = nums.get(0).copied().unwrap_or(1);
                let col = nums.get(1).copied().unwrap_or(1);
                Some(AnsiAction::CursorPosition { row, col })
            }
            'd' => Some(AnsiAction::CursorPosition {
                row: nums.get(0).copied().unwrap_or(1),
                col: 0,
            }),

            // 屏幕编辑
            'J' => {
                let mode = match nums.get(0).copied().unwrap_or(0) {
                    0 => ClearMode::ToEnd,
                    1 => ClearMode::FromStart,
                    2 => ClearMode::All,
                    _ => ClearMode::ToEnd,
                };
                Some(AnsiAction::EraseDisplay(mode))
            }
            'K' => {
                let mode = match nums.get(0).copied().unwrap_or(0) {
                    0 => ClearLineMode::Right,
                    1 => ClearLineMode::Left,
                    2 => ClearLineMode::All,
                    _ => ClearLineMode::Right,
                };
                Some(AnsiAction::EraseLine(mode))
            }
            'L' => Some(AnsiAction::InsertLines(nums.get(0).copied().unwrap_or(1))),
            'M' => Some(AnsiAction::DeleteLines(nums.get(0).copied().unwrap_or(1))),
            'P' => Some(AnsiAction::DeleteChars(nums.get(0).copied().unwrap_or(1))),
            'X' => Some(AnsiAction::EraseChars(nums.get(0).copied().unwrap_or(1))),

            // 滚动区域
            'r' => {
                let top = nums.get(0).copied().unwrap_or(1).max(1);
                let bottom = nums.get(1).copied().unwrap_or(0);
                Some(AnsiAction::SetScrollRegion {
                    top: top - 1,
                    bottom,
                })
            }

            // 属性
            'm' => Some(AnsiAction::SetGraphicsRgr(nums)),

            // 设备属性
            'c' => Some(AnsiAction::DeviceAttributes),
            'n' => {
                if nums.get(0) == Some(&6) {
                    Some(AnsiAction::QueryCursorPosition)
                } else {
                    Some(AnsiAction::Ignore)
                }
            }

            // 模式设置
            'h' | 'l' => {
                let set = command == 'h';
                Some(AnsiAction::SetMode(set, nums))
            }

            // 忽略
            _ => Some(AnsiAction::Ignore),
        }
    }

    /// 解析 OSC 序列
    fn parse_osc_sequence(&self, buffer: &str) -> Option<AnsiAction> {
        if buffer.is_empty() {
            return None;
        }

        // OSC 格式: Ps;Pt
        // Ps 是参数，Pt 是文本
        let parts: Vec<&str> = buffer.splitn(2, ';').collect();
        if parts.is_empty() {
            return None;
        }

        let ps = parts[0].parse::<u16>().ok()?;

        match ps {
            0 | 2 => {
                // 设置窗口标题
                if parts.len() > 1 {
                    Some(AnsiAction::SetWindowTitle(parts[1].to_string()))
                } else {
                    None
                }
            }
            _ => Some(AnsiAction::Ignore),
        }
    }

    /// 执行 ANSI 动作
    fn action(&mut self, action: AnsiAction) {
        match action {
            AnsiAction::CursorUp(n) => {
                self.state.move_cursor_relative(0, -(n as i16));
            }
            AnsiAction::CursorDown(n) => {
                self.state.move_cursor_relative(0, n as i16);
            }
            AnsiAction::CursorForward(n) => {
                self.state.move_cursor_relative(n as i16, 0);
            }
            AnsiAction::CursorBackward(n) => {
                self.state.move_cursor_relative(-(n as i16), 0);
            }
            AnsiAction::CursorNextLine(n) => {
                self.state.move_cursor(0, self.state.cursor_y + n);
            }
            AnsiAction::CursorPreviousLine(n) => {
                let new_y = self.state.cursor_y.saturating_sub(n);
                self.state.move_cursor(0, new_y);
            }
            AnsiAction::CursorHorizontalAbs(x) => {
                let x = x.saturating_sub(1);
                self.state.move_cursor(x, self.state.cursor_y);
            }
            AnsiAction::CursorPosition { row, col } => {
                self.state.set_cursor(col, row);
            }
            AnsiAction::SaveCursor => {
                self.saved.x = self.state.cursor_x;
                self.saved.y = self.state.cursor_y;
                self.saved.attrs = self.state.attrs;
                self.saved.fg_color = self.state.fg_color;
                self.saved.bg_color = self.state.bg_color;
            }
            AnsiAction::RestoreCursor => {
                self.state.cursor_x = self.saved.x;
                self.state.cursor_y = self.saved.y;
                self.state.attrs = self.saved.attrs;
                self.state.fg_color = self.saved.fg_color;
                self.state.bg_color = self.saved.bg_color;
            }
            AnsiAction::EraseDisplay(mode) => {
                self.state.clear(mode);
            }
            AnsiAction::EraseLine(mode) => {
                self.state.clear_line(mode);
            }
            AnsiAction::InsertLines(n) => {
                self.state.insert_lines(n);
            }
            AnsiAction::DeleteLines(n) => {
                self.state.delete_lines(n);
            }
            AnsiAction::DeleteChars(_n) => {
                // TODO: 实现删除字符
            }
            AnsiAction::EraseChars(n) => {
                self.state.erase_chars(n);
            }
            AnsiAction::SetScrollRegion { top, bottom } => {
                self.state.set_scroll_region(top, bottom);
            }
            AnsiAction::SetGraphicsRgr(params) => {
                self.process_sgr(&params);
            }
            AnsiAction::ResetGraphics => {
                self.state.reset_attrs();
            }
            AnsiAction::SetMode(_set, _params) => {
                // TODO: 实现模式设置
            }
            AnsiAction::DeviceAttributes => {
                // TODO: 响应设备属性查询
            }
            AnsiAction::QueryCursorPosition => {
                // TODO: 响应光标位置查询
            }
            AnsiAction::SetWindowTitle(_title) => {
                // TODO: 保存窗口标题
            }
            AnsiAction::Ignore => {}
        }
    }

    /// 处理 SGR (Select Graphic Rendition) 参数
    fn process_sgr(&mut self, params: &[u16]) {
        let mut i = 0;
        while i < params.len() {
            let param = params[i];

            match param {
                0 => {
                    // 重置所有属性
                    self.state.reset_attrs();
                }
                1 => self.state.attrs.set(CellAttrs::BOLD, true),
                2 => self.state.attrs.set(CellAttrs::FAINT, true),
                3 => self.state.attrs.set(CellAttrs::ITALIC, true),
                4 => self.state.attrs.set(CellAttrs::UNDERLINE, true),
                5 | 6 => self.state.attrs.set(CellAttrs::BLINK, true),
                7 => self.state.attrs.set(CellAttrs::REVERSE, true),
                8 => self.state.attrs.set(CellAttrs::HIDDEN, true),
                9 => self.state.attrs.set(CellAttrs::STRIKETHROUGH, true),
                21 => self.state.attrs.set(CellAttrs::BOLD, false),
                22 => {
                    self.state.attrs.set(CellAttrs::BOLD, false);
                    self.state.attrs.set(CellAttrs::FAINT, false);
                }
                23 => self.state.attrs.set(CellAttrs::ITALIC, false),
                24 => self.state.attrs.set(CellAttrs::UNDERLINE, false),
                25 => self.state.attrs.set(CellAttrs::BLINK, false),
                27 => self.state.attrs.set(CellAttrs::REVERSE, false),
                28 => self.state.attrs.set(CellAttrs::HIDDEN, false),
                29 => self.state.attrs.set(CellAttrs::STRIKETHROUGH, false),

                // 前景色 (30-37, 39)
                30 => self.state.fg_color = Color::Indexed(0),
                31 => self.state.fg_color = Color::Indexed(1),
                32 => self.state.fg_color = Color::Indexed(2),
                33 => self.state.fg_color = Color::Indexed(3),
                34 => self.state.fg_color = Color::Indexed(4),
                35 => self.state.fg_color = Color::Indexed(5),
                36 => self.state.fg_color = Color::Indexed(6),
                37 => self.state.fg_color = Color::Indexed(7),
                39 => self.state.fg_color = Color::default_fg(),

                // 高亮前景色 (90-97)
                90 => self.state.fg_color = Color::Indexed(8),
                91 => self.state.fg_color = Color::Indexed(9),
                92 => self.state.fg_color = Color::Indexed(10),
                93 => self.state.fg_color = Color::Indexed(11),
                94 => self.state.fg_color = Color::Indexed(12),
                95 => self.state.fg_color = Color::Indexed(13),
                96 => self.state.fg_color = Color::Indexed(14),
                97 => self.state.fg_color = Color::Indexed(15),

                // 背景色 (40-47, 49)
                40 => self.state.bg_color = Color::Indexed(0),
                41 => self.state.bg_color = Color::Indexed(1),
                42 => self.state.bg_color = Color::Indexed(2),
                43 => self.state.bg_color = Color::Indexed(3),
                44 => self.state.bg_color = Color::Indexed(4),
                45 => self.state.bg_color = Color::Indexed(5),
                46 => self.state.bg_color = Color::Indexed(6),
                47 => self.state.bg_color = Color::Indexed(7),
                49 => self.state.bg_color = Color::default_bg(),

                // 高亮背景色 (100-107)
                100 => self.state.bg_color = Color::Indexed(8),
                101 => self.state.bg_color = Color::Indexed(9),
                102 => self.state.bg_color = Color::Indexed(10),
                103 => self.state.bg_color = Color::Indexed(11),
                104 => self.state.bg_color = Color::Indexed(12),
                105 => self.state.bg_color = Color::Indexed(13),
                106 => self.state.bg_color = Color::Indexed(14),
                107 => self.state.bg_color = Color::Indexed(15),

                // 自定义颜色
                38 => {
                    // 前景色自定义
                    if i + 2 < params.len() {
                        match params[i + 1] {
                            5 => {
                                // 256 色
                                if let Some(&idx) = params.get(i + 2) {
                                    self.state.fg_color = Color::Indexed(idx as u8);
                                }
                                i += 2;
                            }
                            2 => {
                                // RGB
                                if i + 4 < params.len() {
                                    let r = params[i + 2] as u8;
                                    let g = params[i + 3] as u8;
                                    let b = params[i + 4] as u8;
                                    self.state.fg_color = Color::Rgb(r, g, b);
                                    i += 4;
                                }
                            }
                            _ => {}
                        }
                    }
                }
                48 => {
                    // 背景色自定义
                    if i + 2 < params.len() {
                        match params[i + 1] {
                            5 => {
                                // 256 色
                                if let Some(&idx) = params.get(i + 2) {
                                    self.state.bg_color = Color::Indexed(idx as u8);
                                }
                                i += 2;
                            }
                            2 => {
                                // RGB
                                if i + 4 < params.len() {
                                    let r = params[i + 2] as u8;
                                    let g = params[i + 3] as u8;
                                    let b = params[i + 4] as u8;
                                    self.state.bg_color = Color::Rgb(r, g, b);
                                    i += 4;
                                }
                            }
                            _ => {}
                        }
                    }
                }
                _ => {}
            }

            i += 1;
        }
    }

    /// 调整大小
    pub fn resize(&mut self, cols: u16, rows: u16) {
        self.state.resize(cols, rows);
    }

    /// 获取状态
    pub fn state(&self) -> &TerminalState {
        &self.state
    }

    /// 获取可变状态
    pub fn state_mut(&mut self) -> &mut TerminalState {
        &mut self.state
    }

    /// 获取光标位置
    pub fn cursor_position(&self) -> (u16, u16) {
        (self.state.cursor_x, self.state.cursor_y)
    }

    /// 获取单元格
    pub fn get_cell(&self, x: u16, y: u16) -> Option<&Cell> {
        self.state
            .cells
            .get(y as usize)
            .and_then(|row| row.get(x as usize))
    }

    /// 获取响应数据（用于设备查询等）
    pub fn take_response(&mut self) -> Vec<u8> {
        // TODO: 收集响应数据
        Vec::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_basic_output() {
        let mut parser = Vt100Parser::new(80, 24);
        let data = b"Hello, World!";
        parser.process(data);

        assert_eq!(parser.get_cell(0, 0).unwrap().char, 'H');
        assert_eq!(parser.get_cell(7, 0).unwrap().char, 'W');
    }

    #[test]
    fn test_newline() {
        let mut parser = Vt100Parser::new(80, 24);
        // 使用 \r\n 来实现完整的换行（回车+换行）
        let data = b"Hello\r\nWorld";
        parser.process(data);

        assert_eq!(parser.get_cell(0, 0).unwrap().char, 'H');
        // "World" 在第二行开头
        assert_eq!(parser.get_cell(0, 1).unwrap().char, 'W');
    }

    #[test]
    fn test_newline_only() {
        let mut parser = Vt100Parser::new(80, 24);
        // 单独的 \n 只换行不回车
        let data = b"Hello\nWorld";
        parser.process(data);

        assert_eq!(parser.get_cell(0, 0).unwrap().char, 'H');
        // "World" 在第二行的第 5 列（因为 \n 没有重置列位置）
        assert_eq!(parser.get_cell(5, 1).unwrap().char, 'W');
    }

    #[test]
    fn test_carriage_return() {
        let mut parser = Vt100Parser::new(80, 24);
        let data = b"Hello\rWorld";
        parser.process(data);

        // \r 将光标移回行首，"World" 覆盖 "Hello"
        assert_eq!(parser.get_cell(0, 0).unwrap().char, 'W');
        assert_eq!(parser.get_cell(1, 0).unwrap().char, 'o');
        assert_eq!(parser.get_cell(4, 0).unwrap().char, 'd');
    }

    #[test]
    fn test_csi_cursor_move() {
        let mut parser = Vt100Parser::new(80, 24);
        let data = b"\x1B[5;10HTest";
        parser.process(data);

        // CSI 5;10 H 应该移动光标到 (9, 4) (0-based)
        assert_eq!(parser.get_cell(9, 4).unwrap().char, 'T');
    }

    #[test]
    fn test_sgr_colors() {
        let mut parser = Vt100Parser::new(80, 24);
        let data = b"\x1B[31;42mRed\x1B[0m";
        parser.process(data);

        let cell = parser.get_cell(0, 0).unwrap();
        assert_eq!(cell.char, 'R');
        assert_eq!(cell.fg_color, Color::Indexed(1)); // 红色
        assert_eq!(cell.bg_color, Color::Indexed(2)); // 绿色
    }

    #[test]
    fn test_clear_screen() {
        let mut parser = Vt100Parser::new(80, 24);
        parser.process(b"Hello");
        parser.process(b"\x1B[2J");
        parser.process(b"World");

        assert_eq!(parser.get_cell(0, 0).unwrap().char, 'W');
    }

    #[test]
    fn test_256_color() {
        let mut parser = Vt100Parser::new(80, 24);
        let data = b"\x1B[38;5;123mTest\x1B[0m";
        parser.process(data);

        let cell = parser.get_cell(0, 0).unwrap();
        assert_eq!(cell.fg_color, Color::Indexed(123));
    }

    #[test]
    fn test_rgb_color() {
        let mut parser = Vt100Parser::new(80, 24);
        let data = b"\x1B[38;2;255;128;0mTest\x1B[0m";
        parser.process(data);

        let cell = parser.get_cell(0, 0).unwrap();
        assert_eq!(cell.fg_color, Color::Rgb(255, 128, 0));
    }

    #[test]
    fn test_indexed_color_conversion() {
        // 测试标准颜色
        let (r, g, b) = indexed_color_to_rgb(0); // 黑色
        assert_eq!((r, g, b), (0x00, 0x00, 0x00));

        let (r, g, b) = indexed_color_to_rgb(1); // 红色
        assert_eq!((r, g, b), (0x99, 0x3E, 0x3E));

        // 测试色立方
        let (r, g, b) = indexed_color_to_rgb(16);
        assert_eq!((r, g, b), (0x00, 0x00, 0x00));

        let (r, g, b) = indexed_color_to_rgb(17);
        assert_eq!((r, g, b), (0x00, 0x00, 0x5F));

        // 测试灰度
        let (r, g, b) = indexed_color_to_rgb(232);
        assert_eq!((r, g, b), (8, 8, 8));

        let (r, g, b) = indexed_color_to_rgb(255);
        assert_eq!((r, g, b), (238, 238, 238));
    }

    #[test]
    fn test_bold_attribute() {
        let mut parser = Vt100Parser::new(80, 24);
        let data = b"\x1B[1mTest\x1B[0m";
        parser.process(data);

        let cell = parser.get_cell(0, 0).unwrap();
        assert!(cell.attrs.is_bold());
    }

    #[test]
    fn test_underline_attribute() {
        let mut parser = Vt100Parser::new(80, 24);
        let data = b"\x1B[4mTest\x1B[0m";
        parser.process(data);

        let cell = parser.get_cell(0, 0).unwrap();
        assert!(cell.attrs.is_underline());
    }

    #[test]
    fn test_dirty_regions() {
        let mut parser = Vt100Parser::new(80, 24);
        let dirty = parser.process(b"Hello");

        // 应该有一个脏区域
        assert!(!dirty.is_empty());
        assert_eq!(dirty[0].x, 0);
        assert_eq!(dirty[0].y, 0);
        // 至少 5 个字符
        assert!(dirty[0].cols >= 5);
    }
}
