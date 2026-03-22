//
//  main.rs
//  Vibe Relay Server
//
//  安全中继服务器 - 端到端加密的终端同步中继
//

use clap::Parser;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{RwLock, mpsc};
use tokio::net::TcpListener;
use tokio_tungstenite::tungstenite::Message;
use tracing::{info, error, debug};
use tracing_subscriber;

mod protocol;

use protocol::{RelayMessage, ClientHandshake, ServerHello};

#[derive(Parser, Debug)]
#[command(name = "vibe-relay")]
#[command(about = "Vibe Relay Server - 安全的终端同步中继服务", long_about = None)]
struct Args {
    #[arg(short, long, default_value = "0.0.0.0:8766")]
    bind: String,

    #[arg(long, default_value = "info")]
    log: String,
}

struct RelayState {
    sessions: HashMap<String, (mpsc::Sender<Message>, Option<mpsc::Sender<Message>>)>,
}

impl RelayState {
    fn new() -> Self {
        Self {
            sessions: HashMap::new(),
        }
    }

    fn register_host(&mut self, session_id: String, tx: mpsc::Sender<Message>) -> bool {
        self.sessions.insert(session_id.clone(), (tx, None));
        true
    }

    fn register_client(&mut self, session_id: String, tx: mpsc::Sender<Message>) -> Option<mpsc::Sender<Message>> {
        if let Some((host_tx, client_tx)) = self.sessions.get_mut(&session_id) {
            if client_tx.is_some() {
                return None;
            }
            *client_tx = Some(tx.clone());
            Some(host_tx.clone())
        } else {
            None
        }
    }

    fn remove_session(&mut self, session_id: &str) {
        self.sessions.remove(session_id);
    }
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
    info!("🔒 End-to-end encryption - Zero Knowledge");

    let state = Arc::new(RwLock::new(RelayState::new()));
    let listener = TcpListener::bind(&args.bind).await?;

    info!("✅ Server ready");

    loop {
        match listener.accept().await {
            Ok((stream, addr)) => {
                debug!("Connection from: {}", addr);
                let state = state.clone();

                tokio::spawn(async move {
                    if let Err(e) = handle_connection(stream, state).await {
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

async fn handle_connection(
    stream: tokio::net::TcpStream,
    state: Arc<RwLock<RelayState>>,
) -> anyhow::Result<()> {
    use futures_util::{SinkExt, StreamExt};

    let ws_stream = tokio_tungstenite::accept_async(stream).await?;
    let peer_addr = ws_stream.get_ref().peer_addr()?;
    info!("WebSocket connected: {}", peer_addr);

    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    let (tx, mut rx) = mpsc::channel::<Message>(100);

    let mut session_id: Option<String> = None;
    let mut peer_tx: Option<mpsc::Sender<Message>> = None;

    loop {
        tokio::select! {
            msg_result = ws_receiver.next() => {
                match msg_result {
                    Some(Ok(msg)) => {
                        // 处理不同类型的消息
                        if matches!(msg, Message::Text(_)) {
                            // 文本消息 - 需要特殊处理
                            if let Message::Text(text) = msg {
                                if let Ok(relay_msg) = serde_json::from_str::<RelayMessage>(&text) {
                                    match relay_msg.type_.as_str() {
                                        "handshake" => {
                                            if let Ok(handshake) = serde_json::from_str::<ClientHandshake>(&text) {
                                                let sid = handshake.session_id.clone();

                                                if validate_session_id(&sid) {
                                                    if handshake.role == "host" {
                                                        let sid_clone = sid.clone();
                                                        session_id = Some(sid_clone.clone());

                                                        let hello = ServerHello {
                                                            type_: "hello".to_string(),
                                                            server_fingerprint: get_server_fingerprint(),
                                                            timestamp: chrono::Utc::now().to_rfc3339(),
                                                        };
                                                        ws_sender.send(Message::Text(serde_json::to_string(&hello)?.into())).await?;

                                                        state.write().await.register_host(sid_clone, tx.clone());
                                                        info!("Host registered: {}", sid);
                                                    } else if handshake.role == "client" {
                                                        if let Some(host_tx) = state.write().await.register_client(sid.clone(), tx.clone()) {
                                                            session_id = Some(sid.clone());
                                                            peer_tx = Some(host_tx.clone());

                                                            let connected = RelayMessage {
                                                                type_: "peer_connected".to_string(),
                                                                ..Default::default()
                                                            };
                                                            let _ = host_tx.send(Message::Text(serde_json::to_string(&connected)?.into())).await;

                                                            info!("Client connected: {}", sid);
                                                        } else {
                                                            let error_msg = RelayMessage {
                                                                type_: "error".to_string(),
                                                                error: Some("Session not found".to_string()),
                                                                ..Default::default()
                                                            };
                                                            ws_sender.send(Message::Text(serde_json::to_string(&error_msg)?.into())).await?;
                                                        }
                                                    }
                                                } else {
                                                    let error_msg = RelayMessage {
                                                        type_: "error".to_string(),
                                                        error: Some("Invalid session ID".to_string()),
                                                        ..Default::default()
                                                    };
                                                    ws_sender.send(Message::Text(serde_json::to_string(&error_msg)?.into())).await?;
                                                }
                                            }
                                        }
                                        "ping" => {
                                            let pong = RelayMessage {
                                                type_: "pong".to_string(),
                                                ..Default::default()
                                            };
                                            ws_sender.send(Message::Text(serde_json::to_string(&pong)?.into())).await?;
                                        }
                                        _ => {
                                            // 其他 RelayMessage 类型，转发给对端
                                            if let Some(ref pt) = peer_tx {
                                                let _ = pt.send(Message::Text(text)).await;
                                            }
                                        }
                                    }
                                } else {
                                    // 非协议文本消息，转发
                                    if let Some(ref pt) = peer_tx {
                                        let _ = pt.send(Message::Text(text)).await;
                                    }
                                }
                            }
                        } else if matches!(msg, Message::Binary(_)) {
                            // 二进制消息
                            if let Message::Binary(data) = msg {
                                if let Some(ref pt) = peer_tx {
                                    debug!("Forwarding {} bytes", data.len());
                                    let _ = pt.send(Message::Binary(data)).await;
                                }
                            }
                        } else if matches!(msg, Message::Close(_)) {
                            if let Message::Close(_) = msg {
                                info!("Client disconnected: {}", peer_addr);
                                break;
                            }
                        } else if matches!(msg, Message::Ping(_)) {
                            ws_sender.send(Message::Pong(Default::default())).await?;
                        } else if matches!(msg, Message::Pong(_)) {
                            // Pong，忽略
                        } else if matches!(msg, Message::Frame(_)) {
                            // Frame，忽略
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

    if let Some(sid) = session_id {
        state.write().await.remove_session(&sid);
    }

    Ok(())
}

fn validate_session_id(session_id: &str) -> bool {
    session_id.len() == 16 && session_id.chars().all(|c| c.is_alphanumeric())
}

fn get_server_fingerprint() -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"vibe-relay-v1");
    hex::encode(&hasher.finalize()[..8])
}
