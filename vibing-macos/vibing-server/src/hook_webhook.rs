//
//  hook_webhook.rs
//  Vibing Server — Webhook Delivery Worker
//
//  将 HookEvent 推送到注册的外部 HTTP 端点
//

use hmac::{Hmac, Mac};
use sha2::Sha256;
use tokio::sync::broadcast;
use tracing::{debug, warn};

use crate::config::WebhookConfig;
use crate::hook_api::HookEvent;

type HmacSha256 = Hmac<Sha256>;

/// 计算 HMAC-SHA256 签名
fn compute_signature(body: &str, secret: &str) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
        .expect("HMAC can take key of any size");
    mac.update(body.as_bytes());
    let result = mac.finalize();
    hex::encode(result.into_bytes())
}

/// 启动 Webhook 推送 worker
pub async fn start_webhook_worker(
    mut rx: broadcast::Receiver<HookEvent>,
    targets: Vec<WebhookConfig>,
) {
    if targets.is_empty() {
        return;
    }

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .expect("Failed to create HTTP client");

    tracing::info!("Webhook worker started with {} target(s)", targets.len());

    loop {
        match rx.recv().await {
            Ok(event) => {
                let event_type = event.event_type().to_string();

                for target in &targets {
                    // 检查事件是否匹配 target 的 filter
                    if !target.events.is_empty()
                        && !target.events.contains(&event_type)
                        && !target.events.contains(&"*".to_string())
                    {
                        continue;
                    }

                    let body = match serde_json::to_string(&event) {
                        Ok(b) => b,
                        Err(_) => continue,
                    };

                    let mut req = client
                        .post(&target.url)
                        .header("Content-Type", "application/json")
                        .header("X-Vibing-Event", &event_type);

                    // 添加 HMAC 签名
                    if let Some(secret) = &target.secret {
                        let sig = compute_signature(&body, secret);
                        req = req.header("X-Vibing-Signature", format!("sha256={}", sig));
                    }

                    let url = target.url.clone();
                    let req = req.body(body);

                    // 非阻塞发送
                    tokio::spawn(async move {
                        match req.send().await {
                            Ok(resp) => {
                                debug!("Webhook delivered to {}: {}", url, resp.status());
                            }
                            Err(e) => {
                                warn!("Webhook delivery failed to {}: {}", url, e);
                            }
                        }
                    });
                }
            }
            Err(broadcast::error::RecvError::Lagged(n)) => {
                warn!("Webhook worker lagged, skipped {} events", n);
            }
            Err(broadcast::error::RecvError::Closed) => {
                break;
            }
        }
    }
}
