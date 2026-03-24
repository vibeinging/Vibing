//
//  protocol.rs
//  Vibe Relay Server
//
//  中继协议定义
//

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// 中继消息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelayMessage {
    #[serde(rename = "type")]
    pub type_: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub public_key: Option<String>,
}

impl Default for RelayMessage {
    fn default() -> Self {
        Self {
            type_: String::new(),
            error: None,
            data: None,
            session_id: None,
            role: None,
            public_key: None,
        }
    }
}

/// 客户端握手消息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientHandshake {
    #[serde(rename = "type")]
    pub type_: String,
    pub session_id: String,
    pub role: String, // "host" or "client"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub public_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub token: Option<String>,
}

/// 服务器欢迎消息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerHello {
    #[serde(rename = "type")]
    pub type_: String,
    pub server_fingerprint: String,
    pub timestamp: String,
}

/// 密钥交换消息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyExchange {
    #[serde(rename = "type")]
    pub type_: String,
    pub ephemeral_public: String,
    pub signing_public: String,
    pub signature: String, // 对 ephemeral_public 的签名
}

/// 连接状态消息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionStatus {
    #[serde(rename = "type")]
    pub type_: String,
    pub status: String, // "connected", "disconnected", "waiting"
}

/// 中继消息类型
#[derive(Debug, Clone, PartialEq)]
pub enum RelayMessageType {
    Handshake,
    Hello,
    KeyExchange,
    Data,
    Ping,
    Pong,
    PeerConnected,
    PeerDisconnected,
    Error,
}

impl RelayMessageType {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Handshake => "handshake",
            Self::Hello => "hello",
            Self::KeyExchange => "key_exchange",
            Self::Data => "data",
            Self::Ping => "ping",
            Self::Pong => "pong",
            Self::PeerConnected => "peer_connected",
            Self::PeerDisconnected => "peer_disconnected",
            Self::Error => "error",
        }
    }
}

/// 生成随机会话 ID
pub fn generate_session_id() -> String {
    use rand::Rng;
    const CHARSET: &[u8] = b"abcdefghjkmnpqrstuvwxyz23456789";
    let mut rng = rand::thread_rng();

    (0..16)
        .map(|_| {
            let idx = rng.gen_range(0..CHARSET.len());
            CHARSET[idx] as char
        })
        .collect()
}
