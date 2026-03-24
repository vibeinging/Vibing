//
//  render.rs
//  Vibe Terminal Server
//
//  渲染器 - 从终端状态生成增量帧
//

use crate::pty::TerminalCell;
use crate::protocol::{CellData, Color as ProtocolColor, CellAttrs as ProtocolAttrs};

/// 渲染器 - 对比前后状态生成增量 ScreenFrame
pub struct Renderer {
    last_seq: u64,
    last_cells: Vec<Vec<TerminalCell>>,
    last_cursor: (usize, usize),
    cols: usize,
    rows: usize,
}

impl Renderer {
    pub fn new(cols: usize, rows: usize) -> Self {
        Self {
            last_seq: 0,
            last_cells: vec![vec![TerminalCell::default(); cols]; rows],
            last_cursor: (0, 0),
            cols,
            rows,
        }
    }

    /// 调整渲染器大小
    pub fn resize(&mut self, cols: usize, rows: usize) {
        self.cols = cols;
        self.rows = rows;
        self.last_cells = vec![vec![TerminalCell::default(); cols]; rows];
        self.last_seq += 1;
    }

    /// 生成增量帧
    /// 返回 (序列号, 脏区域列表, 光标帧)
    pub fn render(
        &mut self,
        cells: &[Vec<TerminalCell>],
        cursor: (usize, usize),
    ) -> (u64, Vec<crate::protocol::DirtyRegion>, Option<crate::protocol::CursorFrame>) {
        self.last_seq += 1;
        let seq = self.last_seq;

        // 按行检测变化，合并连续变化的单元格为行级脏区域
        let dirty_regions = self.find_dirty_rows(cells);

        // 光标帧
        let cursor_frame = if cursor != self.last_cursor {
            Some(crate::protocol::CursorFrame {
                x: cursor.0 as u16,
                y: cursor.1 as u16,
                visible: true,
                style: crate::protocol::CursorStyle::Block,
            })
        } else {
            None
        };

        // 更新缓存
        self.last_cells = cells.to_vec();
        self.last_cursor = cursor;

        (seq, dirty_regions, cursor_frame)
    }

    /// 生成全屏帧（首次连接或 resize 后使用）
    pub fn render_full(
        &mut self,
        cells: &[Vec<TerminalCell>],
        cursor: (usize, usize),
        cols: u16,
        rows: u16,
    ) -> (u64, Vec<crate::protocol::DirtyRegion>, Option<crate::protocol::CursorFrame>) {
        self.last_seq += 1;
        let seq = self.last_seq;

        // 生成全屏脏区域
        let mut region_cells = Vec::with_capacity(cols as usize * rows as usize);
        for row in cells.iter().take(rows as usize) {
            for cell in row.iter().take(cols as usize) {
                region_cells.push(cell_to_protocol(cell));
            }
        }

        let dirty_regions = vec![crate::protocol::DirtyRegion {
            x: 0,
            y: 0,
            width: cols,
            height: rows,
            cells: region_cells,
        }];

        let cursor_frame = Some(crate::protocol::CursorFrame {
            x: cursor.0 as u16,
            y: cursor.1 as u16,
            visible: true,
            style: crate::protocol::CursorStyle::Block,
        });

        self.last_cells = cells.to_vec();
        self.last_cursor = cursor;

        (seq, dirty_regions, cursor_frame)
    }

    /// 按行检测脏区域，合并同一行连续变化的单元格
    fn find_dirty_rows(
        &self,
        new_cells: &[Vec<TerminalCell>],
    ) -> Vec<crate::protocol::DirtyRegion> {
        let mut regions = Vec::new();

        let rows = self.last_cells.len().min(new_cells.len());

        for y in 0..rows {
            let old_row = &self.last_cells[y];
            let new_row = &new_cells[y];
            let cols = old_row.len().min(new_row.len());

            // 找到这行中第一个和最后一个变化的列
            let mut first_dirty: Option<usize> = None;
            let mut last_dirty: usize = 0;

            for x in 0..cols {
                if old_row[x] != new_row[x] {
                    if first_dirty.is_none() {
                        first_dirty = Some(x);
                    }
                    last_dirty = x;
                }
            }

            if let Some(start_x) = first_dirty {
                let width = last_dirty - start_x + 1;

                // 收集变化区域的单元格数据
                let mut region_cells = Vec::with_capacity(width);
                for x in start_x..=last_dirty {
                    region_cells.push(cell_to_protocol(&new_row[x]));
                }

                regions.push(crate::protocol::DirtyRegion {
                    x: start_x as u16,
                    y: y as u16,
                    width: width as u16,
                    height: 1,
                    cells: region_cells,
                });
            }
        }

        // 合并相邻行的脏区域以减少帧数
        merge_adjacent_regions(regions)
    }
}

/// 合并相邻行的脏区域
fn merge_adjacent_regions(regions: Vec<crate::protocol::DirtyRegion>) -> Vec<crate::protocol::DirtyRegion> {
    if regions.len() <= 1 {
        return regions;
    }

    let mut merged: Vec<crate::protocol::DirtyRegion> = Vec::new();

    for region in regions {
        let should_merge = if let Some(last) = merged.last() {
            // 如果上一个区域和当前区域相邻（y 连续）且 x/width 相同，合并
            last.y + last.height == region.y && last.x == region.x && last.width == region.width
        } else {
            false
        };

        if should_merge {
            let last = merged.last_mut().unwrap();
            last.height += region.height;
            last.cells.extend(region.cells);
        } else {
            merged.push(region);
        }
    }

    merged
}

/// 将 TerminalCell 转换为协议的 CellData
fn cell_to_protocol(cell: &TerminalCell) -> CellData {
    CellData {
        char: cell.char.to_string(),
        fg_color: convert_color(cell.fg_color),
        bg_color: convert_color(cell.bg_color),
        attrs: convert_attrs(cell.attrs),
    }
}

/// 转换颜色
fn convert_color(rgb: (u8, u8, u8)) -> ProtocolColor {
    // 始终用 RGB，避免前景/背景默认色被混淆
    ProtocolColor::Rgb { r: rgb.0, g: rgb.1, b: rgb.2 }
}

/// 转换属性
fn convert_attrs(attrs: u16) -> ProtocolAttrs {
    let mut protocol_attrs = ProtocolAttrs::empty();

    if attrs & 0x01 != 0 { protocol_attrs.insert(ProtocolAttrs::BOLD); }
    if attrs & 0x02 != 0 { protocol_attrs.insert(ProtocolAttrs::DIM); }
    if attrs & 0x04 != 0 { protocol_attrs.insert(ProtocolAttrs::ITALIC); }
    if attrs & 0x08 != 0 { protocol_attrs.insert(ProtocolAttrs::UNDERLINE); }
    if attrs & 0x10 != 0 { protocol_attrs.insert(ProtocolAttrs::BLINK); }
    if attrs & 0x20 != 0 { protocol_attrs.insert(ProtocolAttrs::REVERSE); } // Note: REVERSE is 0x20 in vt100, 0x80 in protocol
    if attrs & 0x40 != 0 { protocol_attrs.insert(ProtocolAttrs::HIDDEN); }
    if attrs & 0x80 != 0 { protocol_attrs.insert(ProtocolAttrs::STRIKETHROUGH); }

    protocol_attrs
}

// ========== 状态追赶：终端状态 → ANSI 字节序列 ==========

/// 将终端当前状态转换为等效的 ANSI 字节序列。
/// 用于 RawStream 客户端订阅时"追赶"当前画面。
/// SwiftTerm 客户端 feed 这些字节后就能显示完整的当前终端状态。
pub fn state_to_ansi(
    cells: &[Vec<TerminalCell>],
    cursor: (usize, usize),
    cols: usize,
    rows: usize,
) -> Vec<u8> {
    let mut out = Vec::with_capacity(cols * rows * 20); // 预估大小

    // 先重置所有属性为默认，再清屏
    // 这样清屏填充的 cell 用 .defaultColor（而非显式黑色）
    out.extend_from_slice(b"\x1b[0m\x1b[2J\x1b[H");

    // 跟踪当前 SGR 状态以减少冗余转义序列
    // 使用 sentinel 值表示"默认色"，避免发送显式 RGB 黑色
    let default_fg: (u8, u8, u8) = (229, 229, 229);
    let default_bg: (u8, u8, u8) = (0, 0, 0);
    let mut cur_fg: (u8, u8, u8) = default_fg;
    let mut cur_bg: (u8, u8, u8) = default_bg;
    let mut cur_attrs: u16 = 0;

    for y in 0..rows.min(cells.len()) {
        // 定位到行首
        if y > 0 {
            // CUP: ESC[row;colH (1-based)
            out.extend_from_slice(format!("\x1b[{};1H", y + 1).as_bytes());
        }

        let row = &cells[y];
        for x in 0..cols.min(row.len()) {
            let cell = &row[x];

            // 检查属性是否变化
            let need_sgr = cell.fg_color != cur_fg || cell.bg_color != cur_bg || cell.attrs != cur_attrs;

            if need_sgr {
                // 重置然后设置新属性
                let mut sgr_parts: Vec<u8> = Vec::new();
                sgr_parts.push(0); // reset

                // 属性
                if cell.attrs & 0x01 != 0 { sgr_parts.push(1); } // bold
                if cell.attrs & 0x02 != 0 { sgr_parts.push(2); } // dim
                if cell.attrs & 0x04 != 0 { sgr_parts.push(3); } // italic
                if cell.attrs & 0x08 != 0 { sgr_parts.push(4); } // underline
                if cell.attrs & 0x10 != 0 { sgr_parts.push(5); } // blink
                if cell.attrs & 0x20 != 0 { sgr_parts.push(7); } // reverse
                if cell.attrs & 0x40 != 0 { sgr_parts.push(8); } // hidden
                if cell.attrs & 0x80 != 0 { sgr_parts.push(9); } // strikethrough

                // SGR 序列
                let sgr_str: String = sgr_parts.iter().map(|p| p.to_string()).collect::<Vec<_>>().join(";");
                out.extend_from_slice(format!("\x1b[{}m", sgr_str).as_bytes());

                // 前景色
                let (r, g, b) = cell.fg_color;
                if (r, g, b) == default_fg {
                    out.extend_from_slice(b"\x1b[39m"); // 默认前景
                } else {
                    out.extend_from_slice(format!("\x1b[38;2;{};{};{}m", r, g, b).as_bytes());
                }

                // 背景色
                let (r, g, b) = cell.bg_color;
                if (r, g, b) == default_bg {
                    out.extend_from_slice(b"\x1b[49m"); // 默认背景（让客户端用自己的主题色）
                } else {
                    out.extend_from_slice(format!("\x1b[48;2;{};{};{}m", r, g, b).as_bytes());
                }

                cur_fg = cell.fg_color;
                cur_bg = cell.bg_color;
                cur_attrs = cell.attrs;
            }

            // 输出字符
            let ch = cell.char;
            if ch == '\0' || ch == ' ' {
                out.push(b' ');
            } else {
                let mut buf = [0u8; 4];
                let s = ch.encode_utf8(&mut buf);
                out.extend_from_slice(s.as_bytes());
            }
        }
    }

    // 重置 SGR
    out.extend_from_slice(b"\x1b[0m");

    // 恢复光标位置 (1-based)
    out.extend_from_slice(format!("\x1b[{};{}H", cursor.1 + 1, cursor.0 + 1).as_bytes());

    out
}
