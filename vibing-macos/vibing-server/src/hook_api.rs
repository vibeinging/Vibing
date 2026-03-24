//
//  hook_api.rs
//  Vibing Server — Hook API Engine
//
//  PTY 数据流的可编程接口核心：事件处理、prompt 检测、idle 检测
//

use std::collections::VecDeque;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use dashmap::DashMap;
use serde::Serialize;
use tokio::sync::broadcast;
use tokio::time::{Duration, Instant};
use tracing::{debug, info, warn};

use crate::config::HookApiConfig;
use crate::pty::PtySessionId;
use crate::server::{ServerEvent, SessionData};

// ── Event types ──────────────────────────────────────────────

/// Hook 事件 — 暴露给外部消费者的事件格式
#[derive(Clone, Debug, Serialize)]
#[serde(tag = "type")]
pub enum HookEvent {
    #[serde(rename = "on_output")]
    Output {
        session_id: String,
        data_base64: String,
        timestamp: u64,
    },
    #[serde(rename = "on_prompt")]
    Prompt {
        session_id: String,
        prompt: DetectedPrompt,
        timestamp: u64,
    },
    #[serde(rename = "on_idle")]
    Idle {
        session_id: String,
        idle_ms: u64,
        timestamp: u64,
    },
    #[serde(rename = "on_error")]
    Error {
        session_id: String,
        pattern: String,
        line: String,
        timestamp: u64,
    },
    #[serde(rename = "on_session_created")]
    SessionCreated { session_id: String, timestamp: u64 },
    #[serde(rename = "on_session_closed")]
    SessionClosed { session_id: String, timestamp: u64 },
}

impl HookEvent {
    pub fn event_type(&self) -> &'static str {
        match self {
            HookEvent::Output { .. } => "on_output",
            HookEvent::Prompt { .. } => "on_prompt",
            HookEvent::Idle { .. } => "on_idle",
            HookEvent::Error { .. } => "on_error",
            HookEvent::SessionCreated { .. } => "on_session_created",
            HookEvent::SessionClosed { .. } => "on_session_closed",
        }
    }
}

/// 检测到的交互提示
#[derive(Clone, Debug, Serialize)]
pub struct DetectedPrompt {
    pub kind: PromptKind,
    pub text: String,
    pub options: Vec<String>,
    pub default: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PromptKind {
    Confirmation,
    Selection,
    Passphrase,
}

// ── Prompt detection ─────────────────────────────────────────

/// 从 PTY 输出中检测交互提示
struct PromptDetector {
    patterns: Vec<PromptPattern>,
}

struct PromptPattern {
    regex: regex::Regex,
    kind: PromptKind,
}

impl PromptDetector {
    fn new() -> Self {
        let patterns = vec![
            // [y/N], [Y/n], [y/n/a], (y/n)
            PromptPattern {
                regex: regex::Regex::new(
                    r"[\[\(]([yYnNaA]/[yYnNaA](?:/[a-zA-Z])*)[)\]]\s*$"
                ).unwrap(),
                kind: PromptKind::Confirmation,
            },
            // (yes/no), (Yes/No)
            PromptPattern {
                regex: regex::Regex::new(
                    r"\(([yY](?:es)?/[nN](?:o)?)\)\s*$"
                ).unwrap(),
                kind: PromptKind::Confirmation,
            },
            // Claude Code: "Allow ..." / "Approve ..."
            PromptPattern {
                regex: regex::Regex::new(
                    r"(?i)(?:allow|approve|confirm|proceed|continue)\??\s*[\[\(]"
                ).unwrap(),
                kind: PromptKind::Confirmation,
            },
            // Aider: "Edit? (Y)es/(N)o"
            PromptPattern {
                regex: regex::Regex::new(
                    r"(?i)\?\s*\([A-Z]\)[a-z]+/\([A-Z]\)[a-z]+\s*$"
                ).unwrap(),
                kind: PromptKind::Confirmation,
            },
            // Password / passphrase prompts (detect but never auto-approve)
            PromptPattern {
                regex: regex::Regex::new(
                    r"(?i)(?:password|passphrase|token|secret)\s*:\s*$"
                ).unwrap(),
                kind: PromptKind::Passphrase,
            },
        ];
        Self { patterns }
    }

    /// 分析文本，返回检测到的 prompt（如果有）
    fn detect(&self, text: &str) -> Option<DetectedPrompt> {
        for pattern in &self.patterns {
            if let Some(caps) = pattern.regex.captures(text) {
                // 提取最后几行作为 prompt 文本
                let prompt_text = text.lines().last().unwrap_or(text).trim().to_string();

                // 尝试提取选项（从第一个捕获组）
                let (options, default) = if let Some(opts_match) = caps.get(1) {
                    let opts_str = opts_match.as_str();
                    let opts: Vec<String> = opts_str.split('/').map(|s| s.to_string()).collect();
                    // 大写的选项是默认值
                    let default = opts.iter().find(|o| o.chars().all(|c| c.is_uppercase())).cloned();
                    (opts, default)
                } else {
                    (vec![], None)
                };

                return Some(DetectedPrompt {
                    kind: pattern.kind.clone(),
                    text: prompt_text,
                    options,
                    default,
                });
            }
        }
        None
    }
}

/// 错误模式检测
struct ErrorDetector {
    regex: regex::Regex,
}

impl ErrorDetector {
    fn new() -> Self {
        Self {
            regex: regex::Regex::new(
                r"(?i)(?:error|fatal|panic|exception|traceback|failed)[\s:\[]"
            ).unwrap(),
        }
    }

    fn detect(&self, text: &str) -> Option<(String, String)> {
        for line in text.lines().rev().take(5) {
            if let Some(m) = self.regex.find(line) {
                let pattern = m.as_str().trim_end_matches(|c: char| !c.is_alphanumeric()).to_string();
                return Some((pattern, line.trim().to_string()));
            }
        }
        None
    }
}

/// 剥离 ANSI 转义码
fn strip_ansi(input: &[u8]) -> String {
    let text = String::from_utf8_lossy(input);
    // 匹配 ESC[ ... 字母 (CSI sequences) 和 ESC] ... ST (OSC sequences)
    let re = regex::Regex::new(r"\x1b\[[0-9;]*[a-zA-Z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][0-9A-B]").unwrap();
    re.replace_all(&text, "").to_string()
}

// ── Per-session state ────────────────────────────────────────

struct SessionHookState {
    last_output_at: Instant,
    is_idle: bool,
    /// 最近输出的环形缓冲区（用于 prompt/error 匹配）
    ring_buffer: VecDeque<u8>,
    /// 断路器：最近输出块的哈希（用于检测重复）
    recent_hashes: VecDeque<u64>,
    /// 上一次已处理的 prompt 文本（防止对同一个 prompt 重复操作）
    last_prompt: Option<String>,
}

impl SessionHookState {
    fn new() -> Self {
        Self {
            last_output_at: Instant::now(),
            is_idle: false,
            ring_buffer: VecDeque::with_capacity(4096),
            recent_hashes: VecDeque::with_capacity(32),
            last_prompt: None,
        }
    }

    fn push_output(&mut self, data: &[u8]) {
        for &byte in data {
            if self.ring_buffer.len() >= 4096 {
                self.ring_buffer.pop_front();
            }
            self.ring_buffer.push_back(byte);
        }
        self.last_output_at = Instant::now();
        self.is_idle = false;
    }

    /// 获取最后 N 字节用于模式匹配
    fn tail_bytes(&self, n: usize) -> Vec<u8> {
        let len = self.ring_buffer.len();
        let start = if len > n { len - n } else { 0 };
        self.ring_buffer.iter().skip(start).copied().collect()
    }

    /// 记录输出块哈希，返回连续重复次数
    fn push_hash(&mut self, data: &[u8]) -> usize {
        // 简单快速哈希（FNV-1a）
        let mut h: u64 = 0xcbf29ce484222325;
        for &b in data {
            h ^= b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }

        if self.recent_hashes.len() >= 32 {
            self.recent_hashes.pop_front();
        }
        self.recent_hashes.push_back(h);

        // 从后往前数连续相同的哈希
        let mut count = 0;
        for &prev in self.recent_hashes.iter().rev() {
            if prev == h {
                count += 1;
            } else {
                break;
            }
        }
        count
    }
}

// ── Hook Engine ──────────────────────────────────────────────

pub struct HookEngine {
    config: HookApiConfig,
    hook_tx: broadcast::Sender<HookEvent>,
    session_states: Arc<DashMap<PtySessionId, SessionHookState>>,
    sessions: Arc<DashMap<PtySessionId, SessionData>>,
    prompt_detector: PromptDetector,
    error_detector: ErrorDetector,
}

impl HookEngine {
    pub fn new(
        config: HookApiConfig,
        sessions: Arc<DashMap<PtySessionId, SessionData>>,
    ) -> Self {
        let (hook_tx, _) = broadcast::channel(1000);
        Self {
            config,
            hook_tx,
            session_states: Arc::new(DashMap::new()),
            sessions,
            prompt_detector: PromptDetector::new(),
            error_detector: ErrorDetector::new(),
        }
    }

    /// 获取 hook 事件发送者（供 HTTP 层订阅）
    pub fn hook_tx(&self) -> broadcast::Sender<HookEvent> {
        self.hook_tx.clone()
    }

    /// 获取 sessions 引用（供 HTTP 层注入输入）
    pub fn sessions(&self) -> Arc<DashMap<PtySessionId, SessionData>> {
        self.sessions.clone()
    }

    /// 主事件循环 — 消费 ServerEvent，产生 HookEvent
    pub async fn run(self, mut event_rx: broadcast::Receiver<ServerEvent>) {
        let idle_timeout = Duration::from_millis(self.config.idle_timeout_ms);
        let session_states = self.session_states.clone();
        let hook_tx = self.hook_tx.clone();

        // Idle 检测任务
        let idle_states = session_states.clone();
        let idle_hook_tx = hook_tx.clone();
        let idle_ms = self.config.idle_timeout_ms;
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(1));
            loop {
                interval.tick().await;
                let now = Instant::now();
                for mut entry in idle_states.iter_mut() {
                    let state = entry.value_mut();
                    if !state.is_idle && now.duration_since(state.last_output_at) >= Duration::from_millis(idle_ms) {
                        state.is_idle = true;
                        let _ = idle_hook_tx.send(HookEvent::Idle {
                            session_id: entry.key().as_string(),
                            idle_ms,
                            timestamp: now_unix(),
                        });
                    }
                }
            }
        });

        info!("HookEngine started, listening for events...");

        // 主事件循环
        loop {
            match event_rx.recv().await {
                Ok(event) => {
                    match event {
                        ServerEvent::SessionOutput(id, raw_data) => {
                            self.process_output(id, &raw_data);
                        }
                        ServerEvent::SessionCreated(id) => {
                            session_states.insert(id, SessionHookState::new());
                            let _ = hook_tx.send(HookEvent::SessionCreated {
                                session_id: id.as_string(),
                                timestamp: now_unix(),
                            });
                        }
                        ServerEvent::SessionClosed(id) => {
                            session_states.remove(&id);
                            let _ = hook_tx.send(HookEvent::SessionClosed {
                                session_id: id.as_string(),
                                timestamp: now_unix(),
                            });
                        }
                        _ => {}
                    }
                }
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    warn!("HookEngine lagged, skipped {} events", n);
                }
                Err(broadcast::error::RecvError::Closed) => {
                    info!("HookEngine: event channel closed, shutting down");
                    break;
                }
            }
        }
    }

    fn process_output(&self, session_id: PtySessionId, raw_data: &[u8]) {
        // 更新 session 状态
        let mut state_entry = self.session_states.entry(session_id).or_insert_with(SessionHookState::new);
        state_entry.push_output(raw_data);

        // ── 断路器：检测重复输出 ──
        if self.config.circuit_breaker.enabled && raw_data.len() > 10 {
            let repeat_count = state_entry.push_hash(raw_data);
            if repeat_count >= self.config.circuit_breaker.repeat_threshold {
                warn!("Circuit breaker triggered for session {} ({} repeats)", session_id, repeat_count);
                // 重置计数，避免连续触发
                state_entry.recent_hashes.clear();
                drop(state_entry);
                // 发送 Ctrl+C（0x03）
                if let Some(entry) = self.sessions.get(&session_id) {
                    if let Ok(session) = entry.session.try_lock() {
                        let _ = session.write(&[0x03]);
                        info!("Circuit breaker: sent Ctrl+C to session {}", session_id);
                    }
                }
                return; // 不继续处理这次输出
            }
        }

        // 发送 on_output 事件
        let _ = self.hook_tx.send(HookEvent::Output {
            session_id: session_id.as_string(),
            data_base64: base64::Engine::encode(&base64::engine::general_purpose::STANDARD, raw_data),
            timestamp: now_unix(),
        });

        // 获取尾部用于 prompt/error 检测
        let tail = state_entry.tail_bytes(512);
        let last_prompt = state_entry.last_prompt.clone();
        drop(state_entry);

        let clean_text = strip_ansi(&tail);

        // ── Prompt 检测 + 自动批准 ──
        if let Some(prompt) = self.prompt_detector.detect(&clean_text) {
            // 防止对同一个 prompt 重复处理
            let is_new = last_prompt.as_deref() != Some(&prompt.text);

            if is_new {
                if let Some(mut entry) = self.session_states.get_mut(&session_id) {
                    entry.last_prompt = Some(prompt.text.clone());
                }

                debug!("Prompt detected in session {}: {:?}", session_id, prompt.text);
                let _ = self.hook_tx.send(HookEvent::Prompt {
                    session_id: session_id.as_string(),
                    prompt: prompt.clone(),
                    timestamp: now_unix(),
                });

                // 自动批准逻辑
                if self.config.auto_approve.enabled {
                    if let Some(response) = self.decide_auto_approve(&prompt) {
                        if let Some(entry) = self.sessions.get(&session_id) {
                            if let Ok(session) = entry.session.try_lock() {
                                let _ = session.write(response.as_bytes());
                                info!("Auto-approve: sent '{}' to session {} for: {}",
                                    response.trim(), session_id, prompt.text);
                            }
                        }
                    }
                }
            }
        }

        // Error 检测
        if let Some((pattern, line)) = self.error_detector.detect(&clean_text) {
            let _ = self.hook_tx.send(HookEvent::Error {
                session_id: session_id.as_string(),
                pattern,
                line,
                timestamp: now_unix(),
            });
        }
    }

    /// 根据配置决定是否自动回复。返回 Some("y\n") / Some("n\n") / None（不干预）
    fn decide_auto_approve(&self, prompt: &DetectedPrompt) -> Option<String> {
        // 密码类 prompt 永远不自动处理
        if matches!(prompt.kind, PromptKind::Passphrase) {
            return None;
        }

        let text_lower = prompt.text.to_lowercase();
        let cfg = &self.config.auto_approve;

        // deny 优先级高于 allow
        if cfg.deny_keywords.iter().any(|kw| text_lower.contains(&kw.to_lowercase())) {
            return Some("n\n".to_string());
        }

        if cfg.allow_keywords.iter().any(|kw| text_lower.contains(&kw.to_lowercase())) {
            return Some("y\n".to_string());
        }

        // 两个列表都不匹配 → 不干预，交给用户
        None
    }
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

// ── Tests ────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_prompt_detection_yn() {
        let detector = PromptDetector::new();

        // [y/N]
        let result = detector.detect("Do you want to continue? [y/N]");
        assert!(result.is_some());
        let prompt = result.unwrap();
        assert!(matches!(prompt.kind, PromptKind::Confirmation));
        assert_eq!(prompt.options, vec!["y", "N"]);
        assert_eq!(prompt.default, Some("N".to_string()));

        // [Y/n]
        let result = detector.detect("Apply changes? [Y/n]");
        assert!(result.is_some());
        let prompt = result.unwrap();
        assert_eq!(prompt.default, Some("Y".to_string()));

        // (yes/no)
        let result = detector.detect("Are you sure? (yes/no)");
        assert!(result.is_some());
    }

    #[test]
    fn test_prompt_detection_passphrase() {
        let detector = PromptDetector::new();

        let result = detector.detect("Password: ");
        assert!(result.is_some());
        assert!(matches!(result.unwrap().kind, PromptKind::Passphrase));

        let result = detector.detect("Enter passphrase: ");
        assert!(result.is_some());
        assert!(matches!(result.unwrap().kind, PromptKind::Passphrase));
    }

    #[test]
    fn test_prompt_detection_no_match() {
        let detector = PromptDetector::new();
        assert!(detector.detect("Hello world").is_none());
        assert!(detector.detect("Building project...").is_none());
    }

    #[test]
    fn test_error_detection() {
        let detector = ErrorDetector::new();

        let result = detector.detect("error[E0308]: mismatched types");
        assert!(result.is_some());

        let result = detector.detect("FATAL: connection refused");
        assert!(result.is_some());

        let result = detector.detect("Everything is fine");
        assert!(result.is_none());
    }

    #[test]
    fn test_strip_ansi() {
        let input = b"\x1b[32mHello\x1b[0m world";
        let result = strip_ansi(input);
        assert_eq!(result, "Hello world");
    }

    #[test]
    fn test_session_ring_buffer() {
        let mut state = SessionHookState::new();
        state.push_output(b"Hello ");
        state.push_output(b"World");
        let tail = state.tail_bytes(5);
        assert_eq!(tail, b"World");
    }

    #[test]
    fn test_circuit_breaker_detection() {
        let mut state = SessionHookState::new();
        let data = b"error: something went wrong\n";

        // 前 4 次不触发
        for i in 1..=4 {
            assert!(state.push_hash(data) < 5, "should not trigger at {}", i);
        }
        // 第 5 次触发
        assert_eq!(state.push_hash(data), 5);
    }

    #[test]
    fn test_circuit_breaker_reset_on_different_output() {
        let mut state = SessionHookState::new();
        state.push_hash(b"error A\n");
        state.push_hash(b"error A\n");
        state.push_hash(b"error A\n");
        // 不同输出打断连续计数
        assert_eq!(state.push_hash(b"something else\n"), 1);
        assert_eq!(state.push_hash(b"error A\n"), 1);
    }

    #[test]
    fn test_auto_approve_decisions() {
        use crate::config::AutoApproveConfig;

        let cfg = AutoApproveConfig::default();

        // safe: contains "read"
        let prompt = DetectedPrompt {
            kind: PromptKind::Confirmation,
            text: "Allow read file src/main.rs? [y/n]".into(),
            options: vec!["y".into(), "n".into()],
            default: None,
        };
        let text_lower = prompt.text.to_lowercase();
        let is_deny = cfg.deny_keywords.iter().any(|kw| text_lower.contains(&kw.to_lowercase()));
        let is_allow = cfg.allow_keywords.iter().any(|kw| text_lower.contains(&kw.to_lowercase()));
        assert!(!is_deny);
        assert!(is_allow);

        // dangerous: contains "rm -"
        let prompt2 = DetectedPrompt {
            kind: PromptKind::Confirmation,
            text: "Run rm -rf ./dist? [y/n]".into(),
            options: vec!["y".into(), "n".into()],
            default: None,
        };
        let text_lower2 = prompt2.text.to_lowercase();
        let is_deny2 = cfg.deny_keywords.iter().any(|kw| text_lower2.contains(&kw.to_lowercase()));
        assert!(is_deny2);

        // passphrase: never auto-approve
        let prompt3 = DetectedPrompt {
            kind: PromptKind::Passphrase,
            text: "Password: ".into(),
            options: vec![],
            default: None,
        };
        assert!(matches!(prompt3.kind, PromptKind::Passphrase));

        // unknown: no match = no action
        let prompt4 = DetectedPrompt {
            kind: PromptKind::Confirmation,
            text: "Deploy to production? [y/n]".into(),
            options: vec!["y".into(), "n".into()],
            default: None,
        };
        let text_lower4 = prompt4.text.to_lowercase();
        let is_deny4 = cfg.deny_keywords.iter().any(|kw| text_lower4.contains(&kw.to_lowercase()));
        let is_allow4 = cfg.allow_keywords.iter().any(|kw| text_lower4.contains(&kw.to_lowercase()));
        assert!(!is_deny4);
        assert!(!is_allow4); // neither match → no action, ask user
    }
}
