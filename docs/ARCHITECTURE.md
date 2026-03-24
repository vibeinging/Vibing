# Vibing Architecture

> Technical deep-dive for contributors and the curious. For product overview, see [README](../README.md).

## Repository Structure

```
vibing/
├── vibing-macos/                # macOS client — Swift/SwiftUI + SwiftTerm
│   └── vibing-server/           # Terminal server — Rust + Tokio
├── vibing-ios/                  # iOS client — Swift/UIKit + Metal
├── vibing-android/              # Android client — Kotlin + Compose
└── vibing-relay/                # E2E encrypted relay — Rust + Axum
```

## Data Flow

```
AI Agent (Claude Code, Gemini CLI, Aider, etc.)
    │
    ▼
PTY stdout
    │
    ▼
VT100 Parser (Rust) ── Parse ANSI/SGR/OSC/256-color/RGB
    │
    ▼
Dirty Region Diff ──── Extract only changed cells
    │
    ▼
Binary Frame ────────── [1B type][4B length][JSON payload]
    │
    ▼
WebSocket broadcast ── 60fps throttle, broadcast to all clients
    │
    ▼
Client Render ───────── Metal GPU (macOS/iOS) / Compose (Android)
```

## Tech Stack

| Component | Stack | Details |
|-----------|-------|---------|
| **Terminal Server** | Rust, Tokio, portable-pty | Custom VT100 parser (1500+ LOC), incremental dirty-region diffing |
| **Relay Server** | Rust, Axum, SQLite | Zero-knowledge relay, AES-256-GCM, JWT + Argon2 |
| **macOS Client** | Swift 5.9, SwiftUI, [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT) | Terminal emulation via SwiftTerm, multi-tab + split pane, 7 built-in themes |
| **iOS Client** | Swift 5.9, UIKit, Metal | 60fps Metal rendering, custom mobile keyboard |
| **Android Client** | Kotlin, Jetpack Compose | Material3 design |

## Protocol

Binary frame format for minimal overhead:

```
┌──────────┬──────────────┬─────────────────┐
│ Type (1B)│ Length (4B LE)│ JSON Payload    │
└──────────┴──────────────┴─────────────────┘
```

### Frame Types

| Type | Direction | Purpose |
|------|-----------|---------|
| `0x01` | → Server | Keyboard input |
| `0x02` | → Server | Subscribe to session |
| `0x03` | → Server | Create session |
| `0x04` | → Server | Resize terminal |
| `0x05` | → Server | Close session |
| `0x10` | ← Client | Screen output (incremental) |
| `0x11` | ← Client | Cursor update |
| `0x12` | ← Client | Mode update |
| `0x13` | ← Client | Session created |
| `0x14` | ← Client | Session closed |
| `0x15` | ← Client | Error |
| `0x16` | ← Client | Raw output |
| `0x17` | ← Client | Negotiate |
| `0x20` | ↔ | Ping |
| `0x21` | ↔ | Pong |

Full protocol definition: [`vibing-macos/vibing-server/src/protocol.rs`](../vibing-macos/vibing-server/src/protocol.rs)

## Security Model

```
Your Mac ←── AES-256-GCM ──→ Relay ←── AES-256-GCM ──→ Your Phone
                               │
                          Sees nothing.
                          Stores nothing.
                          Knows nothing.
```

- Per-session symmetric keys, generated during device pairing
- Relay is a **blind forwarder** — zero-knowledge architecture
- Plaintext never leaves your device
- Fully self-hostable — trust no one but yourself
- Password hashing: Argon2
- Authentication: JWT tokens

## Key Source Files

### Terminal Server (Rust)

| File | LOC | Purpose |
|------|-----|---------|
| `server.rs` | 958 | WebSocket server, event-driven broadcast, 60fps throttle |
| `pty.rs` | 775 | PTY session management, integrated with VT100 parser |
| `vt100.rs` | 1572 | Full VT100/ANSI parser (CSI, SGR, OSC, 256-color + RGB) |
| `protocol.rs` | 1063 | Binary frame protocol definitions |
| `render.rs` | 320 | Incremental renderer, per-line dirty-region detection |
| `relay_client.rs` | 422 | Relay connection client, AES-256-GCM encryption |
| `config.rs` | 57 | Configuration handling |

### Relay Server (Rust)

| File | LOC | Purpose |
|------|-----|---------|
| `main.rs` | 443 | Axum HTTP + WebSocket server |
| `api.rs` | 388 | REST API endpoints |
| `auth.rs` | 227 | JWT authentication |
| `crypto.rs` | 196 | AES-256-GCM encryption |
| `db.rs` | 205 | SQLite database |
| `protocol.rs` | 123 | Protocol definitions |

### macOS Client (Swift)

| Directory | Key Files | Purpose |
|-----------|-----------|---------|
| `Models/` | TabManager, ThemeManager, AccountManager | State management |
| `Views/` | ContentView, WorkingTerminalView, CommandPaletteView | SwiftUI views |
| `Rendering/` | SwiftTerminalView, OptimizedMetalRenderer | Terminal rendering |
| `Network/` | TerminalWebSocketClient, BinaryProtocolEncoder | Communication |

### iOS Client (Swift)

| Directory | Key Files | Purpose |
|-----------|-----------|---------|
| `Metal/` | MetalRenderer, GlyphCache, TerminalState | GPU rendering |
| `Network/` | WebSocketClient, TerminalSyncEngine, RelayClient | Communication |
| `ViewControllers/` | TerminalViewerController, ConnectionViewController | UIKit controllers |

## Build & Test

### Prerequisites

| Component | Requirements |
|-----------|-------------|
| macOS client | macOS 13.0+, Xcode 15+, Swift 5.9 |
| iOS client | iOS 15.0+, Xcode 15+ |
| Android client | Android Studio, SDK 26+ |
| Rust components | Rust 1.70+ (2021 edition) |

### Commands

```bash
# macOS client
cd vibing-macos && swift build

# Terminal server
cd vibing-macos/vibing-server && cargo build --release
cd vibing-macos/vibing-server && cargo run -- --bind 127.0.0.1:8765

# Relay server
cd vibing-relay && cargo build --release

# Tests
cd vibing-macos/vibing-server && cargo test    # 24 tests
cd vibing-relay && cargo test
```

## Notes

- Swift `Color` conflicts with `TerminalProtocol.swift`'s `Color` enum — use `SwiftUI.Color` in UI code
- `vibing-server/` and `VibeTerminal/` are excluded from Swift compilation in Package.swift
- PTYTypes.swift and PTYSession.swift have type overlap — only PTYSession.swift is compiled
