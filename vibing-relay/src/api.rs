//
//  api.rs
//  Vibe Relay Server
//
//  HTTP REST API - 用户认证和设备管理
//

use axum::{
    extract::{ConnectInfo, Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{delete, get, post},
    Json, Router,
};
use serde_json::json;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::auth::{self, ErrorResponse, LoginRequest, RegisterRequest};
use crate::AppState;

/// 登录频率限制：窗口期内最大尝试次数
const MAX_LOGIN_ATTEMPTS: u32 = 10;
/// 频率限制窗口期（秒）
const RATE_LIMIT_WINDOW_SECS: u64 = 300; // 5 分钟

/// 创建 API 路由
pub fn api_routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/auth/register", post(register_handler))
        .route("/auth/login", post(login_handler))
        .route("/auth/qr-generate", post(qr_generate_handler))
        .route("/auth/qr-login", post(qr_login_handler))
        .route("/auth/me", get(me_handler))
        .route("/sessions", get(list_sessions_handler))
        .route("/devices", get(list_devices_handler))
        .route("/devices/{device_id}", delete(delete_device_handler))
}

async fn register_handler(
    State(state): State<Arc<AppState>>,
    Json(req): Json<RegisterRequest>,
) -> impl IntoResponse {
    // Argon2 hashing is CPU-intensive — run off the async executor
    let result = tokio::task::spawn_blocking({
        let state = state.clone();
        move || auth::register(&state.db, &state.jwt_secret, &req)
    })
    .await;

    match result {
        Ok(Ok(resp)) => (StatusCode::OK, Json(json!(resp))),
        Ok(Err(msg)) => (
            StatusCode::BAD_REQUEST,
            Json(json!(ErrorResponse { error: msg })),
        ),
        Err(_) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!(ErrorResponse { error: "Internal error".to_string() })),
        ),
    }
}

/// 登录（含频率限制）
async fn login_handler(
    State(state): State<Arc<AppState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(req): Json<LoginRequest>,
) -> impl IntoResponse {
    let ip = addr.ip().to_string();

    // 频率限制检查
    {
        let attempts = state.login_attempts.read().await;
        if let Some((count, first_time)) = attempts.get(&ip) {
            if first_time.elapsed() < Duration::from_secs(RATE_LIMIT_WINDOW_SECS)
                && *count >= MAX_LOGIN_ATTEMPTS
            {
                return (
                    StatusCode::TOO_MANY_REQUESTS,
                    Json(json!(ErrorResponse {
                        error: "Too many login attempts, try again later".to_string()
                    })),
                );
            }
        }
    }

    // Argon2 verification is CPU-intensive — run off the async executor
    let result = tokio::task::spawn_blocking({
        let state = state.clone();
        move || auth::login(&state.db, &state.jwt_secret, &req)
    })
    .await
    .unwrap_or_else(|_| Err("Internal error".to_string()));

    if result.is_err() {
        let mut attempts = state.login_attempts.write().await;
        let entry = attempts.entry(ip).or_insert((0, Instant::now()));
        if entry.1.elapsed() >= Duration::from_secs(RATE_LIMIT_WINDOW_SECS) {
            *entry = (1, Instant::now());
        } else {
            entry.0 += 1;
        }
    } else {
        // 登录成功，仅在有记录时才加写锁
        let has_entry = state.login_attempts.read().await.contains_key(&ip);
        if has_entry {
            state.login_attempts.write().await.remove(&ip);
        }
    }

    match result {
        Ok(resp) => (StatusCode::OK, Json(json!(resp))),
        Err(msg) => (
            StatusCode::UNAUTHORIZED,
            Json(json!(ErrorResponse { error: msg })),
        ),
    }
}

/// 获取当前用户信息
async fn me_handler(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = match extract_claims(&state.jwt_secret, &headers) {
        Some(c) => c,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!(ErrorResponse {
                    error: "Invalid or missing token".to_string()
                })),
            )
        }
    };

    match state.db.get_user_by_id(&claims.sub) {
        Ok(Some(user)) => (
            StatusCode::OK,
            Json(json!({
                "user_id": user.id,
                "username": user.username,
                "created_at": user.created_at,
                "last_login": user.last_login,
            })),
        ),
        _ => (
            StatusCode::NOT_FOUND,
            Json(json!(ErrorResponse {
                error: "User not found".to_string()
            })),
        ),
    }
}

/// 获取用户的活跃 relay sessions
async fn list_sessions_handler(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = match extract_claims(&state.jwt_secret, &headers) {
        Some(c) => c,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!(ErrorResponse {
                    error: "Invalid or missing token".to_string()
                })),
            )
        }
    };

    let us = state.user_sessions.read().await;
    let sessions = us.get(&claims.sub).cloned().unwrap_or_default();
    (StatusCode::OK, Json(json!(sessions)))
}

/// 获取用户的设备列表
async fn list_devices_handler(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = match extract_claims(&state.jwt_secret, &headers) {
        Some(c) => c,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!(ErrorResponse {
                    error: "Invalid or missing token".to_string()
                })),
            )
        }
    };

    match state.db.get_devices_by_user(&claims.sub) {
        Ok(mut devices) => {
            // 标记在线状态
            let online_devices = state.online_devices.read().await;
            for device in &mut devices {
                device.is_online = online_devices
                    .get(&claims.sub)
                    .map(|ids| ids.contains(&device.id))
                    .unwrap_or(false);
            }
            (StatusCode::OK, Json(json!(devices)))
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!(ErrorResponse {
                error: format!("Failed to fetch devices: {}", e)
            })),
        ),
    }
}

/// 删除设备
async fn delete_device_handler(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
) -> impl IntoResponse {
    let claims = match extract_claims(&state.jwt_secret, &headers) {
        Some(c) => c,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!(ErrorResponse {
                    error: "Invalid or missing token".to_string()
                })),
            )
        }
    };

    match state.db.delete_device(&device_id, &claims.sub) {
        Ok(true) => (StatusCode::OK, Json(json!({"deleted": true}))),
        Ok(false) => (
            StatusCode::NOT_FOUND,
            Json(json!(ErrorResponse {
                error: "Device not found".to_string()
            })),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!(ErrorResponse {
                error: format!("Failed to delete device: {}", e)
            })),
        ),
    }
}

/// 已登录用户生成 QR 登录码（供其他设备扫描）
async fn qr_generate_handler(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = match extract_claims(&state.jwt_secret, &headers) {
        Some(c) => c,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!(ErrorResponse {
                    error: "Invalid or missing token".to_string()
                })),
            )
        }
    };

    // 生成 16 字符随机码
    let code: String = (0..16)
        .map(|_| {
            let idx = rand::random::<usize>() % 36;
            b"abcdefghijklmnopqrstuvwxyz0123456789"[idx] as char
        })
        .collect();

    let qr_value = format!("VIBE_QR|{}", code);

    state
        .qr_tokens
        .write()
        .await
        .insert(code.clone(), (claims.sub.clone(), Instant::now()));

    (StatusCode::OK, Json(json!({
        "qr_code": qr_value,
        "expires_in": 300
    })))
}

/// QR 登录请求
#[derive(Debug, serde::Deserialize)]
struct QrLoginRequest {
    code: String,
    device_id: Option<String>,
    device_name: Option<String>,
    device_type: Option<String>,
}

/// 未登录设备用 QR 码换取 token
async fn qr_login_handler(
    State(state): State<Arc<AppState>>,
    Json(req): Json<QrLoginRequest>,
) -> impl IntoResponse {
    // 从 code 中提取实际的 token key
    let code = req.code.strip_prefix("VIBE_QR|").unwrap_or(&req.code);

    // 查找并消费 QR token（一次性使用）
    let user_id = {
        let mut tokens = state.qr_tokens.write().await;
        match tokens.remove(code) {
            Some((uid, created)) => {
                if created.elapsed() > Duration::from_secs(300) {
                    return (
                        StatusCode::BAD_REQUEST,
                        Json(json!(ErrorResponse {
                            error: "QR code has expired".to_string()
                        })),
                    );
                }
                uid
            }
            None => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!(ErrorResponse {
                        error: "Invalid or expired QR code".to_string()
                    })),
                );
            }
        }
    };

    // 查找用户
    let user = match state.db.get_user_by_id(&user_id) {
        Ok(Some(u)) => u,
        _ => {
            return (
                StatusCode::NOT_FOUND,
                Json(json!(ErrorResponse {
                    error: "User not found".to_string()
                })),
            );
        }
    };

    // 注册设备
    let device_id = if let Some(did) = &req.device_id {
        let name = req.device_name.as_deref().unwrap_or("Unknown Device");
        let dtype = req.device_type.as_deref().unwrap_or("unknown");
        let _ = state.db.upsert_device(did, &user.id, name, dtype, None);
        Some(did.clone())
    } else if let (Some(name), Some(dtype)) = (&req.device_name, &req.device_type) {
        let did = uuid::Uuid::new_v4().to_string();
        let _ = state.db.upsert_device(&did, &user.id, name, dtype, None);
        Some(did)
    } else {
        None
    };

    let _ = state.db.update_last_login(&user.id);

    match auth::generate_token(&state.jwt_secret, &user.id, &user.username, device_id.as_deref()) {
        Ok(token) => (
            StatusCode::OK,
            Json(json!({
                "token": token,
                "user_id": user.id,
                "username": user.username,
                "device_id": device_id,
            })),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!(ErrorResponse {
                error: format!("Failed to generate token: {}", e)
            })),
        ),
    }
}

fn extract_claims(jwt_secret: &str, headers: &HeaderMap) -> Option<auth::Claims> {
    let auth_header = headers.get("authorization")?.to_str().ok()?;
    let token = auth_header.strip_prefix("Bearer ")?;
    auth::verify_token(jwt_secret, token).ok()
}
