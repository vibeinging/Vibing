//
//  admin.rs
//  Vibe Relay Server
//
//  管理后台 — HTTP Basic Auth + 内嵌 HTML
//

use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::{Html, IntoResponse, Redirect},
    routing::{get, post},
    Form, Router,
};
use serde::Deserialize;
use std::sync::Arc;

use crate::AppState;

/// 管理后台路由
pub fn admin_routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/admin", get(dashboard))
        .route("/admin/users", get(users_page))
        .route("/admin/users/disable", post(disable_user))
        .route("/admin/users/enable", post(enable_user))
        .route("/admin/users/delete", post(delete_user))
        .route("/admin/invites", get(invites_page))
        .route("/admin/invites/create", post(create_invite))
        .route("/admin/invites/delete", post(delete_invite))
}

// ---- Auth ----

fn check_admin(state: &AppState, headers: &HeaderMap) -> Result<(), StatusCode> {
    let admin_pass = match &state.admin_pass {
        Some(p) => p,
        None => return Err(StatusCode::FORBIDDEN),
    };

    let auth_header = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    if !auth_header.starts_with("Basic ") {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let decoded = base64_decode(&auth_header[6..]).map_err(|_| StatusCode::UNAUTHORIZED)?;
    let parts: Vec<&str> = decoded.splitn(2, ':').collect();
    if parts.len() != 2 {
        return Err(StatusCode::UNAUTHORIZED);
    }

    if parts[0] == state.admin_user && parts[1] == admin_pass {
        Ok(())
    } else {
        Err(StatusCode::UNAUTHORIZED)
    }
}

fn base64_decode(input: &str) -> Result<String, ()> {
    use base64::Engine;
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(input)
        .map_err(|_| ())?;
    String::from_utf8(bytes).map_err(|_| ())
}

fn unauthorized() -> impl IntoResponse {
    (
        StatusCode::UNAUTHORIZED,
        [("WWW-Authenticate", "Basic realm=\"Vibing Admin\"")],
        "Unauthorized",
    )
}

// ---- Pages ----

async fn dashboard(State(state): State<Arc<AppState>>, headers: HeaderMap) -> impl IntoResponse {
    if let Err(_) = check_admin(&state, &headers) {
        return unauthorized().into_response();
    }

    let user_count = state.db.user_count().unwrap_or(0);
    let invite_count = state.db.invite_code_count().unwrap_or(0);
    let online_count = {
        let online = state.online_devices.read().await;
        online.values().map(|v| v.len()).sum::<usize>()
    };

    let html = format!(r#"<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Vibing Admin</title>{CSS}</head>
<body>
<div class="container">
    <h1>🖥 Vibing Admin</h1>
    <nav>
        <a href="/relay/admin" class="active">Dashboard</a>
        <a href="/relay/admin/users">Users</a>
        <a href="/relay/admin/invites">Invite Codes</a>
    </nav>
    <div class="stats">
        <div class="stat"><span class="num">{user_count}</span><span class="label">Users</span></div>
        <div class="stat"><span class="num">{online_count}</span><span class="label">Online</span></div>
        <div class="stat"><span class="num">{invite_count}</span><span class="label">Active Invites</span></div>
    </div>
</div>
</body></html>"#);

    Html(html).into_response()
}

async fn users_page(State(state): State<Arc<AppState>>, headers: HeaderMap) -> impl IntoResponse {
    if let Err(_) = check_admin(&state, &headers) {
        return unauthorized().into_response();
    }

    let users = state.db.list_all_users().unwrap_or_default();
    let online_devices = state.online_devices.read().await;

    let mut rows = String::new();
    for user in &users {
        let is_online = online_devices.contains_key(&user.id);
        let status_badge = match user.status.as_str() {
            "disabled" => r#"<span class="badge red">Disabled</span>"#,
            _ => if is_online { r#"<span class="badge green">Online</span>"# } else { r#"<span class="badge gray">Offline</span>"# },
        };
        let actions = if user.status == "disabled" {
            format!(r#"<form method="post" action="/relay/admin/users/enable" style="display:inline"><input type="hidden" name="user_id" value="{}"><button class="btn-sm green">Enable</button></form>"#, user.id)
        } else {
            format!(r#"<form method="post" action="/relay/admin/users/disable" style="display:inline"><input type="hidden" name="user_id" value="{}"><button class="btn-sm yellow">Disable</button></form>"#, user.id)
        };
        let delete = format!(r#"<form method="post" action="/relay/admin/users/delete" style="display:inline" onsubmit="return confirm('Delete user {}?')"><input type="hidden" name="user_id" value="{}"><button class="btn-sm red">Delete</button></form>"#, user.username, user.id);

        rows.push_str(&format!(
            "<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{} {}</td></tr>",
            user.id, user.username, status_badge,
            &user.created_at[..10],
            user.last_login.as_deref().map(|s| &s[..10]).unwrap_or("-"),
            actions, delete,
        ));
    }

    let html = format!(r#"<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Users - Vibing Admin</title>{CSS}</head>
<body>
<div class="container">
    <h1>👥 Users ({count})</h1>
    <nav>
        <a href="/relay/admin">Dashboard</a>
        <a href="/relay/admin/users" class="active">Users</a>
        <a href="/relay/admin/invites">Invite Codes</a>
    </nav>
    <table>
        <tr><th>ID</th><th>Username</th><th>Status</th><th>Created</th><th>Last Login</th><th>Actions</th></tr>
        {rows}
    </table>
</div>
</body></html>"#, count = users.len());

    Html(html).into_response()
}

async fn invites_page(State(state): State<Arc<AppState>>, headers: HeaderMap) -> impl IntoResponse {
    if let Err(_) = check_admin(&state, &headers) {
        return unauthorized().into_response();
    }

    let codes = state.db.list_invite_codes().unwrap_or_default();

    let mut rows = String::new();
    for code in &codes {
        let status = if code.use_count >= code.max_uses {
            r#"<span class="badge red">Used</span>"#
        } else {
            r#"<span class="badge green">Active</span>"#
        };
        let delete = format!(r#"<form method="post" action="/relay/admin/invites/delete" style="display:inline"><input type="hidden" name="code" value="{}"><button class="btn-sm red">Delete</button></form>"#, code.code);

        rows.push_str(&format!(
            "<tr><td><code>{}</code></td><td>{}</td><td>{}/{}</td><td>{}</td><td>{}</td><td>{}</td></tr>",
            code.code, status, code.use_count, code.max_uses,
            &code.created_at[..10],
            code.used_by.as_deref().unwrap_or("-"),
            delete,
        ));
    }

    let html = format!(r#"<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Invites - Vibing Admin</title>{CSS}</head>
<body>
<div class="container">
    <h1>🎫 Invite Codes ({count})</h1>
    <nav>
        <a href="/relay/admin">Dashboard</a>
        <a href="/relay/admin/users">Users</a>
        <a href="/relay/admin/invites" class="active">Invite Codes</a>
    </nav>
    <form method="post" action="/relay/admin/invites/create" class="create-form">
        <input type="number" name="max_uses" value="1" min="1" max="100" style="width:60px">
        <button class="btn green">Generate Invite Code</button>
    </form>
    <table>
        <tr><th>Code</th><th>Status</th><th>Uses</th><th>Created</th><th>Used By</th><th>Actions</th></tr>
        {rows}
    </table>
</div>
</body></html>"#, count = codes.len());

    Html(html).into_response()
}

// ---- Actions ----

#[derive(Deserialize)]
struct UserAction {
    user_id: String,
}

#[derive(Deserialize)]
struct InviteAction {
    code: Option<String>,
    max_uses: Option<i32>,
}

async fn disable_user(State(state): State<Arc<AppState>>, headers: HeaderMap, Form(form): Form<UserAction>) -> impl IntoResponse {
    if let Err(e) = check_admin(&state, &headers) { return e.into_response(); }
    let _ = state.db.set_user_status(&form.user_id, "disabled");
    Redirect::to("/relay/admin/users").into_response()
}

async fn enable_user(State(state): State<Arc<AppState>>, headers: HeaderMap, Form(form): Form<UserAction>) -> impl IntoResponse {
    if let Err(e) = check_admin(&state, &headers) { return e.into_response(); }
    let _ = state.db.set_user_status(&form.user_id, "active");
    Redirect::to("/relay/admin/users").into_response()
}

async fn delete_user(State(state): State<Arc<AppState>>, headers: HeaderMap, Form(form): Form<UserAction>) -> impl IntoResponse {
    if let Err(e) = check_admin(&state, &headers) { return e.into_response(); }
    let _ = state.db.delete_user(&form.user_id);
    Redirect::to("/relay/admin/users").into_response()
}

async fn create_invite(State(state): State<Arc<AppState>>, headers: HeaderMap, Form(form): Form<InviteAction>) -> impl IntoResponse {
    if let Err(e) = check_admin(&state, &headers) { return e.into_response(); }

    let code = generate_invite_code();
    let max_uses = form.max_uses.unwrap_or(1);
    let _ = state.db.create_invite_code(&code, &state.admin_user, max_uses);
    Redirect::to("/relay/admin/invites").into_response()
}

async fn delete_invite(State(state): State<Arc<AppState>>, headers: HeaderMap, Form(form): Form<InviteAction>) -> impl IntoResponse {
    if let Err(e) = check_admin(&state, &headers) { return e.into_response(); }
    if let Some(code) = &form.code {
        let _ = state.db.delete_invite_code(code);
    }
    Redirect::to("/relay/admin/invites").into_response()
}

fn generate_invite_code() -> String {
    let chars: Vec<char> = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars().collect();
    (0..8)
        .map(|_| chars[rand::random::<usize>() % chars.len()])
        .collect()
}

// ---- CSS ----

const CSS: &str = r#"<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, system-ui, sans-serif; background: #0f0f13; color: #e0e0e0; }
.container { max-width: 900px; margin: 0 auto; padding: 32px 24px; }
h1 { font-size: 24px; margin-bottom: 16px; color: #fff; }
nav { display: flex; gap: 8px; margin-bottom: 24px; }
nav a { padding: 8px 16px; border-radius: 8px; text-decoration: none; color: #888; background: #1a1a22; font-size: 14px; }
nav a.active { background: #6ac278; color: #fff; }
nav a:hover { background: #252530; }
.stats { display: flex; gap: 16px; margin-bottom: 24px; }
.stat { flex: 1; background: #1a1a22; border-radius: 12px; padding: 20px; text-align: center; border: 1px solid #ffffff08; }
.stat .num { display: block; font-size: 32px; font-weight: bold; color: #6ac278; }
.stat .label { font-size: 13px; color: #888; margin-top: 4px; }
table { width: 100%; border-collapse: collapse; background: #1a1a22; border-radius: 12px; overflow: hidden; }
th { text-align: left; padding: 12px 14px; background: #15151d; color: #888; font-size: 12px; text-transform: uppercase; }
td { padding: 10px 14px; border-top: 1px solid #ffffff06; font-size: 13px; }
code { background: #252530; padding: 2px 8px; border-radius: 4px; font-size: 13px; color: #6ac278; }
.badge { padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 600; }
.badge.green { background: #6ac27822; color: #6ac278; }
.badge.red { background: #e0505022; color: #e05050; }
.badge.gray { background: #88888822; color: #888; }
.badge.yellow { background: #e0a05022; color: #e0a050; }
.btn { padding: 8px 16px; border: none; border-radius: 8px; cursor: pointer; font-size: 14px; font-weight: 600; color: #fff; }
.btn.green { background: #6ac278; }
.btn.green:hover { background: #5ab368; }
.btn-sm { padding: 4px 10px; border: none; border-radius: 6px; cursor: pointer; font-size: 11px; font-weight: 600; color: #fff; margin-left: 4px; }
.btn-sm.green { background: #6ac278; }
.btn-sm.yellow { background: #c0903c; }
.btn-sm.red { background: #c05050; }
.create-form { display: flex; gap: 8px; margin-bottom: 16px; align-items: center; }
.create-form input { background: #252530; border: 1px solid #ffffff10; color: #fff; padding: 8px 12px; border-radius: 8px; font-size: 14px; }
</style>"#;
