# Relay Bridge Implementation - macOS 对接 Server 实现记录

## Date: 2026-03-23

## Summary

实现了 macOS 客户端通过 vibing-server 连接 relay 服务器，与 iOS 移动端共享终端会话的完整链路。

## Architecture

```
iOS ↔ vibing-relay ↔ vibing-server ↔ PTY    (单跳，低延迟)
                      ↑
               macOS 客户端控制（发送 start_relay/stop_relay 命令）
```

## Changes Made

### 1. vibing-server/src/relay_client.rs
- **Fix**: 修复 key 派生与 iOS 不一致 (`SHA256(session_id)` instead of `SHA256("vibe-terminal-v1" + session_id)`)
- **Feature**: `RelayHandshake` 添加 JWT `token` 字段
- **Feature**: `RelayClient::new()` 接受 `token` 和 `event_tx` 参数
- **Feature**: 新增 `RelayEvent` enum (PeerConnected, PeerDisconnected, Error)
- **Feature**: 连接状态变化时通过 event channel 通知

### 2. vibing-server/src/server.rs
- **Feature**: 新增 `RelayBridge` struct 管理 relay 连接
- **Feature**: `TerminalServer` 添加 `relay_bridges: DashMap`
- **Feature**: `start_relay` 命令 — 动态启动 relay 桥接
- **Feature**: `stop_relay` 命令 — 停止 relay 桥接
- **Feature**: `broadcast_session_output` 增加 relay 转发
- **Feature**: 会话关闭时自动清理 relay bridge
- **Feature**: `send_text_to_client` 辅助方法
- **Feature**: relay 状态回传 (relay_started, relay_stopped, relay_peer_connected, relay_peer_disconnected)

### 3. vibing-macos/Models/AccountManager.swift
- **Feature**: `RelayAPIClient` 添加 `getRelaySessions()` 方法
- **Feature**: `RelayAPIClient` 添加 `relayWebSocketURL` 属性

### 4. vibing-macos/Models/RelaySessionManager.swift (NEW)
- 管理 relay 共享状态 (isSharing, relaySessionId, peerConnected)
- `startSharing()` — 生成 session ID，发送 start_relay 命令
- `stopSharing()` — 发送 stop_relay 命令
- `handleRelayMessage()` — 处理 server 回传的 relay 状态

### 5. vibing-macos/Network/TerminalWebSocketClient.swift
- **Feature**: `handleTextMessage` 拦截 `relay_*` 消息转发给 RelaySessionManager
- **Feature**: `sendRawText()` 方法发送原始 JSON 文本

### 6. vibing-macos/Views/WorkingTerminalView.swift
- **Feature**: `TerminalSessionManager` 监听 `sendRelayCommand` 通知
- **Feature**: `currentSessionId` 改为 `private(set)` 供外部读取

### 7. vibing-macos/Views/ShareSessionView.swift (NEW)
- `ShareSessionView` — 分享面板 UI（session code 显示、连接状态、开始/停止）
- `ShareToolbarButton` — 工具栏按钮（带 popover）

### 8. vibing-macos/Package.swift
- 添加 RelaySessionManager.swift 和 ShareSessionView.swift

## Protocol: start_relay Command

```json
{
  "type": "start_relay",
  "session_id": "1",
  "relay_url": "ws://relay.example.com:8766/ws",
  "token": "JWT...",
  "relay_session_id": "abc123def456ghij"
}
```

## Relay URL Configuration

macOS 端 relay URL 通过 `UserDefaults.standard.string(forKey: "relayServerURL")` 配置，默认 `http://127.0.0.1:8766`。

## Encryption

Both iOS and Rust server derive AES-256-GCM key from `SHA256(session_id)`. Format: `[nonce(12 bytes) + ciphertext + tag(16 bytes)]`.

## Build Verification

- Rust: `cargo build` ✅, `cargo test` 27/27 passed ✅
- Swift: `swift build` ✅
