# Vibing 系统设计文档

> 日期: 2026-03-23
> 目标: 极致性能 · 功能完整 · 用户友好 · 现代化界面

---

## 一、当前状态总结

### 整体完成度

| 组件 | 完成度 | 关键阻塞 |
|------|--------|----------|
| vibing-server (Rust) | 60% | 🔴 PTY 输出未广播到客户端；VT100 解析器已实现但未集成 |
| vibing-macos (Swift) | 70% | 终端视图仍是占位符；UI 未接入 Metal 渲染 |
| vibing-ios (Swift) | 70% | 无 Xcode 项目；连接逻辑为 mock |
| vibing-relay (Rust) | 90% | 基本就绪，crypto 模块未接入 |

### 🔴 致命问题

1. **服务端 PTY 输出从未发送到客户端** — `server.rs` 的输出读取任务是空循环，客户端收不到任何终端数据
2. **完整的 VT100 解析器 (50KB) 写好了但没接入** — `pty.rs` 仅处理基础控制字符
3. **macOS 终端视图是占位符** — ContentView 显示 "Vibe Terminal v1.0" 静态文本
4. **存在重复文件** — TerminalMetalView.swift 等存在两份

---

## 二、架构设计

### 2.1 系统架构

```
┌─────────────────────────────────────────────────────┐
│                    vibing-macos                       │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ SwiftUI  │  │  Metal   │  │  vibing-server    │  │
│  │   Views  │←→│ Renderer │  │  (Rust subprocess) │  │
│  └────┬─────┘  └────┬─────┘  │  ┌─────────────┐  │  │
│       │              │        │  │ PTY Manager │  │  │
│       └──────┬───────┘        │  │ + VT100     │  │  │
│              │                │  └──────┬──────┘  │  │
│     TerminalViewModel         │         │         │  │
│              │                │  ┌──────┴──────┐  │  │
│     ┌────────┴────────┐      │  │  WebSocket  │  │  │
│     │  WebSocket Client│←────┼──│   Server    │  │  │
│     └─────────────────┘      │  └─────────────┘  │  │
│                               └───────────────────┘  │
└──────────────────────────────────────────────────────┘
                        │
                   WebSocket (WAN)
                        │
              ┌─────────┴──────────┐
              │    vibing-relay     │
              │  (E2E encrypted)   │
              └─────────┬──────────┘
                        │
           ┌────────────┼────────────┐
           │                         │
    ┌──────┴──────┐          ┌──────┴──────┐
    │ vibing-ios  │          │ vibing-web  │
    │  (UIKit +   │          │  (Future)   │
    │   Metal)    │          │             │
    └─────────────┘          └─────────────┘
```

### 2.2 数据流

```
PTY stdout → VT100Parser → TerminalState → DirtyRegions → ScreenFrame → WebSocket → Client
Client KeyPress → WebSocket → Server → PTY stdin
```

### 2.3 核心设计原则

| 原则 | 实现方式 |
|------|----------|
| **零拷贝传输** | 本地: SharedMemory IPC; 远程: 二进制协议 + 增量脏区域 |
| **GPU 优先渲染** | Metal instanced rendering, 4096×4096 glyph atlas |
| **增量更新** | 仅传输变化的 cell 区域，非全屏刷新 |
| **异步全链路** | Tokio async runtime (Rust) + Swift async/await |
| **端到端加密** | AES-256-GCM，中继服务器零知识 |

---

## 三、功能规划

### Phase 1 — 核心打通 (Critical Path)

> 目标：macOS 客户端能完整显示终端并交互

#### P1.1 服务端修复
- [ ] **集成 VT100 解析器到 pty.rs** — 将 `vt100.rs` 的完整解析器接入 PTY 输出处理
- [ ] **修复 PTY 输出广播** — `server.rs` 输出读取任务要实际读取 PTY 数据、生成 ScreenFrame、广播到已订阅客户端
- [ ] **接通事件通道** — PTY reader → event channel → broadcast handler
- [ ] **实现 resize 协议** — 客户端窗口调整时同步到 PTY
- [ ] **添加心跳检测** — Ping/Pong 检测死连接

#### P1.2 macOS 客户端集成
- [ ] **替换 ContentView 占位符** — 接入 TerminalMetalView + TerminalInputView
- [ ] **统一重复文件** — 合并两份 TerminalMetalView.swift，保留更完整的版本
- [ ] **接通数据流** — WebSocketClient → TerminalViewModel → Metal Renderer
- [ ] **连接状态实时化** — ConnectionStatusIndicator 接入实际 WebSocket 状态
- [ ] **修复后端路径** — 更新 AppDelegate 中的 vibing-server 启动路径

### Phase 2 — 完整终端体验

> 目标：达到日常使用终端的完整功能

#### P2.1 终端功能
- [ ] 滚动回看 (scrollback buffer) — 鼠标/触控板滚动查看历史
- [ ] 文本选择与复制 — 鼠标拖选、Cmd+C 复制
- [ ] 搜索终端内容 — Cmd+F 搜索当前 buffer
- [ ] 多 Tab 支持 — 多个终端会话标签页
- [ ] 分屏 (Split Pane) — 水平/垂直分割终端
- [ ] URL 检测与点击 — 识别并高亮可点击链接
- [ ] 图片协议支持 — iTerm2/Kitty 图片协议 (可选)

#### P2.2 性能优化
- [ ] 优化脏区域合并算法 — render.rs 中的 extend_dirty_region 改为智能合并
- [ ] 大量输出节流 — 高速输出时合并帧，避免客户端过载
- [ ] SharedMemory IPC 激活 — 本地通信从 WebSocket 切换到零拷贝共享内存
- [ ] Glyph atlas 按需扩展 — 遇到未缓存字符时动态加载

### Phase 3 — 现代化 UI

> 目标：美观、流畅、直觉化

#### P3.1 界面设计

**窗口布局:**
```
┌─────────────────────────────────────────────────┐
│ ● ● ●          Vibing          [+] [⚙]         │  ← 自定义标题栏，半透明
├─────┬───────────────────────────────────────────┤
│     │  Tab1  │  Tab2  │  Tab3  │                │  ← 标签栏
│  S  ├────────────────────┬──────────────────────┤
│  i  │                    │                      │
│  d  │   Terminal Pane 1  │   Terminal Pane 2    │  ← 可分割面板
│  e  │                    │                      │
│  b  │   $ ls -la         │   $ htop             │
│  a  │   drwxr-xr-x ...  │   CPU [||||    ] 45% │
│  r  │   -rw-r--r-- ...  │   MEM [||||||  ] 72% │
│     │                    │                      │
│  📱 ├────────────────────┴──────────────────────┤
│  💻 │ user@host:~/project                 zsh   │  ← 状态栏
│     │                                           │
└─────┴───────────────────────────────────────────┘
```

**设计语言:**
- 半透明毛玻璃标题栏 (NSVisualEffectView, .behindWindow)
- 侧边栏显示已配对设备，带在线状态指示
- 终端配色方案跟随系统暗色/亮色
- 流畅的 120fps Metal 渲染 (ProMotion 支持)
- 自定义字体渲染，支持连字 (ligature)

**主题系统:**
- 内置经典主题：Dracula, One Dark, Solarized, Nord, Tokyo Night, Catppuccin
- 自定义主题 (前景、背景、16 色 ANSI + 亮色)
- 背景透明度/模糊度可调
- 字体选择 + 大小 + 行高 + 字间距

#### P3.2 交互细节
- 标签页拖拽排序、拖出独立窗口
- 分屏拖拽调整比例
- 终端内容选中高亮动画
- 连接/断开状态动画过渡
- 输入命令时的微交互反馈
- Touch Bar 支持 (如有)

### Phase 4 — 多设备同步

> 目标：任何设备随时接入

#### P4.1 配对与连接
- [ ] 完善 QR 码配对流程 — 生成、扫描、确认全链路
- [ ] 设备管理 — 查看、重命名、移除已配对设备
- [ ] 自动发现 — 同一局域网内自动发现其他 Vibing 设备 (Bonjour/mDNS)
- [ ] 连接恢复 — 断线后自动重连并同步终端状态

#### P4.2 iOS 客户端
- [ ] 创建 Xcode 项目，配置签名和 Bundle ID
- [ ] 接入真实 WebSocket 连接 (替换 mock)
- [ ] 优化移动端键盘体验 — 自定义快捷键栏、手势
- [ ] iPad 分屏适配 — Slide Over / Split View
- [ ] 低延迟体验 — 预测性输入回显

#### P4.3 中继服务
- [ ] 接入 crypto.rs 的 Diffie-Hellman 密钥交换
- [ ] 会话持久化 — 断线重连不丢失会话
- [ ] 多区域部署支持 — 选择最近的中继节点

### Phase 5 — 高级功能

- [ ] Shell 集成 — 命令完成检测、退出码显示、命令耗时
- [ ] 通知系统 — 长时间命令完成后通知 (macOS + iOS 推送)
- [ ] 快捷命令面板 — Cmd+K 命令面板 (类 Spotlight)
- [ ] AI 终端助手 — 选中命令输出后智能解释 (可选)
- [ ] 录制与回放 — 终端会话录制为 asciicast
- [ ] 多人协作 — 多用户同时查看/操作同一终端

---

## 四、技术决策

### 4.1 为什么选择 Metal 而不是 CoreText/AttributedString?

| | Metal | CoreText |
|---|-------|----------|
| 渲染延迟 | ~0.5ms/帧 | ~5-15ms/帧 |
| GPU 利用率 | 高 (instanced draw) | 低 (CPU 光栅化) |
| 大屏幕表现 | 线性扩展 | 性能退化 |
| 自定义着色 | 完全可控 | 受限 |
| 复杂度 | 高 | 低 |

→ 选择 Metal：终端需要高帧率、低延迟，尤其在大量文本滚动时

### 4.2 为什么 Rust 做后端?

- PTY 管理需要精确的系统调用控制
- 内存安全 + 零开销抽象
- Tokio 异步模型适合高并发 WebSocket
- 未来可直接编译为 Linux 独立服务

### 4.3 本地通信策略

| 方式 | 延迟 | 吞吐 | 适用场景 |
|------|------|------|----------|
| SharedMemory (已实现) | ~1μs | 极高 | macOS 本地 |
| WebSocket (已实现) | ~0.5ms | 高 | 默认 / 跨网络 |
| Unix Domain Socket | ~10μs | 高 | 本地替代方案 |

→ Phase 1 先用 WebSocket 打通；Phase 2 激活 SharedMemory 以获得极致本地性能

### 4.4 协议设计

```
帧格式: [1B type] [4B length (LE)] [payload (bincode)]

增量更新策略:
- 全屏帧: 首次连接 / resize 后
- 增量帧: 仅发送 dirty regions
- 帧合并: 高速输出时服务端合并多次变更为单帧
- 序列号: 客户端检测丢帧并请求全屏帧
```

---

## 五、实施优先级

```
Phase 1 (核心打通)     ████████████████████  ← 最高优先
Phase 2 (完整终端)     ███████████████
Phase 3 (现代化UI)     ████████████          ← 可与 Phase 2 并行
Phase 4 (多设备同步)   █████████
Phase 5 (高级功能)     █████
```

**Phase 1 是唯一阻塞项** — 不修复服务端广播和客户端集成，后续所有功能都无法验证。
