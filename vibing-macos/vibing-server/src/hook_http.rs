//
//  hook_http.rs
//  Vibing Server — Hook API HTTP Routes
//
//  Axum HTTP 服务器：SSE 事件流、input injection、auth 中间件
//

use std::convert::Infallible;
use std::sync::Arc;

use base64::Engine as _;
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::sse::{Event, Sse};
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::{Json, Router};
use dashmap::DashMap;
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;
use tokio_stream::wrappers::BroadcastStream;
use tokio_stream::StreamExt as _;
use tracing::{info, warn};

use crate::config::HookApiConfig;
use crate::hook_api::HookEvent;
use crate::pty::PtySessionId;
use crate::server::SessionData;

// ── App state ────────────────────────────────────────────────

#[derive(Clone)]
pub struct AppState {
    hook_tx: broadcast::Sender<HookEvent>,
    sessions: Arc<DashMap<PtySessionId, SessionData>>,
    auth_token: String,
}

// ── Auth middleware ───────────────────────────────────────────

/// 常量时间比较，防止时序攻击
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

fn check_auth(headers: &HeaderMap, expected_token: &str) -> Result<(), StatusCode> {
    let auth = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    let token = auth.strip_prefix("Bearer ").unwrap_or("");

    if constant_time_eq(token.as_bytes(), expected_token.as_bytes()) {
        Ok(())
    } else {
        // 故意不区分 "no token" 和 "wrong token"
        Err(StatusCode::UNAUTHORIZED)
    }
}

// ── Request/Response types ───────────────────────────────────

#[derive(Deserialize)]
pub struct EventFilter {
    filter: Option<String>,
}

#[derive(Deserialize)]
pub struct InputRequest {
    data: String,
}

#[derive(Serialize)]
struct SessionInfo {
    id: String,
}

#[derive(Serialize)]
struct StatusResponse {
    status: String,
    active_sessions: usize,
}

#[derive(Serialize)]
struct OkResponse {
    ok: bool,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

// ── Route handlers ───────────────────────────────────────────

/// GET /api/v1/events — SSE 事件流
async fn sse_events(
    headers: HeaderMap,
    State(state): State<AppState>,
    Query(params): Query<EventFilter>,
) -> Result<Sse<impl tokio_stream::Stream<Item = Result<Event, Infallible>>>, StatusCode> {
    check_auth(&headers, &state.auth_token)?;

    let rx = state.hook_tx.subscribe();
    let filter = params.filter;

    let stream = BroadcastStream::new(rx).filter_map(move |result: Result<HookEvent, _>| {
        match result {
            Ok(event) => {
                if let Some(ref f) = filter {
                    let event_type = event.event_type();
                    let allowed: Vec<&str> = f.split(',').map(|s| s.trim()).collect();
                    if !allowed.contains(&event_type) {
                        return None;
                    }
                }
                let json = serde_json::to_string(&event).ok()?;
                Some(Ok(Event::default().data(json)))
            }
            Err(_) => None,
        }
    });

    Ok(Sse::new(stream))
}

/// GET /api/v1/sessions — 列出活跃 session
async fn list_sessions(
    headers: HeaderMap,
    State(state): State<AppState>,
) -> Result<Json<Vec<SessionInfo>>, StatusCode> {
    check_auth(&headers, &state.auth_token)?;

    let sessions: Vec<SessionInfo> = state
        .sessions
        .iter()
        .map(|entry| SessionInfo {
            id: entry.key().as_string(),
        })
        .collect();

    Ok(Json(sessions))
}

/// GET /api/v1/status — 健康检查
async fn status(
    headers: HeaderMap,
    State(state): State<AppState>,
) -> Result<Json<StatusResponse>, StatusCode> {
    check_auth(&headers, &state.auth_token)?;

    Ok(Json(StatusResponse {
        status: "ok".to_string(),
        active_sessions: state.sessions.len(),
    }))
}

/// POST /api/v1/sessions/:id/input — 写入原始字节到 PTY stdin
async fn post_input(
    headers: HeaderMap,
    State(state): State<AppState>,
    Path(session_id): Path<String>,
    Json(body): Json<InputRequest>,
) -> Result<impl IntoResponse, StatusCode> {
    check_auth(&headers, &state.auth_token)?;

    let id = PtySessionId::parse(&session_id).map_err(|_| StatusCode::BAD_REQUEST)?;

    if let Some(entry) = state.sessions.get(&id) {
        let session = entry.session.lock().await;
        session
            .write(body.data.as_bytes())
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        Ok(Json(OkResponse { ok: true }))
    } else {
        Err(StatusCode::NOT_FOUND)
    }
}

/// POST /api/v1/sessions/:id/approve — 发送 "y\n"
async fn post_approve(
    headers: HeaderMap,
    State(state): State<AppState>,
    Path(session_id): Path<String>,
) -> Result<impl IntoResponse, StatusCode> {
    check_auth(&headers, &state.auth_token)?;

    let id = PtySessionId::parse(&session_id).map_err(|_| StatusCode::BAD_REQUEST)?;

    if let Some(entry) = state.sessions.get(&id) {
        let session = entry.session.lock().await;
        session
            .write(b"y\n")
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        info!("Hook API: approved session {}", session_id);
        Ok(Json(OkResponse { ok: true }))
    } else {
        Err(StatusCode::NOT_FOUND)
    }
}

/// POST /api/v1/sessions/:id/reject — 发送 "n\n"
async fn post_reject(
    headers: HeaderMap,
    State(state): State<AppState>,
    Path(session_id): Path<String>,
) -> Result<impl IntoResponse, StatusCode> {
    check_auth(&headers, &state.auth_token)?;

    let id = PtySessionId::parse(&session_id).map_err(|_| StatusCode::BAD_REQUEST)?;

    if let Some(entry) = state.sessions.get(&id) {
        let session = entry.session.lock().await;
        session
            .write(b"n\n")
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        info!("Hook API: rejected session {}", session_id);
        Ok(Json(OkResponse { ok: true }))
    } else {
        Err(StatusCode::NOT_FOUND)
    }
}

/// POST /api/v1/sessions/:id/command — 发送任意文本 + 回车
async fn post_command(
    headers: HeaderMap,
    State(state): State<AppState>,
    Path(session_id): Path<String>,
    Json(body): Json<InputRequest>,
) -> Result<impl IntoResponse, StatusCode> {
    check_auth(&headers, &state.auth_token)?;

    let id = PtySessionId::parse(&session_id).map_err(|_| StatusCode::BAD_REQUEST)?;

    if let Some(entry) = state.sessions.get(&id) {
        let session = entry.session.lock().await;
        let data = format!("{}\n", body.data);
        session
            .write(data.as_bytes())
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        Ok(Json(OkResponse { ok: true }))
    } else {
        Err(StatusCode::NOT_FOUND)
    }
}

// ── Exec endpoint ────────────────────────────────────────────

#[derive(Deserialize)]
pub struct ExecRequest {
    command: String,
    /// 超时毫秒，默认 30000 (30 秒)
    #[serde(default = "default_exec_timeout")]
    timeout_ms: u64,
    /// Shell prompt 检测模式（正则），默认匹配常见 shell prompt
    #[serde(default)]
    prompt_pattern: Option<String>,
}

fn default_exec_timeout() -> u64 {
    30000
}

#[derive(Serialize)]
struct ExecResponse {
    output: String,
    /// "completed" = 检测到 shell prompt 返回
    /// "timeout" = 超时
    /// "idle" = 无输出超过 idle 阈值
    status: String,
    elapsed_ms: u64,
}

/// POST /api/v1/sessions/:id/exec — 同步执行命令并返回输出
///
/// 流程：
/// 1. 注入 marker echo → 发送命令 → 注入结束 marker echo
/// 2. 监听 on_output 事件，收集两个 marker 之间的输出
/// 3. 超时或检测到结束 marker 后返回
async fn post_exec(
    headers: HeaderMap,
    State(state): State<AppState>,
    Path(session_id): Path<String>,
    Json(body): Json<ExecRequest>,
) -> Result<impl IntoResponse, StatusCode> {
    check_auth(&headers, &state.auth_token)?;

    let id = PtySessionId::parse(&session_id).map_err(|_| StatusCode::BAD_REQUEST)?;

    let entry = state.sessions.get(&id).ok_or(StatusCode::NOT_FOUND)?;

    // 生成唯一 marker 用于定界输出
    let marker_id: String = {
        use rand::Rng;
        rand::thread_rng()
            .sample_iter(&rand::distributions::Alphanumeric)
            .take(16)
            .map(char::from)
            .collect()
    };
    let start_marker = format!("__VIBING_EXEC_START_{}__", marker_id);
    let end_marker = format!("__VIBING_EXEC_END_{}__", marker_id);

    // 订阅 hook 事件流
    let mut rx = state.hook_tx.subscribe();
    let session_id_str = session_id.clone();

    // 注入命令序列：echo start_marker → 实际命令 → echo end_marker
    {
        let session = entry.session.lock().await;
        let inject = format!(
            "echo '{}'; {} ; echo '{}'\n",
            start_marker, body.command, end_marker
        );
        session
            .write(inject.as_bytes())
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    }
    drop(entry);

    // 收集输出直到看到 end_marker 或超时
    let timeout = tokio::time::Duration::from_millis(body.timeout_ms);
    let start_time = tokio::time::Instant::now();
    let mut raw_output = String::new();
    let mut capturing = false;
    let mut status = "timeout".to_string();

    let result = tokio::time::timeout(timeout, async {
        loop {
            match rx.recv().await {
                Ok(HookEvent::Output { session_id: sid, data_base64, .. }) => {
                    if sid != session_id_str {
                        continue;
                    }
                    let bytes = base64::Engine::decode(
                        &base64::engine::general_purpose::STANDARD,
                        &data_base64,
                    )
                    .unwrap_or_default();
                    let text = String::from_utf8_lossy(&bytes);

                    // 去除 ANSI 转义码
                    let clean = {
                        let re = regex::Regex::new(
                            r"\x1b\[[0-9;]*[a-zA-Z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"
                        ).unwrap();
                        re.replace_all(&text, "").to_string()
                    };

                    if !capturing {
                        // 等待 start marker
                        if let Some(pos) = clean.find(&start_marker) {
                            capturing = true;
                            // 取 start marker 之后的部分
                            let after = &clean[pos + start_marker.len()..];
                            if let Some(end_pos) = after.find(&end_marker) {
                                raw_output.push_str(&after[..end_pos]);
                                status = "completed".to_string();
                                return;
                            }
                            raw_output.push_str(after);
                        }
                    } else {
                        // 已经在捕获，检查 end marker
                        if let Some(end_pos) = clean.find(&end_marker) {
                            raw_output.push_str(&clean[..end_pos]);
                            status = "completed".to_string();
                            return;
                        }
                        raw_output.push_str(&clean);
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    status = "closed".to_string();
                    return;
                }
                _ => continue,
            }
        }
    })
    .await;

    if result.is_err() {
        status = "timeout".to_string();
    }

    let elapsed = start_time.elapsed().as_millis() as u64;

    // 清理输出：去除首尾空行、marker echo 本身的行
    let output = raw_output
        .lines()
        .filter(|line| !line.contains(&start_marker) && !line.contains(&end_marker))
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_string();

    Ok(Json(ExecResponse {
        output,
        status,
        elapsed_ms: elapsed,
    }))
}

// ── Server creation ──────────────────────────────────────────

pub fn create_router(
    config: &HookApiConfig,
    hook_tx: broadcast::Sender<HookEvent>,
    sessions: Arc<DashMap<PtySessionId, SessionData>>,
) -> Router {
    let state = AppState {
        hook_tx,
        sessions,
        auth_token: config.token.clone().unwrap_or_default(),
    };

    Router::new()
        .route("/api/v1/events", get(sse_events))
        .route("/api/v1/sessions", get(list_sessions))
        .route("/api/v1/status", get(status))
        .route("/api/v1/sessions/:id/input", post(post_input))
        .route("/api/v1/sessions/:id/approve", post(post_approve))
        .route("/api/v1/sessions/:id/reject", post(post_reject))
        .route("/api/v1/sessions/:id/command", post(post_command))
        .route("/api/v1/sessions/:id/exec", post(post_exec))
        .with_state(state)
}

/// 启动 Hook API HTTP 服务器
pub async fn start_server(
    config: &HookApiConfig,
    hook_tx: broadcast::Sender<HookEvent>,
    sessions: Arc<DashMap<PtySessionId, SessionData>>,
) {
    // ── 安全检查 ──
    // 1. Token 必须存在且足够长
    let token = config.token.as_deref().unwrap_or("");
    if token.is_empty() {
        warn!("Hook API DISABLED: no auth token configured. This is a security requirement.");
        return;
    }
    if token.len() < 16 {
        warn!("Hook API DISABLED: auth token too short (minimum 16 characters).");
        return;
    }

    // 2. 非 localhost 绑定时强制警告
    let bind_addr = &config.bind;
    if !bind_addr.starts_with("127.0.0.1") && !bind_addr.starts_with("localhost") {
        warn!("⚠️  Hook API is binding to {} — this exposes PTY read/write to the network!", bind_addr);
        warn!("⚠️  Only do this if you understand the security implications.");
        warn!("⚠️  Ensure your firewall restricts access to this port.");
    }

    let router = create_router(config, hook_tx, sessions);

    let listener = match tokio::net::TcpListener::bind(bind_addr).await {
        Ok(l) => l,
        Err(e) => {
            warn!("Failed to bind Hook API on {}: {}", bind_addr, e);
            return;
        }
    };

    info!("Hook API listening on {}", bind_addr);

    if let Err(e) = axum::serve(listener, router).await {
        warn!("Hook API server error: {}", e);
    }
}
