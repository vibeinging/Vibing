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
use tracing::{debug, error, info};

use crate::config::ServerConfig;
use crate::pty::{PtySession, PtySessionId, PtyConfig};
use crate::protocol::{Frame, encode_frame};

// JSON 协议消息类型常量
const MSG_TYPE_CREATE_SESSION: &str = "create_session";
const MSG_TYPE_INPUT: &str = "input";
const MSG_TYPE_SUBSCRIBE: &str = "subscribe";

pub struct TerminalServer {
    bind_addr: String,
    config: ServerConfig,

    // 会话管理
    sessions: Arc<DashMap<PtySessionId, Arc<PtySession>>>,

    // WebSocket 客户端
    clients: Arc<Mutex<Vec<WebSocketClient>>>,

    // 事件广播
    event_tx: broadcast::Sender<ServerEvent>,
}

// 服务器事件
#[derive(Clone, Debug)]
pub enum ServerEvent {
    SessionOutput(PtySessionId, Vec<u8>),
    SessionCreated(PtySessionId),
    SessionClosed(PtySessionId),
    ClientConnected,
    ClientDisconnected,
}

// WebSocket 客户端包装
struct WebSocketClient {
    id: ClientId,
    sender: futures_util::stream::SplitSink<WebSocketStream<TcpStream>, Message>,
    subscribed_sessions: Vec<PtySessionId>,
    // 用于向客户端发送消息的通道
    client_tx: broadcast::Sender<Vec<u8>>,
}

type ClientId = usize;

// 全局客户端 ID 生成器
static NEXT_CLIENT_ID: AtomicUsize = AtomicUsize::new(1);

impl TerminalServer {
    pub async fn new(bind_addr: String, config: ServerConfig) -> Result<Self> {
        let sessions = Arc::new(DashMap::new());
        let clients = Arc::new(Mutex::new(Vec::new()));
        let (event_tx, _) = broadcast::channel(100);

        let server = Self {
            bind_addr,
            config,
            sessions,
            clients,
            event_tx,
        };

        // 启动事件处理器
        server.start_event_handler().await;

        Ok(server)
    }

    pub async fn start(&self) -> Result<()> {
        let listener = TcpListener::bind(&self.bind_addr).await?;
        info!("🎧 Server listening on {}", self.bind_addr);

        loop {
            match listener.accept().await {
                Ok((stream, addr)) => {
                    debug!("New connection from: {}", addr);
                    let clients = self.clients.clone();
                    let sessions = self.sessions.clone();
                    let event_tx = self.event_tx.clone();

                    tokio::spawn(async move {
                        if let Err(e) = Self::handle_connection(
                            stream,
                            clients,
                            sessions,
                            event_tx,
                        )
                        .await
                        {
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

    pub async fn shutdown(&self) -> Result<()> {
        info!("🛑 Shutting down sessions...");

        let session_ids: Vec<PtySessionId> = self.sessions.iter().map(|e| *e.key()).collect();
        for id in session_ids {
            if let Some((_, session)) = self.sessions.remove(&id) {
                // 由于 PtySession 的 close 需要 self，我们只能通过 drop 来关闭
                // Drop impl 会处理清理工作
            }
        }

        Ok(())
    }

    async fn handle_connection(
        stream: TcpStream,
        clients: Arc<Mutex<Vec<WebSocketClient>>>,
        sessions: Arc<DashMap<PtySessionId, Arc<PtySession>>>,
        event_tx: broadcast::Sender<ServerEvent>,
    ) -> Result<()> {
        let ws_stream = accept_async(stream).await?;
        let peer_addr = ws_stream.get_ref().peer_addr()?;
        info!("WebSocket connected: {}", peer_addr);

        let (ws_sender, mut ws_receiver) = ws_stream.split();
        let client_id = NEXT_CLIENT_ID.fetch_add(1, Ordering::SeqCst);

        // 创建客户端专用的广播通道
        let (client_tx, _client_rx) = broadcast::channel(100);

        // 创建客户端
        let client = WebSocketClient {
            id: client_id,
            sender: ws_sender,
            subscribed_sessions: Vec::new(),
            client_tx,
        };

        // 添加到客户端列表
        {
            let mut clients = clients.lock().await;
            clients.push(client);
        }

        let _ = event_tx.send(ServerEvent::ClientConnected);

        while let Some(msg_result) = ws_receiver.next().await {
            match msg_result {
                Ok(Message::Text(text)) => {
                    if let Ok(data) = Self::parse_text_message(&text) {
                        Self::handle_protocol_message(data, &sessions, &event_tx, &clients, client_id).await;
                    }
                }
                Ok(Message::Binary(data)) => {
                    Self::handle_binary_message(data.to_vec(), &sessions, &event_tx, &clients, client_id).await;
                }
                Ok(Message::Close(_)) => {
                    info!("Client {} disconnected", client_id);
                    break;
                }
                Err(e) => {
                    error!("WebSocket error: {}", e);
                    break;
                }
                _ => {}
            }
        }

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
        sessions: &Arc<DashMap<PtySessionId, Arc<PtySession>>>,
        _event_tx: &broadcast::Sender<ServerEvent>,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        client_id: ClientId,
    ) {
        // 解析协议
        if let Ok(frame) = crate::protocol::decode_frame(&data) {
            match frame {
                Frame::Input(session_id_str, input_data) => {
                    // 输入数据到指定会话
                    if let Ok(session_id) = PtySessionId::parse(&session_id_str) {
                        if let Some(session) = sessions.get(&session_id) {
                            if let Err(e) = session.write(&input_data) {
                                debug!("Failed to write to session {}: {}", session_id, e);
                            }
                        }
                    }
                }
                Frame::Subscribe(session_id_strs) => {
                    // 客户端订阅会话
                    Self::handle_subscribe(session_id_strs, clients, client_id).await;
                }
                Frame::ResizeSession(session_id_str, cols, rows) => {
                    // 调整会话大小
                    if let Ok(session_id) = PtySessionId::parse(&session_id_str) {
                        if let Some(session) = sessions.get(&session_id) {
                            // 注意：这里需要获取可变引用，但由于 Arc<PtySession>
                            // 我们需要使用内部的可变性或者通过其他方式处理
                            // 当前简单处理：记录日志
                            debug!("Resize request for session {}: {}x{}", session_id, cols, rows);
                        }
                    }
                }
                Frame::CloseSession(session_id_str) => {
                    // 关闭会话
                    if let Ok(session_id) = PtySessionId::parse(&session_id_str) {
                        sessions.remove(&session_id);
                        info!("Session {} closed by client request", session_id);
                    }
                }
                _ => {}
            }
        }
    }

    // 处理订阅请求
    async fn handle_subscribe(
        session_id_strs: Vec<String>,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        client_id: ClientId,
    ) {
        let mut session_ids = Vec::new();
        for sid_str in session_id_strs {
            if let Ok(sid) = PtySessionId::parse(&sid_str) {
                session_ids.push(sid);
            }
        }

        let mut clients = clients.lock().await;
        if let Some(client) = clients.iter_mut().find(|c| c.id == client_id) {
            // 替换订阅列表
            client.subscribed_sessions = session_ids.clone();
            debug!("Client {} subscribed to {} sessions", client_id, session_ids.len());
        }
    }

    // 处理协议消息
    async fn handle_protocol_message(
        data: serde_json::Value,
        sessions: &Arc<DashMap<PtySessionId, Arc<PtySession>>>,
        event_tx: &broadcast::Sender<ServerEvent>,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        client_id: ClientId,
    ) {
        // 处理 JSON 协议消息
        if let Some(msg_type) = data["type"].as_str() {
            match msg_type {
                MSG_TYPE_CREATE_SESSION => {
                    // 创建新会话
                    if let Ok(session_id) = Self::handle_create_session(data, &sessions, &event_tx).await {
                        // 一次性处理：订阅并发送响应
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
                    // 输入数据
                    if let Some(session_id) = data["session_id"].as_str() {
                        if let Some(input_data) = data["data"].as_str() {
                            if let Ok(id) = PtySessionId::parse(session_id) {
                                if let Some(session) = sessions.get(&id) {
                                    if let Err(e) = session.write(input_data.as_bytes()) {
                                        debug!("Failed to write to session {}: {}", id, e);
                                    }
                                }
                            }
                        }
                    }
                }
                MSG_TYPE_SUBSCRIBE => {
                    // 订阅会话
                    if let Some(session_ids) = data["session_ids"].as_array() {
                        let sid_strs: Vec<String> = session_ids
                            .iter()
                            .filter_map(|v| v.as_str())
                            .map(|s| s.to_string())
                            .collect();
                        Self::handle_subscribe(sid_strs, clients, client_id).await;
                    }
                }
                _ => {}
            }
        }
    }

    // 处理创建会话请求
    async fn handle_create_session(
        data: serde_json::Value,
        sessions: &Arc<DashMap<PtySessionId, Arc<PtySession>>>,
        event_tx: &broadcast::Sender<ServerEvent>,
    ) -> Result<PtySessionId> {
        // 解析请求参数
        let command = data["command"].as_str().unwrap_or("sh");
        let args: Vec<String> = data["args"]
            .as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str())
                    .map(|s| s.to_string())
                    .collect()
            })
            .unwrap_or_default();

        let cwd = data["cwd"].as_str().map(|s| s.to_string());
        let env = data["env"].as_array().map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_array())
                .filter_map(|pair| {
                    if pair.len() >= 2 {
                        let key = pair[0].as_str()?;
                        let value = pair[1].as_str()?;
                        Some((key.to_string(), value.to_string()))
                    } else {
                        None
                    }
                })
                .collect()
        });

        // 构建 PTY 配置
        let mut pty_config = PtyConfig {
            shell: command.to_string(),
            args,
            cols: data["cols"].as_u64().unwrap_or(80) as u16,
            rows: data["rows"].as_u64().unwrap_or(24) as u16,
            env: env.unwrap_or_default(),
        };

        // 设置工作目录
        if let Some(cwd) = cwd {
            // 注意：PtyConfig 没有 cwd 字段，需要在实际启动时处理
            // 这里先记录，后续可以通过 CommandBuilder 设置
            debug!("Creating session with cwd: {}", cwd);
        }

        // 创建 PTY 会话
        let session = PtySession::new(&pty_config)?;
        let session_id = session.id();

        // 启动输出读取任务
        let session_id_for_task = session_id;
        let event_tx_for_task = event_tx.clone();
        let state_for_task = session.state().clone();

        tokio::spawn(async move {
            let mut _last_output: Vec<u8> = Vec::new();
            loop {
                tokio::time::sleep(tokio::time::Duration::from_millis(16)).await;

                // 获取当前状态
                let _state = state_for_task.lock().await;
                // 检测变化并生成事件
                // 这里简化处理：定期发送事件
                drop(_state);

                // 实际实现应该使用更高效的变化检测
            }
        });

        // 添加到会话列表
        sessions.insert(session_id, Arc::new(session));

        // 发送会话创建事件
        let _ = event_tx.send(ServerEvent::SessionCreated(session_id));

        info!("Created new session: {}", session_id);

        Ok(session_id)
    }

    // 启动事件处理器
    async fn start_event_handler(&self) {
        let mut rx = self.event_tx.subscribe();
        let sessions = self.sessions.clone();
        let clients = self.clients.clone();

        tokio::spawn(async move {
            while let Ok(event) = rx.recv().await {
                match event {
                    ServerEvent::SessionOutput(session_id, data) => {
                        // 处理会话输出，生成帧并广播
                        Self::broadcast_session_output(session_id, data, &sessions, &clients).await;
                    }
                    ServerEvent::SessionCreated(session_id) => {
                        info!("Session created: {:?}", session_id);
                    }
                    ServerEvent::SessionClosed(session_id) => {
                        info!("Session closed: {:?}", session_id);
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

    // 广播会话输出
    async fn broadcast_session_output(
        session_id: PtySessionId,
        _data: Vec<u8>,
        sessions: &Arc<DashMap<PtySessionId, Arc<PtySession>>>,
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
    ) {
        // 获取会话
        if let Some(session_entry) = sessions.get(&session_id) {
            let session = session_entry.value();

            // 使用渲染器生成增量帧
            let (cols, rows) = session.size();
            let (cells, cursor) = session.state_snapshot().await;

            // 使用渲染器
            let mut renderer = session.renderer().lock().await;
            let (seq, dirty_regions, cursor_frame) = renderer.render(&cells, cursor);

            // 构建 ScreenFrame
            let screen_frame = crate::protocol::ScreenFrame {
                seq,
                cols,
                rows,
                dirty_regions,
            };

            // 广播到所有订阅的客户端
            let frame = Frame::SessionOutput(session_id.as_string(), screen_frame);
            let binary_data = crate::protocol::encode_frame(&frame);

            // 收集需要发送的客户端 ID
            let target_client_ids: Vec<ClientId> = {
                let clients_guard = clients.lock().await;
                clients_guard
                    .iter()
                    .filter(|c| c.subscribed_sessions.contains(&session_id))
                    .map(|c| c.id)
                    .collect()
            };

            // 发送消息到订阅的客户端
            {
                let mut clients_guard = clients.lock().await;
                for client_id in target_client_ids.iter() {
                    if let Some(client) = clients_guard.iter_mut().find(|c| c.id == *client_id) {
                        let _ = client.sender.send(Message::Binary(binary_data.clone().into())).await;
                    }
                }
            }

            // 如果光标有变化，也发送光标更新
            if let Some(cursor_frm) = cursor_frame {
                let cursor_update = Frame::CursorUpdate(cursor_frm);
                let cursor_data = crate::protocol::encode_frame(&cursor_update);

                let mut clients_guard = clients.lock().await;
                for client_id in target_client_ids.iter() {
                    if let Some(client) = clients_guard.iter_mut().find(|c| c.id == *client_id) {
                        let _ = client.sender.send(Message::Binary(cursor_data.clone().into())).await;
                    }
                }
            }
        }
    }

    // 发送帧到指定客户端
    async fn send_to_client(client: &mut WebSocketClient, frame: &Frame) -> Result<()> {
        let binary_data = encode_frame(frame);
        client
            .sender
            .send(Message::Binary(binary_data.into()))
            .await
            .map_err(|e| anyhow::anyhow!("Failed to send to client: {}", e))
    }

    // 广播帧到所有订阅指定会话的客户端
    async fn broadcast_to_subscribers(
        clients: &Arc<Mutex<Vec<WebSocketClient>>>,
        session_id: PtySessionId,
        frame: &Frame,
    ) {
        let binary_data = encode_frame(frame);

        let mut clients = clients.lock().await;
        for client in clients.iter_mut() {
            if client.subscribed_sessions.contains(&session_id) {
                let _ = client
                    .sender
                    .send(Message::Binary(binary_data.clone().into()))
                    .await;
            }
        }
    }
}
