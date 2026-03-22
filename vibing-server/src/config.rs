//
//  config.rs
//  Vibe Terminal Server
//
//  服务器配置
//

use serde::{Deserialize, Serialize};
use std::path::Path;

/// 服务器配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub bind: String,
    pub default_shell: String,
    pub default_env: Vec<(String, String)>,
    pub max_sessions: usize,
    pub idle_timeout_minutes: u64,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            bind: "0.0.0.0:8765".to_string(),
            default_shell: "/bin/bash".to_string(),
            default_env: vec![
                ("TERM".to_string(), "xterm-256color".to_string()),
                ("LANG".to_string(), "en_US.UTF-8".to_string()),
            ],
            max_sessions: 10,
            idle_timeout_minutes: 30,
        }
    }
}

impl ServerConfig {
    pub fn load<P: AsRef<Path>>(path: P) -> Result<Self, anyhow::Error> {
        let content = std::fs::read_to_string(path)?;
        let config: ServerConfig = toml::from_str(&content)?;
        Ok(config)
    }

    pub fn save<P: AsRef<Path>>(&self, path: P) -> Result<(), anyhow::Error> {
        let content = toml::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }

    pub fn default_config_path() -> &'static str {
        "config.toml"
    }
}
