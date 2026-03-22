# Vibe Terminal Server

多端终端同步服务器 - 主端（电脑/服务器）

## 功能

- ⚡ 启动和管理 PTY 会话
- 🔄 通过 WebSocket 广播终端输出
- 📡 支持多客户端同时连接
- 🎨 增量帧传输，节省带宽
- 🔒 端到端加密传输

## 安装运行

```bash
# 克隆项目
git clone <your-repo>

# 进入目录
cd VibeTerminal-Server

# 运行
cargo run -- --bind 0.0.0.0:8765

# 或指定配置
cargo run -- --config config.toml
```

## 配置文件

创建 `config.toml`:

```toml
bind = "0.0.0.0:8765"
default_shell = "/bin/bash"

max_sessions = 10
idle_timeout_minutes = 30

[default_env]
TERM = "xterm-256color"
LANG = "en_US.UTF-8"
```

## 协议

### 客户端 → 服务器

```
0x01 - Input
  - session_id: string
  - data: bytes
```

### 服务器 → 客户端

```
0x02 - SessionOutput
  - session_id: string
  - frame: ScreenFrame (JSON)

0x03 - CursorUpdate
  - CursorFrame (JSON)

0x04 - ModeUpdate
  - ModeFrame (JSON)

0x05 - Ping
0x06 - Pong
```

## 开发

```bash
# 构建
cargo build

# 运行测试
cargo test

# 本地运行
cargo run
```

## 依赖

- Tokio - 异步运行时
- portable-pty - 跨平台 PTY
- tokio-tungstenite - WebSocket
- serde - 序列化

## 许可证

MIT
