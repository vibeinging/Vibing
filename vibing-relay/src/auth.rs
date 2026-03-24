//
//  auth.rs
//  Vibe Relay Server
//
//  认证模块 - JWT + Argon2 密码哈希
//

use argon2::{
    Argon2,
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString, rand_core::OsRng},
};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use chrono::{Duration, Utc};

use crate::db::Database;

const TOKEN_EXPIRY_HOURS: i64 = 24;

/// JWT Claims
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,        // user_id
    pub username: String,
    pub device_id: Option<String>,
    pub exp: usize,         // expiration timestamp
    pub iat: usize,         // issued at
}

/// 注册请求
#[derive(Debug, Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub password: String,
    pub device_name: Option<String>,
    pub device_type: Option<String>,
    pub invite_code: Option<String>,
}

/// 登录请求
#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
    pub device_id: Option<String>,
    pub device_name: Option<String>,
    pub device_type: Option<String>,
}

/// 认证响应
#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub token: String,
    pub user_id: String,
    pub username: String,
    pub device_id: Option<String>,
}

/// 错误响应
#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
}

/// 生成用户 ID
fn generate_user_id() -> String {
    let chars: Vec<char> = "abcdefghijklmnopqrstuvwxyz0123456789".chars().collect();
    let random: String = (0..8)
        .map(|_| {
            let idx = rand::random::<usize>() % chars.len();
            chars[idx]
        })
        .collect();
    format!("vibe_{}", random)
}

/// 哈希密码
pub fn hash_password(password: &str) -> anyhow::Result<String> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let hash = argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| anyhow::anyhow!("Password hashing failed: {}", e))?;
    Ok(hash.to_string())
}

/// 验证密码
pub fn verify_password(password: &str, hash: &str) -> anyhow::Result<bool> {
    let parsed_hash = PasswordHash::new(hash)
        .map_err(|e| anyhow::anyhow!("Invalid password hash: {}", e))?;
    Ok(Argon2::default()
        .verify_password(password.as_bytes(), &parsed_hash)
        .is_ok())
}

/// 生成 JWT token
pub fn generate_token(jwt_secret: &str, user_id: &str, username: &str, device_id: Option<&str>) -> anyhow::Result<String> {
    let now = Utc::now();
    let exp = now + Duration::hours(TOKEN_EXPIRY_HOURS);

    let claims = Claims {
        sub: user_id.to_string(),
        username: username.to_string(),
        device_id: device_id.map(|s| s.to_string()),
        exp: exp.timestamp() as usize,
        iat: now.timestamp() as usize,
    };

    let token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(jwt_secret.as_bytes()),
    )?;

    Ok(token)
}

/// 验证 JWT token
pub fn verify_token(jwt_secret: &str, token: &str) -> anyhow::Result<Claims> {
    let token_data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(jwt_secret.as_bytes()),
        &Validation::default(),
    )
    .map_err(|e| anyhow::anyhow!("Token verification failed: {}", e))?;

    Ok(token_data.claims)
}

/// 注册用户
pub fn register(
    db: &Database,
    jwt_secret: &str,
    req: &RegisterRequest,
) -> Result<AuthResponse, String> {
    // 验证输入
    if req.username.len() < 2 || req.username.len() > 32 {
        return Err("Username must be 2-32 characters".to_string());
    }
    if req.password.len() < 6 {
        return Err("Password must be at least 6 characters".to_string());
    }
    if !req.username.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-') {
        return Err("Username can only contain letters, numbers, _ and -".to_string());
    }

    // 验证邀请码
    let invite_code = req.invite_code.as_deref().unwrap_or("");
    if invite_code.is_empty() {
        return Err("Invite code is required".to_string());
    }
    if !db.validate_invite_code(invite_code).unwrap_or(false) {
        return Err("Invalid or expired invite code".to_string());
    }

    // 检查用户名是否已存在
    if let Ok(Some(_)) = db.get_user_by_username(&req.username) {
        return Err("Username already taken".to_string());
    }

    // 创建用户
    let user_id = generate_user_id();
    let password_hash = hash_password(&req.password)
        .map_err(|e| format!("Failed to hash password: {}", e))?;

    db.create_user(&user_id, &req.username, &password_hash)
        .map_err(|e| format!("Failed to create user: {}", e))?;

    // 消费邀请码
    let _ = db.use_invite_code(invite_code, &user_id);

    // 注册设备
    let device_id = if let (Some(name), Some(dtype)) = (&req.device_name, &req.device_type) {
        let did = uuid::Uuid::new_v4().to_string();
        let _ = db.upsert_device(&did, &user_id, name, dtype, None);
        Some(did)
    } else {
        None
    };

    // 生成 token
    let token = generate_token(jwt_secret, &user_id, &req.username, device_id.as_deref())
        .map_err(|e| format!("Failed to generate token: {}", e))?;

    Ok(AuthResponse {
        token,
        user_id,
        username: req.username.clone(),
        device_id,
    })
}

/// 登录
pub fn login(
    db: &Database,
    jwt_secret: &str,
    req: &LoginRequest,
) -> Result<AuthResponse, String> {
    // 查找用户
    let user = db
        .get_user_by_username(&req.username)
        .map_err(|e| format!("Database error: {}", e))?
        .ok_or_else(|| "Invalid username or password".to_string())?;

    // 验证密码
    let valid = verify_password(&req.password, &user.password_hash)
        .map_err(|e| format!("Password verification error: {}", e))?;

    if !valid {
        return Err("Invalid username or password".to_string());
    }

    // 更新最后登录时间
    let _ = db.update_last_login(&user.id);

    // 注册/更新设备
    let device_id = if let Some(did) = &req.device_id {
        let name = req.device_name.as_deref().unwrap_or("Unknown Device");
        let dtype = req.device_type.as_deref().unwrap_or("unknown");
        let _ = db.upsert_device(did, &user.id, name, dtype, None);
        Some(did.clone())
    } else if let (Some(name), Some(dtype)) = (&req.device_name, &req.device_type) {
        let did = uuid::Uuid::new_v4().to_string();
        let _ = db.upsert_device(&did, &user.id, name, dtype, None);
        Some(did)
    } else {
        None
    };

    // 生成 token
    let token = generate_token(jwt_secret, &user.id, &user.username, device_id.as_deref())
        .map_err(|e| format!("Failed to generate token: {}", e))?;

    Ok(AuthResponse {
        token,
        user_id: user.id,
        username: user.username,
        device_id,
    })
}
