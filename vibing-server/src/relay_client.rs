//
//  relay_client.rs
//  Vibe Terminal Server
//
//  中继客户端 - 桌面端通过中继服务器与移动端连接
//

use anyhow::{Context, Result};
use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, error, info, warn};

// ========== 协议消息 ==========

#[derive(Debug, Serialize, Deserialize)]
struct RelayHandshake {
    #[serde(rename = "type")]
    type_: String,
    session_id: String,
    role: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct RelayServerHello {
    #[serde(rename = "type")]
    type_: String,
    server_fingerprint: String,
    timestamp: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct RelayPeerConnected {
    #[serde(rename = "type")]
    type_: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct RelayError {
    #[serde(rename = "type")]
    type_: String,
    error: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct RelayPing {
    #[serde(rename = "type")]
    type_: String,
}

// ========== 中继客户端 ==========

pub struct RelayClient {
    relay_url: String,
    session_id: String,
    role: RelayRole,

    // 加密密钥（从 session_id 派生）
    encryption_key: Vec<u8>,

    // WebSocket
    ws_sender: Arc<Mutex<Option<mpsc::Sender<Message>>>>,

    // 对端连接状态
    peer_connected: Arc<Mutex<bool>>,

    // 接收通道
    data_rx: Arc<Mutex<Option<mpsc::Receiver<Vec<u8>>>>>,
}

#[derive(Clone, Copy)]
pub enum RelayRole {
    Host,
    Client,
}

impl RelayRole {
    fn as_str(&self) -> &'static str {
        match self {
            RelayRole::Host => "host",
            RelayRole::Client => "client",
        }
    }
}

impl RelayClient {
    /// 创建新的中继客户端
    pub fn new(relay_url: String, session_id: String, role: RelayRole) -> Result<Self> {
        // 验证 session_id 格式（16 字符字母数字）
        if session_id.len() != 16 || !session_id.chars().all(|c| c.is_alphanumeric()) {
            anyhow::bail!("Invalid session_id: must be 16 alphanumeric characters");
        }

        // 从 session_id 派生加密密钥
        let encryption_key = Self::derive_key(&session_id);

        info!(
            "Creating relay client: url={}, session={}, role={}",
            relay_url, session_id, role.as_str()
        );

        Ok(Self {
            relay_url,
            session_id,
            role,
            encryption_key,
            ws_sender: Arc::new(Mutex::new(None)),
            peer_connected: Arc::new(Mutex::new(false)),
            data_rx: Arc::new(Mutex::new(None)),
        })
    }

    /// 从 session_id 派生加密密钥（SHA256）
    fn derive_key(session_id: &str) -> Vec<u8> {
        let mut hasher = Sha256::new();
        hasher.update(b"vibe-terminal-v1"); // 上下文
        hasher.update(session_id.as_bytes());
        hasher.finalize().to_vec()
    }

    /// 连接到中继服务器
    pub async fn connect(&self) -> Result<()> {
        info!("Connecting to relay server: {}", self.relay_url);

        let (ws_stream, _) = connect_async(&self.relay_url)
            .await
            .context("Failed to connect to relay server")?;

        info!("WebSocket connected to relay");

        let (mut ws_sender, mut ws_receiver) = ws_stream.split();

        // 创建消息通道
        let (tx, mut rx) = mpsc::channel::<Message>(100);

        // 保存发送器
        *self.ws_sender.lock().await = Some(tx);

        // 创建数据接收通道
        let (data_tx, data_rx) = mpsc::channel::<Vec<u8>>(100);
        *self.data_rx.lock().await = Some(data_rx);

        // 发送握手
        let handshake = RelayHandshake {
            type_: "handshake".to_string(),
            session_id: self.session_id.clone(),
            role: self.role.as_str().to_string(),
        };

        let handshake_json = serde_json::to_string(&handshake)?;
        ws_sender
            .send(Message::Text(handshake_json.into()))
            .await
            .context("Failed to send handshake")?;

        debug!("Sent handshake to relay server");

        // 克隆需要的变量
        let peer_connected = self.peer_connected.clone();
        let encryption_key = self.encryption_key.clone();
        let session_id = self.session_id.clone();

        // 启动发送任务
        tokio::spawn(async move {
            while let Some(msg) = rx.recv().await {
                if ws_sender.send(msg).await.is_err() {
                    error!("Failed to send message to relay");
                    break;
                }
            }
        });

        // 启动接收任务
        tokio::spawn(async move {
            while let Some(msg_result) = ws_receiver.next().await {
                match msg_result {
                    Ok(Message::Text(text)) => {
                        if let Err(e) = Self::handle_text_message(
                            &text,
                            &peer_connected,
                            &session_id,
                        )
                        .await
                        {
                            warn!("Error handling text message: {}", e);
                        }
                    }
                    Ok(Message::Binary(data)) => {
                        if let Err(e) =
                            Self::handle_binary_message(&data, &encryption_key, &data_tx).await
                        {
                            warn!("Error handling binary message: {}", e);
                        }
                    }
                    Ok(Message::Close(_)) => {
                        info!("Relay server closed connection");
                        *peer_connected.lock().await = false;
                        break;
                    }
                    Err(e) => {
                        error!("WebSocket error: {}", e);
                        break;
                    }
                    _ => {}
                }
            }
        });

        Ok(())
    }

    /// 处理文本消息
    async fn handle_text_message(
        text: &str,
        peer_connected: &Arc<Mutex<bool>>,
        _session_id: &str,
    ) -> Result<()> {
        let json: serde_json::Value = serde_json::from_str(text)?;

        if let Some(msg_type) = json["type"].as_str() {
            match msg_type {
                "hello" => {
                    if let Some(fingerprint) = json["server_fingerprint"].as_str() {
                        info!("Relay server hello (fingerprint: {})", fingerprint);
                    }
                }
                "peer_connected" => {
                    info!("Peer connected via relay!");
                    *peer_connected.lock().await = true;
                }
                "error" => {
                    let error_msg = json["error"].as_str().unwrap_or("Unknown error");
                    warn!("Relay server error: {}", error_msg);
                }
                "pong" => {
                    debug!("Received pong from relay");
                }
                _ => {
                    debug!("Unknown message type: {}", msg_type);
                }
            }
        }

        Ok(())
    }

    /// 处理二进制消息（解密并转发）
    async fn handle_binary_message(
        data: &[u8],
        encryption_key: &[u8],
        data_tx: &mpsc::Sender<Vec<u8>>,
    ) -> Result<()> {
        // 解密数据
        let decrypted = Self::decrypt_data(data, encryption_key)?;

        // 发送到接收通道
        let _ = data_tx.send(decrypted).await;

        Ok(())
    }

    /// 加密数据（AES-256-GCM）
    fn encrypt_data(plaintext: &[u8], key: &[u8]) -> Result<Vec<u8>> {
        let cipher = Aes256Gcm::new_from_slice(key).context("Invalid key size")?;

        // 生成随机 nonce
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);

        // 加密
        let ciphertext = cipher
            .encrypt(&nonce, plaintext)
            .map_err(|e| anyhow::anyhow!("Encryption failed: {}", e))?;

        // 返回格式：nonce(12) + ciphertext
        let mut result = Vec::with_capacity(nonce.len() + ciphertext.len());
        result.extend_from_slice(&nonce);
        result.extend_from_slice(&ciphertext);

        Ok(result)
    }

    /// 解密数据
    fn decrypt_data(encrypted: &[u8], key: &[u8]) -> Result<Vec<u8>> {
        if encrypted.len() < 12 {
            anyhow::bail!("Encrypted data too short");
        }

        let cipher = Aes256Gcm::new_from_slice(key).context("Invalid key size")?;

        // 分离 nonce 和 ciphertext
        let (nonce_bytes, ciphertext) = encrypted.split_at(12);
        let nonce = Nonce::from_slice(nonce_bytes);

        // 解密
        let plaintext = cipher
            .decrypt(nonce, ciphertext)
            .map_err(|e| anyhow::anyhow!("Decryption failed: {}", e))?;

        Ok(plaintext)
    }

    /// 发送数据（加密后发送）
    pub async fn send_data(&self, data: &[u8]) -> Result<()> {
        // 检查对端是否已连接
        if !*self.peer_connected.lock().await {
            anyhow::bail!("Peer not connected");
        }

        // 加密数据
        let encrypted = Self::encrypt_data(data, &self.encryption_key)?;

        // 发送
        if let Some(sender) = self.ws_sender.lock().await.as_ref() {
            sender
                .send(Message::Binary(encrypted.into()))
                .await
                .context("Failed to send data to relay")?;
        } else {
            anyhow::bail!("WebSocket sender not available");
        }

        Ok(())
    }

    /// 接收数据（解密后）
    pub async fn recv_data(&self) -> Result<Vec<u8>> {
        if let Some(rx) = self.data_rx.lock().await.as_mut() {
            rx.recv()
                .await
                .ok_or_else(|| anyhow::anyhow!("Receive channel closed"))
        } else {
            anyhow::bail!("Receive channel not available");
        }
    }

    /// 检查对端是否已连接
    pub async fn is_peer_connected(&self) -> bool {
        *self.peer_connected.lock().await
    }

    /// 发送心跳 ping
    pub async fn send_ping(&self) -> Result<()> {
        let ping = RelayPing { type_: "ping".to_string() };
        let ping_json = serde_json::to_string(&ping)?;

        if let Some(sender) = self.ws_sender.lock().await.as_ref() {
            sender
                .send(Message::Text(ping_json.into()))
                .await
                .context("Failed to send ping")?;
        }

        Ok(())
    }

    /// 断开连接
    pub async fn disconnect(&self) -> Result<()> {
        *self.peer_connected.lock().await = false;
        *self.ws_sender.lock().await = None;
        Ok(())
    }

    /// 获取会话 ID
    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    /// 获取角色
    pub fn role(&self) -> RelayRole {
        self.role
    }
}
