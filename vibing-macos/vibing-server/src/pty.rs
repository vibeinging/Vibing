//
//  pty.rs
//  Vibe Terminal Server
//
//  PTY 会话管理 - 集成 VT100 解析器
//

use anyhow::Result;
use portable_pty::{native_pty_system, Child, CommandBuilder, ExitStatus, PtySize};
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tracing::{debug, error, info, warn};

use crate::vt100::{Vt100Parser, Cell as Vt100Cell};

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
    pub shell: String,
    pub args: Vec<String>,
    pub env: Vec<(String, String)>,
    pub cols: u16,
    pub rows: u16,
    pub cwd: Option<String>,
}

impl Default for PtyConfig {
    fn default() -> Self {
        let detected = detect_user_shell();
        Self {
            shell: detected.shell,
            args: detected.args,
            env: detect_env_vars(),
            cols: 80,
            rows: 24,
            cwd: detect_home_dir(),
        }
    }
}

/// 检测到的 shell 信息
struct DetectedShell {
    shell: String,
    args: Vec<String>,
}

/// 检测用户默认 shell
///
/// 优先级:
/// 1. macOS: dscl 查询用户数据库 (最准确，反映系统偏好设置中配置的 shell)
/// 2. $SHELL 环境变量
/// 3. /etc/passwd
/// 4. 回退到 /bin/zsh (macOS 默认)
fn detect_user_shell() -> DetectedShell {
    // 1. macOS: 通过 dscl 查询用户数据库（最准确，$SHELL 可能被父进程覆盖）
    #[cfg(target_os = "macos")]
    {
        if let Ok(output) = std::process::Command::new("dscl")
            .args([".", "-read", &format!("/Users/{}", whoami()), "UserShell"])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                if let Some(shell) = stdout.strip_prefix("UserShell: ") {
                    let shell = shell.trim().to_string();
                    if std::path::Path::new(&shell).exists() {
                        let args = login_args_for_shell(&shell);
                        info!("Detected user shell from dscl: {}", shell);
                        return DetectedShell { shell, args };
                    }
                }
            }
        }
    }

    // 2. 从 $SHELL 环境变量获取
    if let Ok(shell) = std::env::var("SHELL") {
        if !shell.is_empty() && std::path::Path::new(&shell).exists() {
            let args = login_args_for_shell(&shell);
            info!("Detected user shell from $SHELL: {}", shell);
            return DetectedShell { shell, args };
        }
    }

    // 3. 从 /etc/passwd 读取
    if let Ok(content) = std::fs::read_to_string("/etc/passwd") {
        let username = whoami();
        for line in content.lines() {
            if line.starts_with(&format!("{}:", username)) {
                if let Some(shell) = line.rsplit(':').next() {
                    let shell = shell.trim().to_string();
                    if !shell.is_empty() && std::path::Path::new(&shell).exists() {
                        let args = login_args_for_shell(&shell);
                        info!("Detected user shell from /etc/passwd: {}", shell);
                        return DetectedShell { shell, args };
                    }
                }
            }
        }
    }

    // 4. 回退到 /bin/zsh (macOS 默认) 或 /bin/bash
    let fallback = if std::path::Path::new("/bin/zsh").exists() {
        "/bin/zsh"
    } else {
        "/bin/bash"
    };
    info!("Using fallback shell: {}", fallback);
    DetectedShell {
        shell: fallback.to_string(),
        args: login_args_for_shell(fallback),
    }
}

/// 根据 shell 类型返回合适的登录参数
fn login_args_for_shell(shell: &str) -> Vec<String> {
    let shell_name = std::path::Path::new(shell)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("sh");

    match shell_name {
        "fish" => {
            // fish 使用 --login 而不是 -l
            vec!["--login".to_string()]
        }
        "zsh" | "bash" | "sh" | "dash" | "ksh" => {
            vec!["--login".to_string()]
        }
        "nu" | "nushell" => {
            // nushell 不使用 --login
            vec!["--login".to_string()]
        }
        _ => {
            vec!["--login".to_string()]
        }
    }
}

/// 获取当前用户名
fn whoami() -> String {
    std::env::var("USER")
        .or_else(|_| std::env::var("LOGNAME"))
        .unwrap_or_else(|_| {
            std::process::Command::new("whoami")
                .output()
                .ok()
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .map(|s| s.trim().to_string())
                .unwrap_or_else(|| "root".to_string())
        })
}

/// 检测用户 HOME 目录
fn detect_home_dir() -> Option<String> {
    std::env::var("HOME").ok().filter(|h| !h.is_empty())
}

/// 检测并构建环境变量
///
/// 策略：继承所有父进程的环境变量，然后覆盖/添加终端特定的变量。
/// 这样可以保留用户在 shell profile 中设置的所有自定义环境
/// （如 CARGO_HOME, GOPATH, NVM_DIR, CONDA 等）。
fn detect_env_vars() -> Vec<(String, String)> {
    let mut env: Vec<(String, String)> = Vec::new();

    // 继承所有环境变量（过滤掉一些不应该传递的）
    let skip_vars = [
        "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID",
        "ITERM_SESSION_ID", "ITERM_PROFILE",
        "WARP_IS_LOCAL_SHELL_SESSION", "WARP_USE_SSH_WRAPPER",
        "TERMINAL_EMULATOR",
        // 不传递旧终端的特定变量，让新 PTY 环境干净
        "_", "SHLVL", "OLDPWD",
    ];

    for (key, value) in std::env::vars() {
        if skip_vars.contains(&key.as_str()) {
            continue;
        }
        env.push((key, value));
    }

    // 覆盖终端特定变量
    set_or_replace(&mut env, "TERM", "xterm-256color");
    set_or_replace(&mut env, "COLORTERM", "truecolor");
    set_or_replace(&mut env, "TERM_PROGRAM", "Vibing");
    set_or_replace(&mut env, "TERM_PROGRAM_VERSION", env!("CARGO_PKG_VERSION"));

    // 确保 LANG 有值（避免 locale 问题）
    if !env.iter().any(|(k, _)| k == "LANG") {
        env.push(("LANG".to_string(), "en_US.UTF-8".to_string()));
    }

    // 增强 PATH：确保常见工具路径存在
    enhance_path(&mut env);

    env
}

/// 在 env vec 中设置或替换键值
fn set_or_replace(env: &mut Vec<(String, String)>, key: &str, value: &str) {
    if let Some(entry) = env.iter_mut().find(|(k, _)| k == key) {
        entry.1 = value.to_string();
    } else {
        env.push((key.to_string(), value.to_string()));
    }
}

/// 增强 PATH 变量，确保常见开发工具路径存在
fn enhance_path(env: &mut Vec<(String, String)>) {
    let home = std::env::var("HOME").unwrap_or_default();
    if home.is_empty() {
        return;
    }

    // 需要确保在 PATH 中的额外路径
    let extra_paths = [
        format!("{home}/.cargo/bin"),           // Rust
        format!("{home}/.local/bin"),            // pipx, user scripts
        format!("{home}/go/bin"),                // Go
        format!("{home}/.nvm/versions/node"),    // NVM (不精确，但 nvm 会在 shell init 处理)
        "/opt/homebrew/bin".to_string(),         // Homebrew (Apple Silicon)
        "/usr/local/bin".to_string(),            // Homebrew (Intel) / 系统工具
        "/usr/local/sbin".to_string(),
    ];

    if let Some(entry) = env.iter_mut().find(|(k, _)| k == "PATH") {
        let current = &entry.1;
        let mut parts: Vec<&str> = current.split(':').collect();
        for extra in &extra_paths {
            if std::path::Path::new(extra).exists() && !parts.contains(&extra.as_str()) {
                parts.push(extra);
            }
        }
        entry.1 = parts.join(":");
    }
}

/// 公开的环境检测信息（用于 API 响应）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShellInfo {
    pub shell: String,
    pub shell_name: String,
    pub home: String,
    pub user: String,
}

impl ShellInfo {
    pub fn detect() -> Self {
        let detected = detect_user_shell();
        let shell_name = std::path::Path::new(&detected.shell)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("sh")
            .to_string();
        Self {
            shell: detected.shell,
            shell_name,
            home: detect_home_dir().unwrap_or_default(),
            user: whoami(),
        }
    }
}

/// 一个可用的 shell
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AvailableShell {
    pub path: String,
    pub name: String,
    pub version: String,
    pub is_default: bool,
}

/// 扫描系统中所有可用的 shell
pub fn detect_available_shells() -> Vec<AvailableShell> {
    let default_shell = detect_user_shell().shell;
    let mut shells: Vec<AvailableShell> = Vec::new();
    let mut seen = std::collections::HashSet::new();

    // 1. 从 /etc/shells 读取系统注册的 shell
    if let Ok(content) = std::fs::read_to_string("/etc/shells") {
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if std::path::Path::new(line).exists() && seen.insert(line.to_string()) {
                let name = std::path::Path::new(line)
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("unknown")
                    .to_string();
                let version = get_shell_version(line);
                shells.push(AvailableShell {
                    path: line.to_string(),
                    name,
                    version,
                    is_default: line == default_shell,
                });
            }
        }
    }

    // 2. 额外扫描常见位置（可能不在 /etc/shells 中）
    let extra_paths = [
        "/usr/local/bin/fish",
        "/opt/homebrew/bin/fish",
        "/usr/local/bin/nu",
        "/opt/homebrew/bin/nu",
        "/usr/local/bin/elvish",
        "/opt/homebrew/bin/elvish",
        "/usr/local/bin/pwsh",
        "/opt/homebrew/bin/pwsh",
    ];

    for path in &extra_paths {
        if std::path::Path::new(path).exists() && seen.insert(path.to_string()) {
            let name = std::path::Path::new(path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("unknown")
                .to_string();
            let version = get_shell_version(path);
            shells.push(AvailableShell {
                path: path.to_string(),
                name,
                version,
                is_default: *path == default_shell,
            });
        }
    }

    // 排序：默认 shell 排第一，其余按名称排序
    shells.sort_by(|a, b| {
        b.is_default.cmp(&a.is_default)
            .then_with(|| a.name.cmp(&b.name))
    });

    shells
}

/// 获取 shell 版本号
fn get_shell_version(shell_path: &str) -> String {
    let name = std::path::Path::new(shell_path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("");

    let version_flag = match name {
        "fish" | "nu" | "elvish" | "pwsh" => "--version",
        _ => "--version",
    };

    std::process::Command::new(shell_path)
        .arg(version_flag)
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                String::from_utf8(o.stdout).ok()
            } else {
                String::from_utf8(o.stderr).ok()
            }
        })
        .map(|s| {
            // 提取版本号（取第一行，去掉 shell 名称前缀）
            let line = s.lines().next().unwrap_or("").trim().to_string();
            // 常见格式: "fish, version 3.7.0" / "zsh 5.9" / "GNU bash, version 5.2.26"
            line
        })
        .unwrap_or_default()
}

/// 终端单元格 - 用于渲染器和协议输出
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

impl TerminalCell {
    /// 从 vt100::Cell 转换
    pub fn from_vt100(cell: &Vt100Cell) -> Self {
        Self {
            char: cell.char,
            fg_color: cell.fg_color.to_rgb(),
            bg_color: cell.bg_color.to_rgb(),
            attrs: cell.attrs.flags,
        }
    }
}

/// PTY 事件
#[derive(Debug, Clone)]
pub enum PtyEvent {
    /// PTY 产生了输出数据
    Output(Vec<u8>),
    /// PTY 进程已退出
    Exited(ExitStatus),
}

/// PTY 会话
pub struct PtySession {
    id: PtySessionId,
    writer: Option<Arc<StdMutex<Box<dyn std::io::Write + Send>>>>,
    child: Option<Box<dyn Child + Send + Sync>>,
    reader_task: Option<JoinHandle<()>>,
    cols: u16,
    rows: u16,
    parser: Arc<tokio::sync::Mutex<Vt100Parser>>,
    /// PTY master handle（用于 OS 级 resize），用 Mutex 包装以满足 Sync
    pty_master: StdMutex<Box<dyn portable_pty::MasterPty + Send>>,
}

impl PtySession {
    /// 创建新的 PTY 会话，返回 (session, event_rx)
    pub fn new(config: &PtyConfig) -> Result<(Self, mpsc::UnboundedReceiver<PtyEvent>)> {
        let id = PtySessionId::new();
        let pty_system = native_pty_system();

        let size = PtySize {
            rows: config.rows,
            cols: config.cols,
            pixel_width: 0,
            pixel_height: 0,
        };

        let pty_pair = pty_system.openpty(size)?;

        let mut cmd_builder = CommandBuilder::new(&config.shell);
        for arg in &config.args {
            cmd_builder.arg(arg);
        }
        for (key, value) in &config.env {
            cmd_builder.env(key, value);
        }
        if let Some(cwd) = &config.cwd {
            cmd_builder.cwd(cwd);
        }

        let child = pty_pair.slave.spawn_command(cmd_builder)?;

        let reader = pty_pair.master.try_clone_reader()?;
        let writer = Some(Arc::new(StdMutex::new(pty_pair.master.take_writer()?)));
        let pty_master = pty_pair.master;

        let parser = Arc::new(tokio::sync::Mutex::new(Vt100Parser::new(
            config.cols,
            config.rows,
        )));

        let (event_tx, event_rx) = mpsc::unbounded_channel();

        // 启动 PTY 读取任务
        // 阶段1：spawn_blocking 做同步 IO 读取，通过 channel 发送原始数据
        // 阶段2：异步任务做 VT100 解析 + 发送事件
        let (raw_tx, mut raw_rx) = mpsc::unbounded_channel::<Vec<u8>>();

        // 阻塞线程：读取 PTY 输出
        let _blocking_reader = tokio::task::spawn_blocking(move || {
            info!("PTY blocking reader thread started");
            let mut reader = reader;
            let mut buffer = vec![0u8; 16384];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) => {
                        info!("PTY reader EOF");
                        break;
                    }
                    Ok(n) => {
                        debug!("PTY read {} bytes", n);
                        let data = buffer[..n].to_vec();
                        if raw_tx.send(data).is_err() {
                            warn!("PTY raw channel closed");
                            break;
                        }
                    }
                    Err(e) => {
                        error!("PTY read error: {}", e);
                        break;
                    }
                }
            }
            info!("PTY blocking reader thread exiting");
        });

        // 异步任务：VT100 解析 + 发送事件
        let parser_clone = parser.clone();
        let event_tx_clone = event_tx.clone();
        let reader_task = tokio::spawn(async move {
            while let Some(data) = raw_rx.recv().await {
                // VT100 解析
                {
                    let mut parser = parser_clone.lock().await;
                    parser.process(&data);
                }
                // 通知有新输出
                if event_tx_clone.send(PtyEvent::Output(data)).is_err() {
                    warn!("Failed to send PTY output event");
                    break;
                }
            }
        });

        info!(
            "Created PTY session {}: {} {}",
            id, config.shell,
            config.args.join(" ")
        );

        let session = Self {
            id,
            writer,
            child: Some(child),
            reader_task: Some(reader_task),
            cols: config.cols,
            rows: config.rows,
            parser,
            pty_master: StdMutex::new(pty_master),
        };

        Ok((session, event_rx))
    }

    pub fn id(&self) -> PtySessionId {
        self.id
    }

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

    pub async fn resize(&mut self, cols: u16, rows: u16) -> Result<()> {
        self.cols = cols;
        self.rows = rows;

        // OS 级 PTY resize（发送 SIGWINCH 给 shell）— 同步操作，不跨 await
        {
            let master = self.pty_master.lock().map_err(|_| anyhow::anyhow!("PTY master lock poisoned"))?;
            master.resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })?;
        } // guard 在这里 drop

        {
            let mut parser = self.parser.lock().await;
            parser.resize(cols, rows);
        }
        info!("Resized PTY session {} to {}x{}", self.id, cols, rows);
        Ok(())
    }

    /// 获取当前终端状态快照 (转换为 TerminalCell 格式)
    pub async fn state_snapshot(&self) -> (Vec<Vec<TerminalCell>>, (usize, usize)) {
        let parser = self.parser.lock().await;
        let state = parser.state();
        let (cx, cy) = (state.cursor_x as usize, state.cursor_y as usize);

        let cells: Vec<Vec<TerminalCell>> = state.cells.iter().map(|row| {
            row.iter().map(|cell| TerminalCell::from_vt100(cell)).collect()
        }).collect();

        (cells, (cx, cy))
    }

    /// 获取 VT100 解析器引用
    pub fn parser(&self) -> &Arc<tokio::sync::Mutex<Vt100Parser>> {
        &self.parser
    }

    pub fn size(&self) -> (u16, u16) {
        (self.cols, self.rows)
    }

    pub fn is_alive(&self) -> bool {
        self.reader_task.is_some() && self.writer.is_some()
    }

    pub async fn close(mut self) -> Result<ExitStatus> {
        info!("Closing PTY session {}", self.id);

        if let Some(reader_task) = self.reader_task.take() {
            reader_task.abort();
            let _ = reader_task.await;
        }

        drop(self.writer.take());

        if let Some(mut child) = self.child.take() {
            child.kill()?;
            let status = child.wait()?;
            info!("PTY session {} exited with {:?}", self.id, status);
            Ok(status)
        } else {
            Ok(ExitStatus::with_exit_code(0))
        }
    }

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
        if let Some(reader_task) = self.reader_task.take() {
            reader_task.abort();
        }
        drop(self.writer.take());
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

    pub fn create_session(&self, config: &PtyConfig) -> Result<(PtySessionId, mpsc::UnboundedReceiver<PtyEvent>)> {
        let (session, event_rx) = PtySession::new(config)?;
        let id = session.id();
        self.sessions.insert(id, Arc::new(tokio::sync::Mutex::new(session)));
        Ok((id, event_rx))
    }

    pub fn get_session(&self, id: PtySessionId) -> Option<Arc<tokio::sync::Mutex<PtySession>>> {
        self.sessions.get(&id).map(|entry| entry.value().clone())
    }

    pub fn list_sessions(&self) -> Vec<PtySessionId> {
        self.sessions.iter().map(|entry| *entry.key()).collect()
    }

    pub async fn close_session(&self, id: PtySessionId) -> Result<()> {
        if let Some((_id, session)) = self.sessions.remove(&id) {
            let session = session.lock().await;
            drop(session);
        }
        Ok(())
    }

    pub async fn cleanup_dead_sessions(&self) {
        let mut dead_sessions = Vec::new();

        for entry in self.sessions.iter() {
            let id = *entry.key();
            let session = entry.value().clone();
            let session = session.lock().await;
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
        // shell 应该是系统检测到的，至少不为空
        assert!(!config.shell.is_empty());
        assert!(std::path::Path::new(&config.shell).exists());
        assert_eq!(config.cols, 80);
        assert_eq!(config.rows, 24);
        // 环境变量应该包含 TERM
        assert!(config.env.iter().any(|(k, _)| k == "TERM"));
        assert!(config.env.iter().any(|(k, _)| k == "COLORTERM"));
    }

    #[test]
    fn test_shell_detection() {
        let info = ShellInfo::detect();
        assert!(!info.shell.is_empty());
        assert!(!info.shell_name.is_empty());
        assert!(!info.user.is_empty());
    }
}
