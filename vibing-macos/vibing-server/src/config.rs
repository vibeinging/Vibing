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

    /// Hook API 配置
    #[serde(default)]
    pub hook_api: HookApiConfig,
}

/// Hook API 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HookApiConfig {
    pub enabled: bool,
    pub bind: String,
    pub token: Option<String>,
    /// Idle 检测超时（毫秒），agent 无输出超过此时间触发 on_idle
    pub idle_timeout_ms: u64,
    /// Webhook 目标列表
    #[serde(default)]
    pub webhooks: Vec<WebhookConfig>,

    /// 自动批准配置
    #[serde(default)]
    pub auto_approve: AutoApproveConfig,

    /// 断路器配置
    #[serde(default)]
    pub circuit_breaker: CircuitBreakerConfig,
}

/// 自动批准配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutoApproveConfig {
    pub enabled: bool,
    /// 包含这些关键词的 prompt 自动批准（不区分大小写）
    pub allow_keywords: Vec<String>,
    /// 包含这些关键词的 prompt 自动拒绝（不区分大小写，优先级高于 allow）
    pub deny_keywords: Vec<String>,
}

impl Default for AutoApproveConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            allow_keywords: vec![
                "read".into(), "view".into(), "list".into(),
                "search".into(), "cat".into(), "ls".into(),
                "find".into(), "grep".into(),
            ],
            deny_keywords: vec![
                "delete".into(), "remove".into(), "rm ".into(), "rm -".into(),
                "drop".into(), "force push".into(), "--force".into(),
                "truncate".into(), "format".into(), "mkfs".into(),
            ],
        }
    }
}

/// 断路器配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CircuitBreakerConfig {
    pub enabled: bool,
    /// 连续多少次相似输出触发断路（默认 5）
    pub repeat_threshold: usize,
}

impl Default for CircuitBreakerConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            repeat_threshold: 5,
        }
    }
}

/// Webhook 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebhookConfig {
    pub url: String,
    pub events: Vec<String>,
    pub secret: Option<String>,
}

impl Default for HookApiConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            bind: "127.0.0.1:8767".to_string(),
            token: None,
            idle_timeout_ms: 5000,
            webhooks: vec![],
            auto_approve: AutoApproveConfig::default(),
            circuit_breaker: CircuitBreakerConfig::default(),
        }
    }
}

impl Default for ServerConfig {
    fn default() -> Self {
        // 使用 PtyConfig 的环境检测获取用户默认 shell
        let pty_defaults = crate::pty::PtyConfig::default();
        let shell = pty_defaults.shell;

        Self {
            bind: "0.0.0.0:8765".to_string(),
            default_shell: shell,
            default_env: vec![
                ("TERM".to_string(), "xterm-256color".to_string()),
                ("COLORTERM".to_string(), "truecolor".to_string()),
                ("LANG".to_string(), "en_US.UTF-8".to_string()),
            ],
            max_sessions: 10,
            idle_timeout_minutes: 30,
            hook_api: HookApiConfig::default(),
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
