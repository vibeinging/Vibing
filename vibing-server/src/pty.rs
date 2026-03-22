//
//  pty.rs
//  Vibe Terminal Server
//
//  PTY 会话管理
//

use anyhow::Result;
use portable_pty::{native_pty_system, Child, CommandBuilder, ExitStatus, MasterPty, PtySize, PtySystem};
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tracing::{debug, error, info, warn};

use crate::render::Renderer;

/// PTY 会话 ID
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PtySessionId(u64);

impl PtySessionId {
    pub fn new() -> Self {
        static COUNTER: AtomicU64 = AtomicU64::new(1);
        PtySessionId(COUNTER.fetch_add(1, Ordering::SeqCst))
    }

    pub fn parse(s: &str) -> Result<Self, String> {
        s.parse::<u64>()
            .map(PtySessionId)
            .map_err(|_| "Invalid session ID".to_string())
    }

    pub fn as_u64(&self) -> u64 {
        self.0
    }

    pub fn as_string(&self) -> String {
        self.0.to_string()
    }
}

impl std::fmt::Display for PtySessionId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// PTY 配置
#[derive(Debug, Clone)]
pub struct PtyConfig {
    /// Shell 命令路径
    pub shell: String,
    /// 命令参数
    pub args: Vec<String>,
    /// 环境变量
    pub env: Vec<(String, String)>,
    /// 初始列数
    pub cols: u16,
    /// 初始行数
    pub rows: u16,
}

impl Default for PtyConfig {
    fn default() -> Self {
        Self {
            shell: "/bin/bash".to_string(),
            args: vec!["--login".to_string()],
            env: default_env_vars(),
            cols: 80,
            rows: 24,
        }
    }
}

/// 获取默认环境变量
fn default_env_vars() -> Vec<(String, String)> {
    let mut env = vec![
        ("TERM".to_string(), "xterm-256color".to_string()),
        ("COLORTERM".to_string(), "truecolor".to_string()),
    ];

    // 添加用户的环境变量（安全子集）
    for (key, value) in std::env::vars() {
        // 只传递安全的变量
        match key.as_str() {
            "PATH" | "HOME" | "USER" | "SHELL" | "LANG" | "LC_ALL"
            | "LC_CTYPE" | "DISPLAY" | "XDG_RUNTIME_DIR" => {
                env.push((key, value));
            }
            _ => {
                // 跳过其他变量
            }
        }
    }

    env
}

/// 终端单元格
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TerminalCell {
    pub char: char,
    pub fg_color: (u8, u8, u8),
    pub bg_color: (u8, u8, u8),
    pub attrs: u16,
}

impl Default for TerminalCell {
    fn default() -> Self {
        Self {
            char: ' ',
            fg_color: (212, 212, 212),
            bg_color: (28, 28, 28),
            attrs: 0,
        }
    }
}

/// 终端状态
#[derive(Clone)]
pub struct TerminalState {
    cols: usize,
    rows: usize,
    cells: Vec<Vec<TerminalCell>>,
    cursor_x: usize,
    cursor_y: usize,
}

impl TerminalState {
    pub fn new(cols: usize, rows: usize) -> Self {
        let cells = vec![vec![TerminalCell::default(); cols]; rows];
        Self {
            cols,
            rows,
            cells,
            cursor_x: 0,
            cursor_y: 0,
        }
    }

    pub fn resize(&mut self, cols: usize, rows: usize) {
        // 创建新的单元格网格，尽可能保留现有内容
        let mut new_cells = vec![vec![TerminalCell::default(); cols]; rows];

        for y in 0..self.rows.min(rows) {
            for x in 0..self.cols.min(cols) {
                new_cells[y][x] = self.cells[y][x];
            }
        }

        self.cols = cols;
        self.rows = rows;
        self.cells = new_cells;

        // 确保光标在范围内
        self.cursor_x = self.cursor_x.min(cols.saturating_sub(1));
        self.cursor_y = self.cursor_y.min(rows.saturating_sub(1));
    }

    pub fn write_bytes(&mut self, data: &[u8]) {
        // 简单的文本输出处理
        // TODO: 使用完整的 VT100 解析器
        let text = String::from_utf8_lossy(data);
        for c in text.chars() {
            self.process_char(c);
        }
    }

    fn process_char(&mut self, c: char) {
        match c {
            '\n' => {
                self.cursor_y += 1;
                if self.cursor_y >= self.rows {
                    // 滚动
                    self.cells.remove(0);
                    self.cells.push(vec![TerminalCell::default(); self.cols]);
                    self.cursor_y = self.rows - 1;
                }
                self.cursor_x = 0;
            }
            '\r' => {
                self.cursor_x = 0;
            }
            '\t' => {
                let tab_stop = (self.cursor_x / 8 + 1) * 8;
                self.cursor_x = tab_stop.min(self.cols);
            }
            '\x08' => {
                // 退格
                self.cursor_x = self.cursor_x.saturating_sub(1);
            }
            c if c.is_ascii_control() => {
                // 其他控制字符忽略
            }
            c => {
                if self.cursor_y < self.rows && self.cursor_x < self.cols {
                    self.cells[self.cursor_y][self.cursor_x].char = c;
                    self.cursor_x += 1;
                    if self.cursor_x >= self.cols {
                        self.cursor_x = 0;
                        self.cursor_y += 1;
                        if self.cursor_y >= self.rows {
                            self.cells.remove(0);
                            self.cells.push(vec![TerminalCell::default(); self.cols]);
                            self.cursor_y = self.rows - 1;
                        }
                    }
                }
            }
        }
    }

    pub fn cells(&self) -> &Vec<Vec<TerminalCell>> {
        &self.cells
    }

    pub fn cursor_position(&self) -> (usize, usize) {
        (self.cursor_x, self.cursor_y)
    }

    pub fn cols(&self) -> usize {
        self.cols
    }

    pub fn rows(&self) -> usize {
        self.rows
    }
}

/// PTY 会话输出事件
#[derive(Debug, Clone)]
pub enum PtyEvent {
    Output(Vec<u8>),
    Exited(ExitStatus),
}

/// PTY 会话
pub struct PtySession {
    id: PtySessionId,
    writer: Option<Arc<StdMutex<Box<dyn std::io::Write + Send>>>>,
    child: Option<Box<dyn Child + Send + Sync>>,
    reader_task: Option<JoinHandle<()>>,
    _event_tx: mpsc::UnboundedSender<PtyEvent>,
    cols: u16,
    rows: u16,
    state: Arc<tokio::sync::Mutex<TerminalState>>,
    renderer: Arc<tokio::sync::Mutex<Renderer>>,
}

impl PtySession {
    /// 创建新的 PTY 会话
    pub fn new(config: &PtyConfig) -> Result<Self> {
        let id = PtySessionId::new();
        let pty_system = native_pty_system();

        // 构建 PTY 大小
        let size = PtySize {
            rows: config.rows,
            cols: config.cols,
            pixel_width: 0,
            pixel_height: 0,
        };

        // 打开 PTY
        let pty_pair = pty_system.openpty(size)?;

        // 构建命令
        let mut cmd_builder = CommandBuilder::new(&config.shell);
        for arg in &config.args {
            cmd_builder.arg(arg);
        }
        for (key, value) in &config.env {
            cmd_builder.env(key, value);
        }

        // 启动子进程
        let child = pty_pair.slave.spawn_command(cmd_builder)?;

        // 获取 writer (take_writer 会消耗 master，所以我们需要先 clone reader)
        let reader = pty_pair.master.try_clone_reader()?;
        let writer = Some(Arc::new(StdMutex::new(pty_pair.master.take_writer()?)));

        // 创建状态和渲染器
        let state = Arc::new(tokio::sync::Mutex::new(TerminalState::new(
            config.cols as usize,
            config.rows as usize,
        )));
        let renderer = Arc::new(tokio::sync::Mutex::new(Renderer::new(
            config.cols as usize,
            config.rows as usize,
        )));

        // 创建事件通道
        let (event_tx, _event_rx) = mpsc::unbounded_channel();

        // 启动读取任务
        let state_clone = state.clone();
        let event_tx_clone = event_tx.clone();
        let reader_task = tokio::spawn(async move {
            let mut reader = reader;
            let mut buffer = vec![0u8; 8192];

            loop {
                match reader.read(&mut buffer) {
                    Ok(0) => {
                        debug!("PTY reader EOF");
                        break;
                    }
                    Ok(n) => {
                        let data = buffer[..n].to_vec();

                        // 更新终端状态
                        {
                            let mut state = state_clone.lock().await;
                            state.write_bytes(&data);
                        }

                        // 发送输出事件
                        if event_tx_clone.send(PtyEvent::Output(data)).is_err() {
                            warn!("Failed to send PTY output event");
                            break;
                        }
                    }
                    Err(e) => {
                        error!("PTY read error: {}", e);
                        break;
                    }
                }
            }
        });

        info!(
            "Created PTY session {}: {} {}",
            id, config.shell,
            config.args.join(" ")
        );

        Ok(Self {
            id,
            writer,
            child: Some(child),
            reader_task: Some(reader_task),
            _event_tx: event_tx,
            cols: config.cols,
            rows: config.rows,
            state,
            renderer,
        })
    }

    /// 获取会话 ID
    pub fn id(&self) -> PtySessionId {
        self.id
    }

    /// 写入数据到 PTY
    pub fn write(&self, data: &[u8]) -> Result<()> {
        if let Some(writer) = &self.writer {
            let mut writer = writer.lock().map_err(|_| anyhow::anyhow!("Writer lock poisoned"))?;
            writer.write_all(data)?;
            writer.flush()?;
            Ok(())
        } else {
            Err(anyhow::anyhow!("PTY writer is closed"))
        }
    }

    /// 调整终端大小
    pub async fn resize(&mut self, cols: u16, rows: u16) -> Result<()> {
        // 更新本地状态
        self.cols = cols;
        self.rows = rows;

        // 更新终端状态
        {
            let mut state = self.state.lock().await;
            state.resize(cols as usize, rows as usize);
        }

        info!("Resized PTY session {} to {}x{}", self.id, cols, rows);
        Ok(())
    }

    /// 获取当前终端状态
    pub async fn state_snapshot(&self) -> (Vec<Vec<TerminalCell>>, (usize, usize)) {
        let state = self.state.lock().await;
        (state.cells().clone(), state.cursor_position())
    }

    /// 获取状态引用
    pub fn state(&self) -> &Arc<tokio::sync::Mutex<TerminalState>> {
        &self.state
    }

    /// 获取渲染器
    pub fn renderer(&self) -> &Arc<tokio::sync::Mutex<Renderer>> {
        &self.renderer
    }

    /// 获取终端大小
    pub fn size(&self) -> (u16, u16) {
        (self.cols, self.rows)
    }

    /// 检查会话是否存活
    pub fn is_alive(&self) -> bool {
        self.reader_task.is_some() && self.writer.is_some()
    }

    /// 关闭会话
    pub async fn close(mut self) -> Result<ExitStatus> {
        info!("Closing PTY session {}", self.id);

        // 中止读取任务
        if let Some(reader_task) = self.reader_task.take() {
            reader_task.abort();
            let _ = reader_task.await;
        }

        // 关闭 writer (发送 EOF)
        drop(self.writer.take());

        // 杀死子进程
        if let Some(mut child) = self.child.take() {
            child.kill()?;
            let status = child.wait()?;
            info!("PTY session {} exited with {:?}", self.id, status);
            Ok(status)
        } else {
            Ok(ExitStatus::with_exit_code(0))
        }
    }

    /// 尝试获取子进程退出状态（非阻塞）
    pub fn try_wait(&mut self) -> Option<Result<ExitStatus>> {
        if let Some(child) = &mut self.child {
            match child.try_wait() {
                Ok(Some(status)) => Some(Ok(status)),
                Ok(None) => None,
                Err(e) => Some(Err(e.into())),
            }
        } else {
            Some(Ok(ExitStatus::with_exit_code(0)))
        }
    }
}

impl Drop for PtySession {
    fn drop(&mut self) {
        info!("Dropping PTY session {}", self.id);

        // 中止读取任务
        if let Some(reader_task) = self.reader_task.take() {
            reader_task.abort();
        }

        // 关闭 writer (发送 EOF)
        drop(self.writer.take());

        // 杀死子进程
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
        }
    }
}

/// PTY 会话管理器
pub struct PtySessionManager {
    sessions: dashmap::DashMap<PtySessionId, Arc<tokio::sync::Mutex<PtySession>>>,
}

impl Default for PtySessionManager {
    fn default() -> Self {
        Self::new()
    }
}

impl PtySessionManager {
    pub fn new() -> Self {
        Self {
            sessions: dashmap::DashMap::new(),
        }
    }

    /// 创建新会话
    pub fn create_session(&self, config: &PtyConfig) -> Result<PtySessionId> {
        let session = PtySession::new(config)?;
        let id = session.id();
        self.sessions.insert(id, Arc::new(tokio::sync::Mutex::new(session)));
        Ok(id)
    }

    /// 获取会话
    pub fn get_session(&self, id: PtySessionId) -> Option<Arc<tokio::sync::Mutex<PtySession>>> {
        self.sessions.get(&id).map(|entry| entry.value().clone())
    }

    /// 列出所有会话
    pub fn list_sessions(&self) -> Vec<PtySessionId> {
        self.sessions.iter().map(|entry| *entry.key()).collect()
    }

    /// 关闭会话
    pub async fn close_session(&self, id: PtySessionId) -> Result<()> {
        if let Some((_id, session)) = self.sessions.remove(&id) {
            let session = session.lock().await;
            // 由于 close 需要 self，这里让 Drop 处理
            drop(session);
        }
        Ok(())
    }

    /// 清理已结束的会话
    pub async fn cleanup_dead_sessions(&self) {
        let mut dead_sessions = Vec::new();

        for entry in self.sessions.iter() {
            let id = *entry.key();
            let session = entry.value().clone();
            let session = session.lock().await;
            // 检查是否存活
            if !session.is_alive() {
                dead_sessions.push(id);
            }
        }

        for id in dead_sessions {
            info!("Cleaning up dead session {}", id);
            let _ = self.close_session(id).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_id() {
        let id1 = PtySessionId::new();
        let id2 = PtySessionId::new();
        assert!(id1.as_u64() < id2.as_u64());
    }

    #[test]
    fn test_default_config() {
        let config = PtyConfig::default();
        assert_eq!(config.shell, "/bin/bash");
        assert_eq!(config.cols, 80);
        assert_eq!(config.rows, 24);
    }

    #[test]
    fn test_terminal_state() {
        let mut state = TerminalState::new(10, 5);
        assert_eq!(state.cols(), 10);
        assert_eq!(state.rows(), 5);

        state.write_bytes(b"Hello");
        assert_eq!(state.cells()[0][0].char, 'H');
        assert_eq!(state.cells()[0][4].char, 'o');

        state.write_bytes(b"\nWorld");
        assert_eq!(state.cells()[1][0].char, 'W');
    }
}
