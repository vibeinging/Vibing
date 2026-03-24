# Hook API System Design

> Vibing 的 PTY 层可编程接口，让开发者在终端数据流上构建扩展。

## Architecture

```
PTY Output → ServerEvent::SessionOutput → HookEngine (prompt detection, idle tracking)
                                              │
                                    ┌─────────┼──────────┐
                                    ▼         ▼          ▼
                              SSE stream   Webhooks   Hook state
                             GET /events  HTTP POST  GET /status

External script → POST /sessions/{id}/input → PtySession.write()
```

Hook API 运行在**独立的 HTTP 端口**（默认 8767），不影响主 WebSocket 服务器（8765）。通过订阅已有的 `broadcast::channel<ServerEvent>` 获取事件，叠加 prompt 检测和 idle 检测逻辑。

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/events` | SSE 事件流（支持 `?filter=on_prompt` 过滤） |
| `GET` | `/api/v1/sessions` | 列出活跃 session |
| `GET` | `/api/v1/status` | 健康检查 + 引擎状态 |
| `POST` | `/api/v1/sessions/{id}/input` | 写入原始字节到 PTY stdin |
| `POST` | `/api/v1/sessions/{id}/approve` | 发送 `y\n` 到 PTY stdin |
| `POST` | `/api/v1/sessions/{id}/reject` | 发送 `n\n` 到 PTY stdin |
| `POST` | `/api/v1/sessions/{id}/command` | 发送任意文本 + 回车 |
| `POST` | `/api/v1/webhooks` | 注册 webhook |
| `DELETE` | `/api/v1/webhooks/{id}` | 删除 webhook |

所有请求需要 `Authorization: Bearer <token>` header。

## Event Types

```json
// on_output — AI agent 产生输出
{"type": "on_output", "session_id": "1", "data_base64": "...", "timestamp": 1711234567}

// on_prompt — 检测到交互提示
{"type": "on_prompt", "session_id": "1", "prompt": {
  "kind": "confirmation",
  "text": "Allow edit to src/main.rs? [y/N]",
  "options": ["y", "N"],
  "default": "N"
}, "timestamp": 1711234567}

// on_idle — Agent 进入空闲
{"type": "on_idle", "session_id": "1", "idle_ms": 5000, "timestamp": 1711234567}

// on_error — 检测到错误模式
{"type": "on_error", "session_id": "1", "pattern": "error", "line": "error[E0308]: mismatched types", "timestamp": 1711234567}

// on_session_created / on_session_closed
{"type": "on_session_created", "session_id": "1", "timestamp": 1711234567}
{"type": "on_session_closed", "session_id": "1", "timestamp": 1711234567}
```

## Prompt Detection

从 PTY 输出的最后 512 字节中（去除 ANSI 转义码后）匹配以下模式：

| AI Tool | Pattern | Example |
|---------|---------|---------|
| Claude Code | `Allow? (Y)es / (N)o` | Tool approval |
| Cursor Agent | `[y/N]` | File modification |
| Aider | `Edit? (Y)es/(N)o` | Apply edit |
| Generic | `[y/n]`, `(yes/no)` | Package managers |
| Passphrase | `Password:`, `passphrase:` | SSH/sudo（检测但不自动批准） |

## Implementation

### New Files

| File | LOC | Purpose |
|------|-----|---------|
| `src/hook_api.rs` | ~400 | HookEngine 核心：事件处理、prompt 检测、idle 检测 |
| `src/hook_http.rs` | ~250 | Axum HTTP 路由、SSE、auth 中间件 |
| `src/hook_webhook.rs` | ~100 | Webhook 推送 worker |

### Modified Files

| File | Change |
|------|--------|
| `src/server.rs` | 新增 `subscribe_events()` 和 `sessions_ref()` 公开方法 |
| `src/config.rs` | 新增 `hook_api_*` 配置字段 |
| `src/main.rs` | 新增 `--hook-api` CLI 参数，条件启动 Hook 引擎 |
| `Cargo.toml` | 新增可选依赖（axum, reqwest, regex），feature flag `hook-api` |

### New Dependencies (behind feature flag)

```toml
[features]
default = []
hook-api = ["axum", "axum-extra", "tower-http", "reqwest", "regex"]
```

默认构建不包含 hook API，零开销。启用：`cargo build --features hook-api`

### Implementation Steps

1. **config.rs** — 添加 `HookConfig` 和 CLI 参数
2. **hook_api.rs** — HookEngine + HookEvent + prompt 检测 regex + unit tests
3. **hook_http.rs** — Axum 路由 + SSE + auth 中间件 + input injection
4. **server.rs** — 暴露 `subscribe_events()` / `sessions_ref()`
5. **hook_webhook.rs** — Webhook 推送
6. **main.rs** — 条件启动 wiring
7. **Cargo.toml** — 可选依赖 + feature flag
8. **Demo 脚本** — Python auto-approve 示例

## Security

- Hook API 默认只监听 `127.0.0.1`（不暴露到公网）
- 所有请求必须携带 auth token
- Webhook 支持 HMAC 签名验证
- Passphrase/password 类 prompt 检测但标记为 `kind: "passphrase"`，demo 脚本不会自动批准
- Feature flag 隔离：默认构建不含 hook API 代码
