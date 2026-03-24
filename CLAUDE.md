# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vibing 是一个跨平台终端同步应用，允许用户通过安全中继在多设备间共享终端会话。采用 Swift (客户端) + Rust (服务端) 混合架构。

## Repository Structure

- **vibing-macos/** — macOS 桌面客户端 (Swift/SwiftUI + Metal, SPM)
  - **vibing-macos/vibing-server/** — 内置终端托管服务器 (Rust)
- **vibing-ios/** — iOS 移动端客户端 (Swift/UIKit + Metal)
- **vibing-relay/** — 端到端加密中继服务器 (Rust)

## Build Commands

```bash
# macOS 客户端
cd vibing-macos && swift build

# 终端服务器
cd vibing-macos/vibing-server && cargo build --release
cd vibing-macos/vibing-server && cargo run -- --bind 127.0.0.1:8765

# 中继服务器
cd vibing-relay && cargo build --release

# Rust 测试 (24 tests)
cd vibing-macos/vibing-server && cargo test
```

## Architecture

### 数据流
```
PTY stdout → Vt100Parser → TerminalState → DirtyRegions → ScreenFrame → WebSocket (JSON) → Client
Client KeyPress → WebSocket → Server → PTY stdin
```

### 协议设计
- 帧格式: `[1B type][4B length LE][JSON payload]` — 使用 serde_json 编码
- 客户端发送 JSON 文本消息创建会话，二进制帧发送输入
- 服务端使用增量脏区域传输，仅发送变化的 cell

### macOS 客户端模块
- `Models/` — TabManager (多标签+分屏), ThemeManager (7个内置主题), AccountManager
- `Views/` — ContentView (主布局), WorkingTerminalView (WebSocket会话), SearchBarView (Cmd+F), CommandPaletteView (Cmd+K)
- `Rendering/` — Metal GPU 渲染 (TerminalMetalView + OptimizedMetalRenderer + GlyphCache)
- `Network/` — TerminalWebSocketClient, BinaryProtocolEncoder/Decoder, TerminalProtocol

### Rust 服务端模块
- `server.rs` — WebSocket 服务器，事件驱动广播，60fps 节流
- `pty.rs` — PTY 会话管理，集成 Vt100Parser
- `vt100.rs` — 完整 VT100/ANSI 解析器 (CSI, SGR, OSC, 256色+RGB)
- `render.rs` — 增量渲染器，按行脏区域检测+合并
- `relay_client.rs` — 中继客户端，AES-256-GCM 加密

### 注意事项
- Swift 的 `Color` 类型与 `TerminalProtocol.swift` 中的 `Color` enum 冲突，UI 代码中需使用 `SwiftUI.Color`
- Package.swift 中 `vibing-server/` 和 `VibeTerminal/` 目录已排除，不参与 Swift 编译
- PTYTypes.swift 与 PTYSession.swift 有类型重复，仅编译 PTYSession.swift

## Platform Requirements
- macOS 客户端: macOS 13.0+, Swift 5.9
- Rust 组件: Edition 2021
- iOS 客户端: iOS 15.0+ (UIKit)
