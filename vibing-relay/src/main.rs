//
//  main.rs
//  Vibe Relay Server
//
//  安全中继服务器 - 端到端加密的终端同步中继
//  HTTP REST API + WebSocket 统一服务
//

use axum::{
    extract::{
        ws::{Message as WsMessage, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
    routing::get,
    Router,
};
use clap::Parser;
use futures_util::{SinkExt, StreamExt};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::net::SocketAddr;
use std::sync::{Arc, LazyLock};
use tokio::sync::{mpsc, RwLock};
use tower_http::cors::CorsLayer;
use tracing::{debug, error, info};

mod admin;
mod api;
mod auth;
mod crypto;
mod db;
mod protocol;

use protocol::{ClientHandshake, RelayMessage, ServerHello};

static SERVER_FINGERPRINT: LazyLock<String> = LazyLock::new(|| {
    let mut hasher = Sha256::new();
    hasher.update(b"vibe-relay-v1");
    hex::encode(&hasher.finalize()[..8])
});

#[derive(Parser, Debug)]
#[command(name = "vibe-relay")]
#[command(about = "Vibe Relay Server - 安全的终端同步中继服务", long_about = None)]
struct Args {
    #[arg(short, long, default_value = "0.0.0.0:8766")]
    bind: String,

    #[arg(long, default_value = "info")]
    log: String,

    #[arg(long, default_value = "vibe-relay.db")]
    db: String,

    /// JWT signing secret (also reads VIBE_JWT_SECRET env var)
    #[arg(long, env = "VIBE_JWT_SECRET")]
    jwt_secret: Option<String>,

    /// Admin panel username
    #[arg(long, env = "VIBE_ADMIN_USER", default_value = "admin")]
    admin_user: String,

    /// Admin panel password (admin panel disabled if not set)
    #[arg(long, env = "VIBE_ADMIN_PASS")]
    admin_pass: Option<String>,
}

struct RelayState {
    sessions: HashMap<String, (mpsc::Sender<WsMessage>, Option<mpsc::Sender<WsMessage>>)>,
}

impl RelayState {
    fn new() -> Self {
        Self {
            sessions: HashMap::new(),
        }
    }

    fn register_host(&mut self, session_id: String, tx: mpsc::Sender<WsMessage>) -> bool {
        self.sessions.insert(session_id, (tx, None));
        true
    }

    fn register_client(
        &mut self,
        session_id: String,
        tx: mpsc::Sender<WsMessage>,
    ) -> Option<mpsc::Sender<WsMessage>> {
        if let Some((host_tx, client_tx)) = self.sessions.get_mut(&session_id) {
            if client_tx.is_some() {
                return None;
            }
            *client_tx = Some(tx);
            Some(host_tx.clone())
        } else {
            None
        }
    }

    fn remove_session(&mut self, session_id: &str) {
        self.sessions.remove(session_id);
    }
}

/// 用户的活跃 relay session
#[derive(Clone, serde::Serialize)]
pub struct UserSession {
    pub session_id: String,
    pub device_id: String,
    pub device_name: String,
    pub role: String,
    pub created_at: String,
}

pub struct AppState {
    pub db: db::Database,
    pub jwt_secret: String,
    pub admin_user: String,
    pub admin_pass: Option<String>,
    relay: RwLock<RelayState>,
    pub online_devices: RwLock<HashMap<String, HashSet<String>>>,
    pub login_attempts: RwLock<HashMap<String, (u32, std::time::Instant)>>,
    pub qr_tokens: RwLock<HashMap<String, (String, std::time::Instant)>>,
    /// user_id → 活跃 relay sessions
    pub user_sessions: RwLock<HashMap<String, Vec<UserSession>>>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    let log_level = match args.log.as_str() {
        "trace" => tracing::Level::TRACE,
        "debug" => tracing::Level::DEBUG,
        "info" => tracing::Level::INFO,
        "warn" => tracing::Level::WARN,
        "error" => tracing::Level::ERROR,
        _ => tracing::Level::INFO,
    };

    tracing_subscriber::fmt()
        .with_max_level(log_level)
        .init();

    info!("🔐 Vibe Relay Server starting...");
    info!("📡 Listening on: {}", args.bind);
    info!("🗄️  Database: {}", args.db);

    let database = db::Database::open(&args.db)?;
    info!("✅ Database initialized");

    let jwt_secret = args.jwt_secret.unwrap_or_else(|| {
        let secret: String = (0..64)
            .map(|_| {
                let idx = rand::random::<usize>() % 62;
                b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[idx] as char
            })
            .collect();
        tracing::warn!("⚠️  No JWT secret provided, using random secret (tokens won't survive restart)");
        tracing::warn!("   Set --jwt-secret or VIBE_JWT_SECRET for persistence");
        secret
    });

    if args.admin_pass.is_some() {
        info!("🔑 Admin panel enabled (user: {})", args.admin_user);
    } else {
        info!("ℹ️  Admin panel disabled (set --admin-pass to enable)");
    }

    let state = Arc::new(AppState {
        db: database,
        jwt_secret,
        admin_user: args.admin_user,
        admin_pass: args.admin_pass,
        relay: RwLock::new(RelayState::new()),
        online_devices: RwLock::new(HashMap::new()),
        login_attempts: RwLock::new(HashMap::new()),
        qr_tokens: RwLock::new(HashMap::new()),
        user_sessions: RwLock::new(HashMap::new()),
    });

    // 定期清理过期的 login_attempts (每 10 分钟)
    {
        let state = state.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(600));
            loop {
                interval.tick().await;
                let cutoff = std::time::Duration::from_secs(300);
                let mut attempts = state.login_attempts.write().await;
                attempts.retain(|_, (_, first_time)| first_time.elapsed() < cutoff);
                drop(attempts);

                let mut qr = state.qr_tokens.write().await;
                qr.retain(|_, (_, created)| created.elapsed() < cutoff);
            }
        });
    }

    use axum::http::{HeaderValue, Method};
    use tower_http::cors::AllowOrigin;

    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::predicate(|origin: &HeaderValue, _| {
            if let Ok(s) = origin.to_str() {
                s.starts_with("http://localhost") || s.starts_with("http://127.0.0.1")
                    || s.starts_with("https://localhost") || s.starts_with("https://127.0.0.1")
            } else {
                false
            }
        }))
        .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
        .allow_headers([axum::http::header::AUTHORIZATION, axum::http::header::CONTENT_TYPE]);

    let relay_routes = Router::new()
        .route("/ws", get(ws_handler))
        .route("/health", get(health_handler))
        .merge(api::api_routes())
        .merge(admin::admin_routes());

    let app = Router::new()
        .nest("/relay", relay_routes)
        .layer(cors)
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(&args.bind).await?;
    info!("✅ Server ready");

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    ).await?;

    Ok(())
}

async fn health_handler() -> impl IntoResponse {
    axum::Json(serde_json::json!({
        "status": "ok",
        "server": "vibe-relay",
        "version": "0.2.0"
    }))
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_connection(socket, state))
}

async fn handle_connection(socket: WebSocket, state: Arc<AppState>) {
    if let Err(e) = handle_connection_inner(socket, state).await {
        error!("Connection error: {}", e);
    }
}

fn make_error_msg(error: &str) -> RelayMessage {
    RelayMessage {
        type_: "error".to_string(),
        error: Some(error.to_string()),
        ..Default::default()
    }
}

async fn send_error(
    ws: &mut futures_util::stream::SplitSink<WebSocket, WsMessage>,
    error: &str,
) -> anyhow::Result<()> {
    let msg = make_error_msg(error);
    ws.send(WsMessage::Text(serde_json::to_string(&msg)?.into())).await?;
    Ok(())
}

async fn handle_connection_inner(
    socket: WebSocket,
    state: Arc<AppState>,
) -> anyhow::Result<()> {
    let (mut ws_sender, mut ws_receiver) = socket.split();
    let (tx, mut rx) = mpsc::channel::<WsMessage>(100);

    let mut session_id: Option<String> = None;
    let mut peer_tx: Option<mpsc::Sender<WsMessage>> = None;
    let mut authenticated_user: Option<(String, String)> = None;

    info!("WebSocket connected");

    loop {
        tokio::select! {
            msg_result = ws_receiver.next() => {
                match msg_result {
                    Some(Ok(msg)) => {
                        match msg {
                            WsMessage::Text(text) => {
                                // 尝试单次解析为 ClientHandshake（包含 RelayMessage 的所有字段）
                                if let Ok(handshake) = serde_json::from_str::<ClientHandshake>(&text) {
                                    if handshake.type_ == "handshake" {
                                        // Token 必须提供
                                        let token = match &handshake.token {
                                            Some(t) => t.clone(),
                                            None => {
                                                send_error(&mut ws_sender, "Authentication required: token missing").await?;
                                                break;
                                            }
                                        };

                                        let claims = match auth::verify_token(&state.jwt_secret, &token) {
                                            Ok(c) => c,
                                            Err(e) => {
                                                send_error(&mut ws_sender, &format!("Authentication failed: {}", e)).await?;
                                                break;
                                            }
                                        };

                                        let device_id = claims.device_id.clone().unwrap_or_default();
                                        authenticated_user = Some((claims.sub.clone(), device_id.clone()));

                                        if !device_id.is_empty() {
                                            let mut online = state.online_devices.write().await;
                                            online.entry(claims.sub.clone())
                                                .or_insert_with(HashSet::new)
                                                .insert(device_id.clone());
                                            // DB write in blocking context to avoid starving tokio
                                            let db_device_id = device_id.clone();
                                            let db = &state.db;
                                            let _ = db.update_device_last_seen(&db_device_id);
                                        }

                                        info!("Authenticated: user={}, device={}", claims.sub, device_id);

                                        let sid = handshake.session_id.clone();

                                        if validate_session_id(&sid) {
                                            if handshake.role == "host" {
                                                session_id = Some(sid.clone());

                                                let hello = ServerHello {
                                                    type_: "hello".to_string(),
                                                    server_fingerprint: SERVER_FINGERPRINT.clone(),
                                                    timestamp: chrono::Utc::now().to_rfc3339(),
                                                };
                                                ws_sender.send(WsMessage::Text(serde_json::to_string(&hello)?.into())).await?;

                                                state.relay.write().await.register_host(sid.clone(), tx.clone());

                                                // 记录 user → session 映射
                                                {
                                                    let entry = UserSession {
                                                        session_id: sid.clone(),
                                                        device_id: device_id.clone(),
                                                        device_name: String::new(),
                                                        role: "host".to_string(),
                                                        created_at: chrono::Utc::now().to_rfc3339(),
                                                    };
                                                    let mut us = state.user_sessions.write().await;
                                                    us.entry(claims.sub.clone()).or_default().push(entry);
                                                }

                                                info!("Host registered: {} (user={})", sid, claims.sub);
                                            } else if handshake.role == "client" {
                                                if let Some(host_tx) = state.relay.write().await.register_client(sid.clone(), tx.clone()) {
                                                    session_id = Some(sid.clone());
                                                    peer_tx = Some(host_tx.clone());

                                                    let connected = RelayMessage {
                                                        type_: "peer_connected".to_string(),
                                                        ..Default::default()
                                                    };
                                                    let _ = host_tx.send(WsMessage::Text(serde_json::to_string(&connected)?.into())).await;

                                                    info!("Client connected: {}", sid);
                                                } else {
                                                    send_error(&mut ws_sender, "Session not found").await?;
                                                }
                                            }
                                        } else {
                                            send_error(&mut ws_sender, "Invalid session ID").await?;
                                        }
                                        continue;
                                    }
                                }

                                // 非 handshake 消息
                                if let Ok(relay_msg) = serde_json::from_str::<RelayMessage>(&text) {
                                    if relay_msg.type_ == "ping" {
                                        let pong = RelayMessage {
                                            type_: "pong".to_string(),
                                            ..Default::default()
                                        };
                                        ws_sender.send(WsMessage::Text(serde_json::to_string(&pong)?.into())).await?;
                                        continue;
                                    }
                                }

                                // 其他文本消息转发给对端
                                if let Some(ref pt) = peer_tx {
                                    let _ = pt.send(WsMessage::Text(text)).await;
                                }
                            }
                            WsMessage::Binary(data) => {
                                if let Some(ref pt) = peer_tx {
                                    debug!("Forwarding {} bytes", data.len());
                                    let _ = pt.send(WsMessage::Binary(data)).await;
                                }
                            }
                            WsMessage::Close(_) => {
                                info!("Client disconnected");
                                break;
                            }
                            WsMessage::Ping(data) => {
                                let _ = ws_sender.send(WsMessage::Pong(data)).await;
                            }
                            WsMessage::Pong(_) => {}
                        }
                    }
                    Some(Err(e)) => {
                        error!("WebSocket error: {}", e);
                        break;
                    }
                    None => break,
                }
            }

            Some(forward_msg) = rx.recv() => {
                if ws_sender.send(forward_msg).await.is_err() {
                    break;
                }
            }
        }
    }

    if let Some(ref sid) = session_id {
        state.relay.write().await.remove_session(sid);
    }

    if let Some((ref user_id, ref device_id)) = authenticated_user {
        // 清理 user_sessions
        if let Some(ref sid) = session_id {
            let mut us = state.user_sessions.write().await;
            if let Some(sessions) = us.get_mut(user_id) {
                sessions.retain(|s| s.session_id != *sid);
                if sessions.is_empty() {
                    us.remove(user_id);
                }
            }
        }

        // 清理 online_devices
        if !device_id.is_empty() {
            let mut online = state.online_devices.write().await;
            if let Some(devices) = online.get_mut(user_id) {
                devices.remove(device_id);
                if devices.is_empty() {
                    online.remove(user_id);
                }
            }
        }
    }

    Ok(())
}

fn validate_session_id(session_id: &str) -> bool {
    session_id.len() == 16 && session_id.chars().all(|c| c.is_alphanumeric())
}
