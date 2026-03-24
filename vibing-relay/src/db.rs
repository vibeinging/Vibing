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
                last_login TEXT
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

            CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);",
        )?;
        Ok(())
    }

    // ---- Users ----

    pub fn create_user(&self, id: &str, username: &str, password_hash: &str) -> anyhow::Result<User> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().to_rfc3339();
        conn.execute(
            "INSERT INTO users (id, username, password_hash, created_at) VALUES (?1, ?2, ?3, ?4)",
            params![id, username, password_hash, now],
        )?;
        Ok(User {
            id: id.to_string(),
            username: username.to_string(),
            password_hash: password_hash.to_string(),
            created_at: now,
            last_login: None,
        })
    }

    fn get_user_by(&self, column: &str, value: &str) -> anyhow::Result<Option<User>> {
        let conn = self.conn.lock().unwrap();
        let sql = format!(
            "SELECT id, username, password_hash, created_at, last_login FROM users WHERE {} = ?1",
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
}
