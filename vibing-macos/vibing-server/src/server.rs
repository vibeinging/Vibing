//
//  server.rs
//  Vibe Terminal Server
//
//  同步服务器核心实现
//

use anyhow::Result;
use dashmap::DashMap;
use futures_util::{SinkExt, StreamExt};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{broadcast, Mutex};
use tokio_tungstenite::{accept_async, tungstenite::Message, WebSocketStream};
use tracing::{debug, error, info, warn};

use crate::config::ServerConfig;
use crate::pty::{PtySession, PtySessionId, PtyConfig, PtyEvent};
use crate::protocol::{Frame, ScreenFrame, ProtocolMode, encode_frame};
use crate::relay_client::{RelayClient, RelayEvent, RelayRole};
use crate::render::Renderer;

// JSON 协议消息类型常量
const MSG_TYPE_CREATE_SESSION: &str = "create_session";
const MSG_TYPE_INPUT: &str = "input";
const MSG_TYPE_SUBSCRIBE: &str = "subscribe";
const MSG_TYPE_NEGOTIATE: &str = "negotiate";
const MSG_TYPE_LIST_SESSIONS: &str = "list_sessions";
const MSG_TYPE_START_RELAY: &str = "start_relay";
const MSG_TYPE_STOP_RELAY: &str = "stop_relay";
const MSG_TYPE_LIST_DIR: &str = "list_dir";

/// 会话数据（存储 session + renderer + 原始字节缓冲）
pub(crate) struct SessionData {
    pub(crate) session: Arc<tokio::sync::Mutex<PtySession>>,
    pub(crate) renderer: Arc<tokio::sync::Mutex<Renderer>>,
    /// 原始 PTY 输出缓冲区（供 RawStream 客户端使用）
    pub(crate) raw_buffer: Arc<tokio::sync::Mutex<Vec<u8>>>,
}

/// 中继桥接数据（一个 PTY 会话对应一个 relay 连接）
struct RelayBridge {
    relay_client: Arc<RelayClient>,
    input_task: tokio::task::JoinHandle<()>,
    event_task: tokio::task::JoinHandle<()>,
    relay_session_id: String,
}

pub struct TerminalServer {
    bind_addr: String,
    config: ServerConfig,
    sessions: Arc<DashMap<PtySessionId, SessionData>>,
    clients: Arc<Mutex<Vec<WebSocketClient>>>,
    event_tx: broadcast::Sender<ServerEvent>,
    /// 活跃的 relay 桥接：PTY session ID → RelayBridge
    relay_bridges: Arc<DashMap<PtySessionId, RelayBridge>>,
}

#[derive(Clone, Debug)]
pub enum ServerEvent {
    /// 会话输出（携带原始字节数据供 RawStream 客户端使用）
    SessionOutput(PtySessionId, Vec<u8>),
    SessionCreated(PtySessionId),
    SessionClosed(PtySessionId),
    ClientConnected,
    ClientDisconnected,
}

struct WebSocketClient {
    id: ClientId,
    sender: futures_util::stream::SplitSink<WebSocketStream<TcpStream>, Message>,
    subscribed_sessions: Vec<PtySessionId>,
    protocol_mode: ProtocolMode,
}

type ClientId = usize;

static NEXT_CLIENT_ID: AtomicUsize = AtomicUsize::new(1);

impl TerminalServer {
    pub async fn new(bind_addr: String, config: ServerConfig) -> Result<Self> {
        let sessions = Arc::new(DashMap::new());
        let clients = Arc::new(Mutex::new(Vec::new()));
        let relay_bridges = Arc::new(DashMap::new());
        let (event_tx, _) = broadcast::channel(1000);

        let server = Self {
            bind_addr,
            config,
            sessions,
            clients,
            event_tx,
            relay_bridges,
        };

        // 启动事件处理器
        server.start_event_handler().await;

        Ok(server)
    }

    pub async fn start(&self) -> Result<()> {
        let listener = TcpListener::bind(&self.bind_addr).await?;
        info!("Server listening on {}", self.bind_addr);

        loop {
            match listener.accept().await {
                Ok((stream, addr)) => {
                    debug!("New connection from: {}", addr);
                    let clients = self.clients.clone();
                    let sessions = self.sessions.clone();
                    let event_tx = self.event_tx.clone();
                    let relay_bridges = self.relay_bridges.clone();

                    tokio::spawn(async move {
                        if let Err(e) = Self::handle_connection(
                            stream,
                            clients,
                            sessions,
                            event_tx,
                            relay_bridges,
                        ).await {
                            error!("Connection error: {}", e);
                        }
                    });
                }
                Err(e) => {
                    error!("Accept error: {}", e);
                }
            }
        }
    }

    /// Subscribe to server events (for Hook API)
    pub fn subscribe_events(&self) -> broadcast::Receiver<ServerEvent> {
        self.event_tx.subscribe()
    }

    /// Get shared reference to sessions map (for Hook API input injection)
    pub fn sessions_ref(&self) -> Arc<DashMap<PtySessionId, SessionData>> {
        self.sessions.clone()
    }

    pub async fn shutdown(&self) -> Result<()> {
        info!("Shutting down sessions...");
        // 清理所有 relay bridges
        let relay_ids: Vec<PtySessionId> = self.relay_bridges.iter().map(|e| *e.key()).collect();
        for id in relay_ids {
            if let Some((_, bridge)) = self.relay_bridges.remove(&id) {
                let _ = bridge.relay_client.disconnect().await;
                bridge.input_task.abort();
                bridge.event_task.abort();
            }
        }
        // 清理所有 sessions
        let session_ids: Vec<PtySessionId> = self.sessions.iter().map(|e| *e.key()).collect();
        for id in session_ids {
            self.sessions.remove(&id);
        }
        Ok(())
    }

    async fn handle_connection(
        stream: TcpStream,
        clients: Arc<Mutex<Vec<WebSocketClient>>>,
        sessions: Arc<DashMap<PtySessionId, SessionData>>,
        event_tx: broadcast::Sender<ServerEvent>,
        relay_bridges: Arc<DashMap<PtySessionId, RelayBridge>>,
    ) -> Result<()> {
        let ws_stream = accept_async(stream).await?;
        let peer_addr = ws_stream.get_ref().peer_addr()?;
        info!("WebSocket connected: {}", peer_addr);

        let (ws_sender, mut ws_receiver) = ws_stream.split();
        let client_id = NEXT_CLIENT_ID.fetch_add(1, Ordering::SeqCst);

        let client = WebSocketClient {
            id: client_id,
            sender: ws_sender,
            subscribed_sessions: Vec::new(),
            protocol_mode: ProtocolMode::JsonIncremental, // 默认 JSON 模式，negotiate 后可切换
        };

        {
            let mut clients = clients.lock().await;
            clients.push(client);
        }

        let _ = event_tx.send(ServerEvent::ClientConnected);

        // 启动心跳
        let clients_for_ping = clients.clone();
        let ping_task = tokio::spawn(async move {
            let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(30));
            loop {
                interval.tick().await;
                let ping_frame = encode_frame(&Frame::Ping);
                let mut clients_guard = clients_for_ping.lock().await;
                if let Some(client) = clients_guard.iter_mut().find(|c| c.id == client_id) {
                    if client.sender.send(Message::Binary(ping_frame.into())).await.is_err() {
                        break;
                    }
                } else {
                    break;
                }
            }
        });

        while let Some(msg_result) = ws_receiver.next().await {
            match msg_result {
                Ok(Message::Text(text)) => {
                    if let Ok(data) = Self::parse_text_message(&text) {
                        Self::handle_protocol_message(data, &sessions, &event_tx, &clients, client_id, &relay_bridges).await;
                    }
                }
                Ok(Message::Binary(data)) => {
                    Self::handle_binary_message(data.to_vec(), &sessions, &event_tx, &clients, client_id).await;
                }
                Ok(Message::Close(_)) => {
                    info!("Client {} disconnected", client_id);
                    break;
                }
                Ok(Message::Pong(_)) => {
                    debug!("Received pong from client {}", client_id);
                }
                Err(e) => {
                    error!("WebSocket error: {}", e);
                    break;
                }
                _ => {}
            }
        }

        ping_task.abort();

        {
            let mut clients = clients.lock().await;
            clients.retain(|c| c.id != client_id);
        }

        let _ = event_tx.send(ServerEvent::ClientDisconnected);

        Ok(())
    }

    fn parse_text_message(text: &str) -> Result<serde_json::Value> {
        Ok(serde_json::from_str(text)?)
    }

    async fn handle_binary_message(
        data: Vec<u8>,
        sessions: &Arc<DashMap<PtySessionId, SessionData>>,
        _event_tx: &broadcast::Sender<ServerEvent>,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        client_id: ClientId,
    ) {
        if let Ok(frame) = crate::protocol::decode_frame(&data) {
            match frame {
                Frame::Input(session_id_str, input_data) => {
                    if let Ok(session_id) = PtySessionId::parse(&session_id_str) {
                        if let Some(session_data) = sessions.get(&session_id) {
                            let session = session_data.session.lock().await;
                            if let Err(e) = session.write(&input_data) {
                                debug!("Failed to write to session {}: {}", session_id, e);
                            }
                        }
                    }
                }
                Frame::Subscribe(session_id_strs) => {
                    Self::handle_subscribe(session_id_strs, clients, sessions, client_id).await;
                }
                Frame::ResizeSession(session_id_str, cols, rows) => {
                    if let Ok(session_id) = PtySessionId::parse(&session_id_str) {
                        if let Some(session_data) = sessions.get(&session_id) {
                            let mut session = session_data.session.lock().await;
                            if let Err(e) = session.resize(cols, rows).await {
                                warn!("Failed to resize session {}: {}", session_id, e);
                            }
                            // resize 后更新渲染器
                            let mut renderer = session_data.renderer.lock().await;
                            renderer.resize(cols as usize, rows as usize);
                        }
                    }
                }
                Frame::CloseSession(session_id_str) => {
                    if let Ok(session_id) = PtySessionId::parse(&session_id_str) {
                        sessions.remove(&session_id);
                        info!("Session {} closed by client request", session_id);
                    }
                }
                Frame::Pong => {
                    debug!("Received pong from client {}", client_id);
                }
                _ => {}
            }
        }
    }

    /// 处理订阅请求 - 订阅后立即发送全屏帧
    async fn handle_subscribe(
        session_id_strs: Vec<String>,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        sessions: &Arc<DashMap<PtySessionId, SessionData>>,
        client_id: ClientId,
    ) {
        let mut session_ids = Vec::new();
        for sid_str in &session_id_strs {
            if let Ok(sid) = PtySessionId::parse(sid_str) {
                session_ids.push(sid);
            }
        }

        // 更新订阅
        {
            let mut clients = clients.lock().await;
            if let Some(client) = clients.iter_mut().find(|c| c.id == client_id) {
                client.subscribed_sessions = session_ids.clone();
                debug!("Client {} subscribed to {} sessions", client_id, session_ids.len());
            }
        }

        // 立即给新订阅的客户端发送全屏帧（或 ANSI 追赶数据）
        for sid in &session_ids {
            if let Some(session_data) = sessions.get(sid) {
                let session = session_data.session.lock().await;
                let (cols, rows) = session.size();
                let (cells, cursor) = session.state_snapshot().await;
                drop(session);

                // 获取客户端协议模式
                let client_mode = {
                    let clients_guard = clients.lock().await;
                    clients_guard.iter().find(|c| c.id == client_id).map(|c| c.protocol_mode)
                };

                match client_mode {
                    Some(ProtocolMode::RawStream) => {
                        // RawStream 客户端：不发追赶数据（避免显式颜色覆盖主题色）
                        // 新 session 由 shell 自己输出内容
                        // 后续加入的观察者需要用别的机制追赶
                    }
                    _ => {
                        // JSON 客户端：发送全屏 JSON 帧
                        let mut renderer = session_data.renderer.lock().await;
                        let (seq, dirty_regions, cursor_frame) = renderer.render_full(&cells, cursor, cols, rows);

                        let screen_frame = ScreenFrame { seq, cols, rows, dirty_regions };
                        let frame = Frame::SessionOutput(sid.as_string(), screen_frame);
                        let binary_data = encode_frame(&frame);

                        let mut clients_guard = clients.lock().await;
                        if let Some(client) = clients_guard.iter_mut().find(|c| c.id == client_id) {
                            let _ = client.sender.send(Message::Binary(binary_data.into())).await;

                            if let Some(cursor_frm) = cursor_frame {
                                let cursor_data = encode_frame(&Frame::CursorUpdate(cursor_frm));
                                let _ = client.sender.send(Message::Binary(cursor_data.into())).await;
                            }
                        }
                    }
                }
            }
        }
    }

    async fn handle_protocol_message(
        data: serde_json::Value,
        sessions: &Arc<DashMap<PtySessionId, SessionData>>,
        event_tx: &broadcast::Sender<ServerEvent>,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        client_id: ClientId,
        relay_bridges: &Arc<DashMap<PtySessionId, RelayBridge>>,
    ) {
        if let Some(msg_type) = data["type"].as_str() {
            match msg_type {
                MSG_TYPE_CREATE_SESSION => {
                    if let Ok(session_id) = Self::handle_create_session(data, sessions, event_tx).await {
                        let frame = Frame::SessionCreated(session_id.as_string());
                        let binary_data = encode_frame(&frame);

                        let mut clients_guard = clients.lock().await;
                        if let Some(client) = clients_guard.iter_mut().find(|c| c.id == client_id) {
                            client.subscribed_sessions.push(session_id);
                            let _ = client.sender.send(Message::Binary(binary_data.into())).await;
                        }
                    }
                }
                MSG_TYPE_INPUT => {
                    if let Some(session_id) = data["session_id"].as_str() {
                        if let Some(input_data) = data["data"].as_str() {
                            if let Ok(id) = PtySessionId::parse(session_id) {
                                if let Some(session_data) = sessions.get(&id) {
                                    let session = session_data.session.lock().await;
                                    if let Err(e) = session.write(input_data.as_bytes()) {
                                        debug!("Failed to write to session {}: {}", id, e);
                                    }
                                }
                            }
                        }
                    }
                }
                MSG_TYPE_SUBSCRIBE => {
                    if let Some(session_ids) = data["session_ids"].as_array() {
                        let sid_strs: Vec<String> = session_ids
                            .iter()
                            .filter_map(|v| v.as_str())
                            .map(|s| s.to_string())
                            .collect();
                        Self::handle_subscribe(sid_strs, clients, sessions, client_id).await;
                    }
                }
                "resize" => {
                    if let Some(session_id) = data["session_id"].as_str() {
                        let cols = data["cols"].as_u64().unwrap_or(80) as u16;
                        let rows = data["rows"].as_u64().unwrap_or(24) as u16;
                        if let Ok(id) = PtySessionId::parse(session_id) {
                            if let Some(session_data) = sessions.get(&id) {
                                let mut session = session_data.session.lock().await;
                                if let Err(e) = session.resize(cols, rows).await {
                                    warn!("Failed to resize session {}: {}", id, e);
                                }
                                let mut renderer = session_data.renderer.lock().await;
                                renderer.resize(cols as usize, rows as usize);
                                info!("Resized session {} to {}x{}", id, cols, rows);
                                // Shell 会在收到 SIGWINCH 后自动重绘，不需要手动发 state_to_ansi
                            }
                        }
                    }
                }
                MSG_TYPE_NEGOTIATE => {
                    let protocol = data["protocol"].as_str().unwrap_or("json_incremental");
                    let mode = if protocol == "raw_stream" {
                        ProtocolMode::RawStream
                    } else {
                        ProtocolMode::JsonIncremental
                    };
                    let mut clients_guard = clients.lock().await;
                    if let Some(client) = clients_guard.iter_mut().find(|c| c.id == client_id) {
                        info!("Client {} negotiated protocol: {:?}", client_id, mode);
                        client.protocol_mode = mode;
                    }
                }
                MSG_TYPE_LIST_SESSIONS => {
                    let session_ids: Vec<String> = sessions.iter()
                        .map(|entry| entry.key().as_string())
                        .collect();
                    let response = serde_json::json!({
                        "type": "session_list",
                        "sessions": session_ids.iter().map(|id| {
                            serde_json::json!({ "id": id, "is_active": true })
                        }).collect::<Vec<_>>()
                    });
                    let msg = Message::Text(response.to_string().into());
                    let mut clients_guard = clients.lock().await;
                    if let Some(client) = clients_guard.iter_mut().find(|c| c.id == client_id) {
                        let _ = client.sender.send(msg).await;
                    }
                }
                "shell_info" => {
                    // 返回服务端检测到的 shell 环境信息 + 所有可用 shell
                    let info = crate::pty::ShellInfo::detect();
                    let available = crate::pty::detect_available_shells();
                    let response = serde_json::json!({
                        "type": "shell_info",
                        "shell": info.shell,
                        "shell_name": info.shell_name,
                        "home": info.home,
                        "user": info.user,
                        "available_shells": available,
                    });
                    let msg = Message::Text(response.to_string().into());
                    let mut clients_guard = clients.lock().await;
                    if let Some(client) = clients_guard.iter_mut().find(|c| c.id == client_id) {
                        let _ = client.sender.send(msg).await;
                    }
                }
                MSG_TYPE_START_RELAY => {
                    Self::handle_start_relay(data, sessions, relay_bridges, clients, client_id).await;
                }
                MSG_TYPE_STOP_RELAY => {
                    Self::handle_stop_relay(data, sessions, relay_bridges, clients, client_id).await;
                }
                MSG_TYPE_LIST_DIR => {
                    Self::handle_list_dir(data, clients, client_id).await;
                }
                _ => {}
            }
        }
    }

    /// 列出目录内容（供移动端文件选择器使用）
    async fn handle_list_dir(
        data: serde_json::Value,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        client_id: ClientId,
    ) {
        let path = data["path"].as_str().unwrap_or(".");

        // 解析路径：~ 展开为 home 目录
        let resolved = if path.starts_with('~') {
            if let Some(home) = std::env::var("HOME").ok() {
                path.replacen('~', &home, 1)
            } else {
                path.to_string()
            }
        } else if path == "." {
            std::env::current_dir()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|_| ".".to_string())
        } else {
            path.to_string()
        };

        // 在 blocking 线程中执行文件系统操作，避免阻塞 tokio
        let resolved_clone = resolved.clone();
        let result = tokio::task::spawn_blocking(move || {
            let resolved_path = std::path::Path::new(&resolved_clone);

            if !resolved_path.is_dir() {
                return Err("Not a directory or does not exist".to_string());
            }

            let mut entries = Vec::new();
            if let Ok(read_dir) = std::fs::read_dir(resolved_path) {
                for entry in read_dir.flatten() {
                    let name = entry.file_name().to_string_lossy().to_string();
                    let metadata = entry.metadata().ok();
                    let is_dir = metadata.as_ref().map(|m| m.is_dir()).unwrap_or(false);
                    let size = metadata.as_ref().map(|m| m.len()).unwrap_or(0);
                    let is_hidden = name.starts_with('.');

                    entries.push(serde_json::json!({
                        "name": name,
                        "type": if is_dir { "dir" } else { "file" },
                        "size": size,
                        "hidden": is_hidden,
                    }));
                }
            }

            entries.sort_by(|a, b| {
                let a_dir = a["type"].as_str() == Some("dir");
                let b_dir = b["type"].as_str() == Some("dir");
                match (a_dir, b_dir) {
                    (true, false) => std::cmp::Ordering::Less,
                    (false, true) => std::cmp::Ordering::Greater,
                    _ => {
                        let a_name = a["name"].as_str().unwrap_or("");
                        let b_name = b["name"].as_str().unwrap_or("");
                        a_name.to_lowercase().cmp(&b_name.to_lowercase())
                    }
                }
            });

            Ok(entries)
        }).await;

        match result {
            Ok(Ok(entries)) => {
                Self::send_text_to_client(clients, client_id, &serde_json::json!({
                    "type": "dir_listing",
                    "path": resolved,
                    "entries": entries,
                })).await;
            }
            Ok(Err(err)) => {
                Self::send_text_to_client(clients, client_id, &serde_json::json!({
                    "type": "dir_listing",
                    "path": path,
                    "error": err,
                })).await;
            }
            Err(_) => {
                Self::send_text_to_client(clients, client_id, &serde_json::json!({
                    "type": "dir_listing",
                    "path": path,
                    "error": "Internal error reading directory",
                })).await;
            }
        }
    }

    /// 启动 relay 桥接：将指定 PTY 会话通过 relay 共享给远程客户端
    async fn handle_start_relay(
        data: serde_json::Value,
        sessions: &Arc<DashMap<PtySessionId, SessionData>>,
        relay_bridges: &Arc<DashMap<PtySessionId, RelayBridge>>,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        client_id: ClientId,
    ) {
        let session_id_str = match data["session_id"].as_str() {
            Some(s) => s.to_string(),
            None => {
                Self::send_text_to_client(clients, client_id, &serde_json::json!({
                    "type": "relay_error", "error": "missing session_id"
                })).await;
                return;
            }
        };
        let relay_url = match data["relay_url"].as_str() {
            Some(s) => s.to_string(),
            None => {
                Self::send_text_to_client(clients, client_id, &serde_json::json!({
                    "type": "relay_error", "error": "missing relay_url"
                })).await;
                return;
            }
        };
        let token = data["token"].as_str().map(|s| s.to_string());
        let relay_session_id = match data["relay_session_id"].as_str() {
            Some(s) => s.to_string(),
            None => {
                Self::send_text_to_client(clients, client_id, &serde_json::json!({
                    "type": "relay_error", "error": "missing relay_session_id"
                })).await;
                return;
            }
        };

        // 验证本地 PTY session 存在
        let session_id = match PtySessionId::parse(&session_id_str) {
            Ok(id) => id,
            Err(_) => {
                Self::send_text_to_client(clients, client_id, &serde_json::json!({
                    "type": "relay_error", "error": "invalid session_id"
                })).await;
                return;
            }
        };
        if !sessions.contains_key(&session_id) {
            Self::send_text_to_client(clients, client_id, &serde_json::json!({
                "type": "relay_error", "error": "session not found"
            })).await;
            return;
        }

        // 检查是否已有 relay bridge
        if relay_bridges.contains_key(&session_id) {
            Self::send_text_to_client(clients, client_id, &serde_json::json!({
                "type": "relay_error", "error": "session already shared via relay"
            })).await;
            return;
        }

        // 创建 relay 事件通道
        let (event_tx, mut event_rx) = tokio::sync::mpsc::channel::<RelayEvent>(32);

        // 创建 RelayClient
        let relay_client = match RelayClient::new(
            relay_url.clone(),
            relay_session_id.clone(),
            RelayRole::Host,
            token,
            Some(event_tx),
        ) {
            Ok(c) => Arc::new(c),
            Err(e) => {
                Self::send_text_to_client(clients, client_id, &serde_json::json!({
                    "type": "relay_error", "error": format!("failed to create relay client: {}", e)
                })).await;
                return;
            }
        };

        // 连接到 relay server
        if let Err(e) = relay_client.connect().await {
            Self::send_text_to_client(clients, client_id, &serde_json::json!({
                "type": "relay_error", "error": format!("failed to connect to relay: {}", e)
            })).await;
            return;
        }

        info!("Relay bridge started for session {} -> relay session {}", session_id, relay_session_id);

        // 启动 relay → PTY 输入转发任务
        let relay_for_input = relay_client.clone();
        let sessions_for_input = sessions.clone();
        let input_task = tokio::spawn(async move {
            loop {
                match relay_for_input.recv_data().await {
                    Ok(data) => {
                        if let Some(session_data) = sessions_for_input.get(&session_id) {
                            let session = session_data.session.lock().await;
                            if let Err(e) = session.write(&data) {
                                warn!("Relay input: failed to write to PTY {}: {}", session_id, e);
                                break;
                            }
                        } else {
                            info!("Relay input: session {} no longer exists", session_id);
                            break;
                        }
                    }
                    Err(e) => {
                        info!("Relay input ended for session {}: {}", session_id, e);
                        break;
                    }
                }
            }
        });

        // 启动 relay 事件监听任务（通知 macOS 客户端对端连接状态）
        let clients_for_events = clients.clone();
        let relay_sid = relay_session_id.clone();
        let event_task = tokio::spawn(async move {
            while let Some(event) = event_rx.recv().await {
                match event {
                    RelayEvent::PeerConnected => {
                        Self::send_text_to_client(&clients_for_events, client_id, &serde_json::json!({
                            "type": "relay_peer_connected",
                            "relay_session_id": relay_sid,
                        })).await;
                    }
                    RelayEvent::PeerDisconnected => {
                        Self::send_text_to_client(&clients_for_events, client_id, &serde_json::json!({
                            "type": "relay_peer_disconnected",
                            "relay_session_id": relay_sid,
                        })).await;
                    }
                    RelayEvent::Error(err) => {
                        Self::send_text_to_client(&clients_for_events, client_id, &serde_json::json!({
                            "type": "relay_error",
                            "relay_session_id": relay_sid,
                            "error": err,
                        })).await;
                    }
                }
            }
        });

        // 存储 relay bridge
        relay_bridges.insert(session_id, RelayBridge {
            relay_client,
            input_task,
            event_task,
            relay_session_id: relay_session_id.clone(),
        });

        // 通知客户端 relay 已启动
        Self::send_text_to_client(clients, client_id, &serde_json::json!({
            "type": "relay_started",
            "session_id": session_id_str,
            "relay_session_id": relay_session_id,
        })).await;
    }

    /// 停止 relay 桥接
    async fn handle_stop_relay(
        data: serde_json::Value,
        _sessions: &Arc<DashMap<PtySessionId, SessionData>>,
        relay_bridges: &Arc<DashMap<PtySessionId, RelayBridge>>,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        client_id: ClientId,
    ) {
        let session_id_str = match data["session_id"].as_str() {
            Some(s) => s.to_string(),
            None => return,
        };
        let session_id = match PtySessionId::parse(&session_id_str) {
            Ok(id) => id,
            Err(_) => return,
        };

        if let Some((_, bridge)) = relay_bridges.remove(&session_id) {
            let _ = bridge.relay_client.disconnect().await;
            bridge.input_task.abort();
            bridge.event_task.abort();
            info!("Relay bridge stopped for session {}", session_id);

            Self::send_text_to_client(clients, client_id, &serde_json::json!({
                "type": "relay_stopped",
                "session_id": session_id_str,
            })).await;
        }
    }

    /// 辅助：发送 JSON 文本消息给指定客户端
    async fn send_text_to_client(
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        client_id: ClientId,
        json: &serde_json::Value,
    ) {
        let msg = Message::Text(json.to_string().into());
        let mut clients_guard = clients.lock().await;
        if let Some(client) = clients_guard.iter_mut().find(|c| c.id == client_id) {
            let _ = client.sender.send(msg).await;
        }
    }

    /// 创建会话并启动输出广播任务
    async fn handle_create_session(
        data: serde_json::Value,
        sessions: &Arc<DashMap<PtySessionId, SessionData>>,
        event_tx: &broadcast::Sender<ServerEvent>,
    ) -> Result<PtySessionId> {
        // 使用 PtyConfig::default() 作为基础（已包含环境检测）
        let defaults = PtyConfig::default();

        // 客户端可以覆盖 shell，"default" 或空值表示使用检测到的默认 shell
        let command = data["command"].as_str()
            .filter(|c| !c.is_empty() && *c != "default" && *c != "sh")
            .map(|c| c.to_string())
            .unwrap_or(defaults.shell);

        let args: Vec<String> = data["args"]
            .as_array()
            .map(|arr| arr.iter().filter_map(|v| v.as_str()).map(|s| s.to_string()).collect())
            .filter(|a: &Vec<String>| !a.is_empty())
            .unwrap_or(defaults.args);

        let cwd = data["cwd"].as_str()
            .map(|s| s.to_string())
            .or(defaults.cwd);

        // 客户端提供的额外 env 会合并到检测到的环境中
        let mut env = defaults.env;
        if let Some(client_env) = data["env"].as_array() {
            for pair in client_env.iter().filter_map(|v| v.as_array()) {
                if pair.len() >= 2 {
                    if let (Some(key), Some(value)) = (pair[0].as_str(), pair[1].as_str()) {
                        // 客户端 env 覆盖默认值
                        if let Some(entry) = env.iter_mut().find(|(k, _)| k == key) {
                            entry.1 = value.to_string();
                        } else {
                            env.push((key.to_string(), value.to_string()));
                        }
                    }
                }
            }
        }

        info!("Creating session with shell: {}, args: {:?}, cwd: {:?}", command, args, cwd);

        let pty_config = PtyConfig {
            shell: command,
            args,
            cols: data["cols"].as_u64().unwrap_or(80) as u16,
            rows: data["rows"].as_u64().unwrap_or(24) as u16,
            env,
            cwd,
        };

        // 创建 PTY 会话，获取事件接收器
        let (session, mut event_rx) = PtySession::new(&pty_config)?;
        let session_id = session.id();
        let (cols, rows) = session.size();

        let renderer = Arc::new(tokio::sync::Mutex::new(Renderer::new(cols as usize, rows as usize)));
        let session_arc = Arc::new(tokio::sync::Mutex::new(session));

        // 原始字节缓冲区
        let raw_buffer = Arc::new(tokio::sync::Mutex::new(Vec::new()));
        let raw_buffer_for_task = raw_buffer.clone();

        // 存储会话数据
        sessions.insert(session_id, SessionData {
            session: session_arc.clone(),
            renderer: renderer.clone(),
            raw_buffer,
        });

        // 发送会话创建事件
        let _ = event_tx.send(ServerEvent::SessionCreated(session_id));

        // 🔥 核心：启动 PTY 输出广播任务
        let event_tx_clone = event_tx.clone();
        let session_id_for_task = session_id;
        tokio::spawn(async move {
            // 节流：合并短时间内的多次输出为一次广播
            let mut throttle_interval = tokio::time::interval(tokio::time::Duration::from_millis(16)); // ~60fps
            let mut has_pending_output = false;

            loop {
                tokio::select! {
                    // 收到 PTY 输出事件
                    event = event_rx.recv() => {
                        match event {
                            Some(PtyEvent::Output(data)) => {
                                // VT100 解析已在 reader 任务中完成
                                // 缓存原始字节供 RawStream 客户端使用
                                {
                                    let mut buf = raw_buffer_for_task.lock().await;
                                    buf.extend_from_slice(&data);
                                }
                                has_pending_output = true;
                            }
                            Some(PtyEvent::Exited(status)) => {
                                info!("Session {} process exited: {:?}", session_id_for_task, status);
                                let _ = event_tx_clone.send(ServerEvent::SessionClosed(session_id_for_task));
                                break;
                            }
                            None => {
                                // 通道关闭
                                info!("Session {} event channel closed", session_id_for_task);
                                let _ = event_tx_clone.send(ServerEvent::SessionClosed(session_id_for_task));
                                break;
                            }
                        }
                    }
                    // 节流定时器
                    _ = throttle_interval.tick() => {
                        if has_pending_output {
                            has_pending_output = false;
                            // 取出并清空原始缓冲
                            let raw_data = {
                                let mut buf = raw_buffer_for_task.lock().await;
                                std::mem::take(&mut *buf)
                            };
                            debug!("Broadcasting output for session {} ({} raw bytes)", session_id_for_task, raw_data.len());
                            let _ = event_tx_clone.send(ServerEvent::SessionOutput(session_id_for_task, raw_data));
                        }
                    }
                }
            }
        });

        info!("Created new session: {} ({}x{})", session_id, cols, rows);

        Ok(session_id)
    }

    /// 启动事件处理器：监听所有服务器事件并分发
    async fn start_event_handler(&self) {
        let mut rx = self.event_tx.subscribe();
        let sessions = self.sessions.clone();
        let clients = self.clients.clone();
        let relay_bridges = self.relay_bridges.clone();

        tokio::spawn(async move {
            while let Ok(event) = rx.recv().await {
                match event {
                    ServerEvent::SessionOutput(session_id, raw_data) => {
                        debug!("Event handler: broadcasting output for {}", session_id);
                        Self::broadcast_session_output(session_id, raw_data, &sessions, &clients, &relay_bridges).await;
                    }
                    ServerEvent::SessionCreated(session_id) => {
                        info!("Session created: {}", session_id);
                    }
                    ServerEvent::SessionClosed(session_id) => {
                        info!("Session closed: {}", session_id);
                        // 清理 relay bridge（如果有）
                        if let Some((_, bridge)) = relay_bridges.remove(&session_id) {
                            let _ = bridge.relay_client.disconnect().await;
                            bridge.input_task.abort();
                            bridge.event_task.abort();
                            info!("Relay bridge cleaned up for closed session {}", session_id);
                        }
                        // 通知订阅的客户端
                        let frame = Frame::SessionClosed(session_id.as_string());
                        let binary_data = encode_frame(&frame);
                        let mut clients_guard = clients.lock().await;
                        for client in clients_guard.iter_mut() {
                            if client.subscribed_sessions.contains(&session_id) {
                                let _ = client.sender.send(Message::Binary(binary_data.clone().into())).await;
                                client.subscribed_sessions.retain(|s| s != &session_id);
                            }
                        }
                        // 清理会话
                        sessions.remove(&session_id);
                    }
                    ServerEvent::ClientConnected => {
                        info!("Client connected");
                    }
                    ServerEvent::ClientDisconnected => {
                        info!("Client disconnected");
                    }
                }
            }
        });
    }

    /// 🔥 核心广播函数 - 按协议模式分流发送（含 relay 转发）
    async fn broadcast_session_output(
        session_id: PtySessionId,
        raw_data: Vec<u8>,
        sessions: &Arc<DashMap<PtySessionId, SessionData>>,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        relay_bridges: &Arc<DashMap<PtySessionId, RelayBridge>>,
    ) {
        let mut clients_guard = clients.lock().await;

        // 检查是否有订阅客户端
        let has_json_clients = clients_guard.iter().any(|c| {
            c.subscribed_sessions.contains(&session_id) && c.protocol_mode == ProtocolMode::JsonIncremental
        });
        let has_raw_clients = clients_guard.iter().any(|c| {
            c.subscribed_sessions.contains(&session_id) && c.protocol_mode == ProtocolMode::RawStream
        });

        let has_relay = relay_bridges.contains_key(&session_id);

        if !has_json_clients && !has_raw_clients && !has_relay {
            return;
        }

        // RawStream 客户端：直接转发原始字节
        if has_raw_clients && !raw_data.is_empty() {
            let raw_frame = encode_frame(&Frame::RawOutput(session_id.as_string(), raw_data.clone()));
            for client in clients_guard.iter_mut() {
                if client.subscribed_sessions.contains(&session_id) && client.protocol_mode == ProtocolMode::RawStream {
                    if let Err(e) = client.sender.send(Message::Binary(raw_frame.clone().into())).await {
                        warn!("Failed to send raw to client {}: {}", client.id, e);
                    }
                }
            }
        }

        // Relay 转发：将原始 PTY 字节加密后发送到 relay
        if has_relay && !raw_data.is_empty() {
            if let Some(bridge) = relay_bridges.get(&session_id) {
                if bridge.relay_client.is_peer_connected().await {
                    if let Err(e) = bridge.relay_client.send_data(&raw_data).await {
                        warn!("Failed to send to relay for session {}: {}", session_id, e);
                    }
                }
            }
        }

        // JsonIncremental 客户端：生成增量帧
        if has_json_clients {
            drop(clients_guard); // 释放锁以获取 session 数据

            if let Some(session_data) = sessions.get(&session_id) {
                let session = session_data.session.lock().await;
                let (cols, rows) = session.size();
                let (cells, cursor) = session.state_snapshot().await;
                drop(session);

                let mut renderer = session_data.renderer.lock().await;
                let (seq, dirty_regions, cursor_frame) = renderer.render(&cells, cursor);
                drop(renderer);

                if dirty_regions.is_empty() && cursor_frame.is_none() {
                    return;
                }

                let mut clients_guard = clients.lock().await;

                if !dirty_regions.is_empty() {
                    let screen_frame = ScreenFrame { seq, cols, rows, dirty_regions };
                    let frame = Frame::SessionOutput(session_id.as_string(), screen_frame);
                    let binary_data = encode_frame(&frame);

                    for client in clients_guard.iter_mut() {
                        if client.subscribed_sessions.contains(&session_id) && client.protocol_mode == ProtocolMode::JsonIncremental {
                            if let Err(e) = client.sender.send(Message::Binary(binary_data.clone().into())).await {
                                warn!("Failed to send to client {}: {}", client.id, e);
                            }
                        }
                    }
                }

                if let Some(cursor_frm) = cursor_frame {
                    let cursor_data = encode_frame(&Frame::CursorUpdate(cursor_frm));
                    for client in clients_guard.iter_mut() {
                        if client.subscribed_sessions.contains(&session_id) && client.protocol_mode == ProtocolMode::JsonIncremental {
                            let _ = client.sender.send(Message::Binary(cursor_data.clone().into())).await;
                        }
                    }
                }
            }
        }
    }
}
