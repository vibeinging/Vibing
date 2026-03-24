//
//  db.rs
//  Vibe Relay Server
//
//  SQLite 数据库层 - 用户和设备管理
//

use rusqlite::{Connection, params};
use std::sync::Mutex;
use chrono::Utc;
use serde::{Deserialize, Serialize};

/// 用户
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub username: String,
    #[serde(skip_serializing)]
    pub password_hash: String,
    pub created_at: String,
    pub last_login: Option<String>,
    #[serde(default = "default_status")]
    pub status: String,
}

fn default_status() -> String { "active".to_string() }

/// 邀请码
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InviteCode {
    pub code: String,
    pub created_by: Option<String>,
    pub created_at: String,
    pub used_by: Option<String>,
    pub used_at: Option<String>,
    pub max_uses: i32,
    pub use_count: i32,
}

/// 设备
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Device {
    pub id: String,
    pub user_id: String,
    pub name: String,
    pub device_type: String,
    pub platform: Option<String>,
    pub registered_at: String,
    pub last_seen: String,
    #[serde(default)]
    pub is_online: bool,
}

pub struct Database {
    conn: Mutex<Connection>,
}

impl Database {
    pub fn open(path: &str) -> anyhow::Result<Self> {
        let conn = Connection::open(path)?;
        let db = Self {
            conn: Mutex::new(conn),
        };
        db.init_tables()?;
        Ok(db)
    }

    fn init_tables(&self) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                created_at TEXT NOT NULL,
                last_login TEXT,
                status TEXT DEFAULT 'active'
            );

            CREATE TABLE IF NOT EXISTS devices (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                device_type TEXT NOT NULL,
                platform TEXT,
                registered_at TEXT NOT NULL,
                last_seen TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);

            CREATE TABLE IF NOT EXISTS invite_codes (
                code TEXT PRIMARY KEY,
                created_by TEXT,
                created_at TEXT NOT NULL,
                used_by TEXT,
                used_at TEXT,
                max_uses INTEGER DEFAULT 1,
                use_count INTEGER DEFAULT 0
            );",
        )?;

        // 迁移：给已有 users 表加 status 字段（如果不存在）
        let _ = conn.execute("ALTER TABLE users ADD COLUMN status TEXT DEFAULT 'active'", []);

        Ok(())
    }

    // ---- Users ----

    pub fn create_user(&self, id: &str, username: &str, password_hash: &str) -> anyhow::Result<User> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().to_rfc3339();
        conn.execute(
            "INSERT INTO users (id, username, password_hash, created_at, status) VALUES (?1, ?2, ?3, ?4, 'active')",
            params![id, username, password_hash, now],
        )?;
        Ok(User {
            id: id.to_string(),
            username: username.to_string(),
            password_hash: password_hash.to_string(),
            created_at: now,
            last_login: None,
            status: "active".to_string(),
        })
    }

    fn get_user_by(&self, column: &str, value: &str) -> anyhow::Result<Option<User>> {
        let conn = self.conn.lock().unwrap();
        let sql = format!(
            "SELECT id, username, password_hash, created_at, last_login, COALESCE(status, 'active') FROM users WHERE {} = ?1",
            column
        );
        let mut stmt = conn.prepare(&sql)?;
        let mut rows = stmt.query(params![value])?;
        if let Some(row) = rows.next()? {
            Ok(Some(User {
                id: row.get(0)?,
                username: row.get(1)?,
                password_hash: row.get(2)?,
                created_at: row.get(3)?,
                last_login: row.get(4)?,
                status: row.get(5)?,
            }))
        } else {
            Ok(None)
        }
    }

    pub fn get_user_by_username(&self, username: &str) -> anyhow::Result<Option<User>> {
        self.get_user_by("username", username)
    }

    pub fn get_user_by_id(&self, id: &str) -> anyhow::Result<Option<User>> {
        self.get_user_by("id", id)
    }

    pub fn update_last_login(&self, user_id: &str) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().to_rfc3339();
        conn.execute(
            "UPDATE users SET last_login = ?1 WHERE id = ?2",
            params![now, user_id],
        )?;
        Ok(())
    }

    // ---- Devices ----

    pub fn upsert_device(
        &self,
        id: &str,
        user_id: &str,
        name: &str,
        device_type: &str,
        platform: Option<&str>,
    ) -> anyhow::Result<Device> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().to_rfc3339();
        conn.execute(
            "INSERT INTO devices (id, user_id, name, device_type, platform, registered_at, last_seen)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(id) DO UPDATE SET name = ?3, last_seen = ?7",
            params![id, user_id, name, device_type, platform, now, now],
        )?;
        Ok(Device {
            id: id.to_string(),
            user_id: user_id.to_string(),
            name: name.to_string(),
            device_type: device_type.to_string(),
            platform: platform.map(|s| s.to_string()),
            registered_at: now.clone(),
            last_seen: now,
            is_online: false,
        })
    }

    pub fn get_devices_by_user(&self, user_id: &str) -> anyhow::Result<Vec<Device>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, user_id, name, device_type, platform, registered_at, last_seen
             FROM devices WHERE user_id = ?1 ORDER BY last_seen DESC",
        )?;
        let devices = stmt.query_map(params![user_id], |row| {
            Ok(Device {
                id: row.get(0)?,
                user_id: row.get(1)?,
                name: row.get(2)?,
                device_type: row.get(3)?,
                platform: row.get(4)?,
                registered_at: row.get(5)?,
                last_seen: row.get(6)?,
                is_online: false,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
        Ok(devices)
    }

    pub fn delete_device(&self, device_id: &str, user_id: &str) -> anyhow::Result<bool> {
        let conn = self.conn.lock().unwrap();
        let rows = conn.execute(
            "DELETE FROM devices WHERE id = ?1 AND user_id = ?2",
            params![device_id, user_id],
        )?;
        Ok(rows > 0)
    }

    pub fn update_device_last_seen(&self, device_id: &str) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().to_rfc3339();
        conn.execute(
            "UPDATE devices SET last_seen = ?1 WHERE id = ?2",
            params![now, device_id],
        )?;
        Ok(())
    }

    // ---- Admin: Users ----

    pub fn list_all_users(&self) -> anyhow::Result<Vec<User>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, username, password_hash, created_at, last_login, COALESCE(status, 'active') FROM users ORDER BY created_at DESC"
        )?;
        let users = stmt.query_map([], |row| {
            Ok(User {
                id: row.get(0)?,
                username: row.get(1)?,
                password_hash: row.get(2)?,
                created_at: row.get(3)?,
                last_login: row.get(4)?,
                status: row.get(5)?,
            })
        })?.collect::<Result<Vec<_>, _>>()?;
        Ok(users)
    }

    pub fn set_user_status(&self, user_id: &str, status: &str) -> anyhow::Result<bool> {
        let conn = self.conn.lock().unwrap();
        let rows = conn.execute(
            "UPDATE users SET status = ?1 WHERE id = ?2",
            params![status, user_id],
        )?;
        Ok(rows > 0)
    }

    pub fn delete_user(&self, user_id: &str) -> anyhow::Result<bool> {
        let conn = self.conn.lock().unwrap();
        // 删用户会级联删设备
        let rows = conn.execute("DELETE FROM users WHERE id = ?1", params![user_id])?;
        Ok(rows > 0)
    }

    pub fn user_count(&self) -> anyhow::Result<i64> {
        let conn = self.conn.lock().unwrap();
        let count: i64 = conn.query_row("SELECT COUNT(*) FROM users", [], |row| row.get(0))?;
        Ok(count)
    }

    // ---- Invite Codes ----

    pub fn create_invite_code(&self, code: &str, created_by: &str, max_uses: i32) -> anyhow::Result<InviteCode> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().to_rfc3339();
        conn.execute(
            "INSERT INTO invite_codes (code, created_by, created_at, max_uses, use_count) VALUES (?1, ?2, ?3, ?4, 0)",
            params![code, created_by, now, max_uses],
        )?;
        Ok(InviteCode {
            code: code.to_string(),
            created_by: Some(created_by.to_string()),
            created_at: now,
            used_by: None,
            used_at: None,
            max_uses,
            use_count: 0,
        })
    }

    pub fn validate_invite_code(&self, code: &str) -> anyhow::Result<bool> {
        let conn = self.conn.lock().unwrap();
        let result: Option<(i32, i32)> = conn.query_row(
            "SELECT max_uses, use_count FROM invite_codes WHERE code = ?1",
            params![code],
            |row| Ok((row.get(0)?, row.get(1)?)),
        ).ok();
        match result {
            Some((max_uses, use_count)) => Ok(use_count < max_uses),
            None => Ok(false),
        }
    }

    pub fn use_invite_code(&self, code: &str, user_id: &str) -> anyhow::Result<bool> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().to_rfc3339();
        let rows = conn.execute(
            "UPDATE invite_codes SET use_count = use_count + 1, used_by = ?1, used_at = ?2 WHERE code = ?3 AND use_count < max_uses",
            params![user_id, now, code],
        )?;
        Ok(rows > 0)
    }

    pub fn list_invite_codes(&self) -> anyhow::Result<Vec<InviteCode>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT code, created_by, created_at, used_by, used_at, max_uses, use_count FROM invite_codes ORDER BY created_at DESC"
        )?;
        let codes = stmt.query_map([], |row| {
            Ok(InviteCode {
                code: row.get(0)?,
                created_by: row.get(1)?,
                created_at: row.get(2)?,
                used_by: row.get(3)?,
                used_at: row.get(4)?,
                max_uses: row.get(5)?,
                use_count: row.get(6)?,
            })
        })?.collect::<Result<Vec<_>, _>>()?;
        Ok(codes)
    }

    pub fn delete_invite_code(&self, code: &str) -> anyhow::Result<bool> {
        let conn = self.conn.lock().unwrap();
        let rows = conn.execute("DELETE FROM invite_codes WHERE code = ?1", params![code])?;
        Ok(rows > 0)
    }

    pub fn invite_code_count(&self) -> anyhow::Result<i64> {
        let conn = self.conn.lock().unwrap();
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM invite_codes WHERE use_count < max_uses", [], |row| row.get(0)
        )?;
        Ok(count)
    }
}
