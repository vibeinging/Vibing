//
//  render.rs
//  Vibe Terminal Server
//
//  渲染相关功能 - 生成增量帧
//

use crate::pty::TerminalCell;
use crate::protocol::{CellData, Color as ProtocolColor, CellAttrs as ProtocolAttrs};

/// 渲染器 - 从终端状态生成增量帧
pub struct Renderer {
    last_seq: u64,
    last_cells: Vec<Vec<TerminalCell>>,
    last_cursor: (usize, usize),
}

impl Renderer {
    pub fn new(cols: usize, rows: usize) -> Self {
        Self {
            last_seq: 0,
            last_cells: vec![vec![TerminalCell::default(); cols]; rows],
            last_cursor: (0, 0),
        }
    }

    /// 生成增量帧
    pub fn render(
        &mut self,
        cells: &[Vec<TerminalCell>],
        cursor: (usize, usize),
    ) -> (u64, Vec<crate::protocol::DirtyRegion>, Option<crate::protocol::CursorFrame>) {
        self.last_seq += 1;
        let seq = self.last_seq;

        // 查找脏区域
        let dirty_regions = Self::find_dirty_regions(
            &self.last_cells,
            cells,
            &self.last_cursor,
            &cursor,
        );

        // 生成脏区域数据
        let regions: Vec<crate::protocol::DirtyRegion> = dirty_regions
            .iter()
            .map(|(x, y, w, h)| Self::make_dirty_region(cells, *x, *y, *w, *h))
            .collect();

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

        (seq, regions, cursor_frame)
    }

    /// 查找脏区域
    fn find_dirty_regions(
        old_cells: &[Vec<TerminalCell>],
        new_cells: &[Vec<TerminalCell>],
        _old_cursor: &(usize, usize),
        _new_cursor: &(usize, usize),
    ) -> Vec<(usize, usize, usize, usize)> {
        let mut regions = Vec::new();

        let rows = old_cells.len().min(new_cells.len());
        let cols = old_cells.get(0).map(|v| v.len()).unwrap_or(0);

        for y in 0..rows {
            for x in 0..cols {
                let old_cell = &old_cells[y][x];
                let new_cell = &new_cells[y][x];

                // 检查是否变化
                if old_cell.char != new_cell.char
                    || old_cell.fg_color != new_cell.fg_color
                    || old_cell.bg_color != new_cell.bg_color
                    || old_cell.attrs != new_cell.attrs
                {
                    // 找到变化的单元格，合并为区域
                    let (_x2, _y2, w, h) = Self::extend_dirty_region(new_cells, x, y);
                    regions.push((x, y, w, h));
                }
            }
        }

        regions
    }

    /// 扩展脏区域
    fn extend_dirty_region(
        cells: &[Vec<TerminalCell>],
        start_x: usize,
        start_y: usize,
    ) -> (usize, usize, usize, usize) {
        let max_x = cells.get(start_y).map(|v| v.len()).unwrap_or(0);
        let max_y = cells.len();

        let mut x2 = start_x;
        let mut y2 = start_y;

        // 向右扩展
        while x2 < max_x {
            // 检查右边单元格是否也变化
            // 这里简化：假设连续的单元格都会变化
            x2 += 1;
        }

        // 向下扩展（如果是整行变化）
        while y2 < max_y {
            // TODO: 更智能的行合并
            y2 += 1;
        }

        (start_x, start_y, x2 - start_x, y2 - start_y)
    }

    /// 创建脏区域数据
    fn make_dirty_region(
        cells: &[Vec<TerminalCell>],
        x: usize,
        y: usize,
        width: usize,
        height: usize,
    ) -> crate::protocol::DirtyRegion {
        // 收集区域内的所有单元格数据
        let mut region_cells = Vec::new();

        for row_y in y..(y + height).min(cells.len()) {
            for col_x in x..(x + width).min(cells.get(row_y).map(|v| v.len()).unwrap_or(0)) {
                let cell = &cells[row_y][col_x];
                region_cells.push(CellData {
                    char: cell.char.to_string(),
                    fg_color: convert_color(cell.fg_color),
                    bg_color: convert_color(cell.bg_color),
                    attrs: convert_attrs(cell.attrs),
                });
            }
        }

        crate::protocol::DirtyRegion {
            x: x as u16,
            y: y as u16,
            width: width as u16,
            height: height as u16,
            cells: region_cells,
        }
    }
}

/// 转换颜色从 pty 到 protocol
fn convert_color(rgb: (u8, u8, u8)) -> ProtocolColor {
    // 尝试匹配标准颜色，否则使用 RGB
    match rgb {
        (0x00, 0x00, 0x00) => ProtocolColor::Indexed(0),
        (0x99, 0x3E, 0x3E) => ProtocolColor::Indexed(1),
        (0x3E, 0x99, 0x3E) => ProtocolColor::Indexed(2),
        (0x99, 0x99, 0x3E) => ProtocolColor::Indexed(3),
        (0x3E, 0x3E, 0x99) => ProtocolColor::Indexed(4),
        (0x99, 0x3E, 0x99) => ProtocolColor::Indexed(5),
        (0x3E, 0x99, 0x99) => ProtocolColor::Indexed(6),
        (0x99, 0x99, 0x99) => ProtocolColor::Indexed(7),
        (0x3E, 0x3E, 0x3E) => ProtocolColor::Indexed(8),
        (0xFF, 0x67, 0x67) => ProtocolColor::Indexed(9),
        (0x67, 0xFF, 0x67) => ProtocolColor::Indexed(10),
        (0xFF, 0xFF, 0x67) => ProtocolColor::Indexed(11),
        (0x67, 0x67, 0xFF) => ProtocolColor::Indexed(12),
        (0xFF, 0x67, 0xFF) => ProtocolColor::Indexed(13),
        (0x67, 0xFF, 0xFF) => ProtocolColor::Indexed(14),
        (0xFF, 0xFF, 0xFF) => ProtocolColor::Indexed(15),
        (212, 212, 212) => ProtocolColor::Default,
        (28, 28, 28) => ProtocolColor::Default,
        _ => ProtocolColor::Rgb { r: rgb.0, g: rgb.1, b: rgb.2 },
    }
}

/// 转换属性从 pty 到 protocol
fn convert_attrs(attrs: u16) -> ProtocolAttrs {
    let mut protocol_attrs = ProtocolAttrs::empty();

    if attrs & 0x01 != 0 {
        protocol_attrs.insert(ProtocolAttrs::BOLD);
    }
    if attrs & 0x02 != 0 {
        protocol_attrs.insert(ProtocolAttrs::DIM);
    }
    if attrs & 0x04 != 0 {
        protocol_attrs.insert(ProtocolAttrs::ITALIC);
    }
    if attrs & 0x08 != 0 {
        protocol_attrs.insert(ProtocolAttrs::UNDERLINE);
    }
    if attrs & 0x10 != 0 {
        protocol_attrs.insert(ProtocolAttrs::BLINK);
    }
    if attrs & 0x20 != 0 {
        protocol_attrs.insert(ProtocolAttrs::REVERSE);
    }
    if attrs & 0x40 != 0 {
        protocol_attrs.insert(ProtocolAttrs::HIDDEN);
    }
    if attrs & 0x80 != 0 {
        protocol_attrs.insert(ProtocolAttrs::STRIKETHROUGH);
    }

    protocol_attrs
}
