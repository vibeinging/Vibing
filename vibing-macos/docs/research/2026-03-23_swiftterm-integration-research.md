# SwiftTerm 作为 Vibing 纯渲染引擎的集成调研

## 调研结论摘要

**SwiftTerm 完全可以作为纯渲染引擎使用**，且这正是其官方推荐的用法之一。SwiftTerm 的架构将终端引擎（`Terminal`）与 UI 视图（`TerminalView`）完全解耦，并通过 delegate 模式实现数据流的双向重定向。这与 Vibing 的 WebSocket 远程渲染架构高度匹配。

---

## 1. SwiftTerm 能否作为纯渲染引擎？

### 结论：完全可以

SwiftTerm 明确支持三种使用模式：

| 模式 | 类 | 用途 |
|------|-----|------|
| 本地终端 | `LocalProcessTerminalView` | 连接本地 PTY（macOS only） |
| **自定义数据源** | **`TerminalView` + `TerminalViewDelegate`** | **连接 SSH、WebSocket 等远程数据源** |
| 无头模式 | `HeadlessTerminal` | 无 UI，纯引擎，用于脚本/测试 |

Vibing 应使用第二种模式：直接使用 `TerminalView`，不使用 `LocalProcessTerminalView`。

### 关键 API

**feed 数据（WebSocket -> 终端渲染）：**
```swift
// 将 VT100/ANSI 字节流直接喂给 TerminalView 渲染
terminalView.feed(byteArray: ArraySlice<UInt8>)  // 二进制数据
terminalView.feed(text: String)                    // 文本数据
```

`feed()` 方法可以从**后台线程**调用，内部会处理线程安全。数据直接传递给内部的 `Terminal` 引擎解析 VT100/ANSI 序列并更新屏幕状态。

**拦截键盘输入（终端 -> WebSocket）：**
```swift
// TerminalViewDelegate 的 send 回调
func send(source: TerminalView, data: ArraySlice<UInt8>) {
    // 用户键盘输入会触发这个回调
    // 将 data 通过 WebSocket 发送到 Rust 服务端
    webSocketClient.send(data: data)
}
```

**无需创建本地 PTY**：`TerminalView` 本身不创建任何 PTY，PTY 管理完全在 `LocalProcessTerminalView`（子类）中。直接使用 `TerminalView` 就是纯渲染器。

---

## 2. SwiftTerm 架构分析

### 层次结构

```
Terminal (纯引擎, 跨平台)
  ├── VT100/ANSI 解析器 (EscapeSequenceParser)
  ├── Buffer 管理 (Buffer, BufferLine, CharData)
  ├── 颜色系统 (Colors, Attribute)
  └── 搜索引擎 (SearchService)

TerminalView (UI 层, 平台相关)
  ├── macOS: NSView 子类 (Mac/MacTerminalView.swift)
  ├── iOS: UIScrollView 子类 (iOS/iOSTerminalView.swift)
  ├── 共享渲染逻辑 (Apple/AppleTerminalView.swift)
  └── Metal GPU 渲染 (Apple/Metal/)

LocalProcessTerminalView (本地 PTY 连接, 仅 macOS)
  └── 继承 TerminalView, 添加 LocalProcess
```

### 关键解耦点

1. **`Terminal` 类**是纯逻辑引擎，不依赖任何 UI 框架
2. **`TerminalView`** 通过 `TerminalDelegate` 协议与 `Terminal` 交互
3. **`TerminalViewDelegate`** 协议是应用层与 UI 层的接口
4. **`LocalProcess`** 是可选组件，仅 `LocalProcessTerminalView` 使用

### TerminalViewDelegate 回调

```swift
public protocol TerminalViewDelegate: AnyObject {
    // 用户输入数据 -> 发送到后端（Vibing: 发到 WebSocket）
    func send(source: TerminalView, data: ArraySlice<UInt8>)

    // 终端尺寸变化（Vibing: 通知服务端调整 PTY 大小）
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int)

    // 标题变化
    func setTerminalTitle(source: TerminalView, title: String)

    // 当前目录变化 (OSC 7)
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?)

    // 滚动位置变化
    func scrolled(source: TerminalView, position: Double)

    // 链接点击
    func requestOpenLink(source: TerminalView, link: String, params: [String:String])

    // 铃声
    func bell(source: TerminalView)

    // 剪贴板 (OSC 52)
    func clipboardCopy(source: TerminalView, content: Data)

    // 屏幕内容变化通知
    func rangeChanged(source: TerminalView, startY: Int, endY: Int)
}
```

---

## 3. 与 Vibing WebSocket 集成方案

### 数据流映射

```
Vibing 当前架构:
  Rust PTY stdout → WebSocket → Client → ???渲染???

SwiftTerm 集成后:
  Rust PTY stdout → WebSocket → terminalView.feed(byteArray:)

  用户键盘 → TerminalViewDelegate.send() → WebSocket → Rust PTY stdin

  终端 resize → TerminalViewDelegate.sizeChanged() → WebSocket → Rust PTY resize
```

### 集成代码骨架（概念）

```swift
class VibingTerminalController: TerminalViewDelegate {
    var terminalView: TerminalView!
    var webSocket: WebSocketClient!

    // WebSocket 收到数据 -> feed 给 SwiftTerm 渲染
    func onWebSocketData(_ data: Data) {
        let bytes = Array(data)
        terminalView.feed(byteArray: bytes[...])
    }

    // SwiftTerm 键盘输入 -> 发到 WebSocket
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        webSocket.send(data: Data(data))
    }

    // 终端 resize -> 通知服务端
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        webSocket.sendResize(cols: newCols, rows: newRows)
    }
}
```

### 协议适配问题

**当前 Vibing 服务端发送 JSON 增量帧**（ScreenFrame + 脏区域），而 SwiftTerm 的 `feed()` 接收的是**原始 VT100/ANSI 字节流**。

两种解决方案：

| 方案 | 描述 | 优缺点 |
|------|------|--------|
| A: 服务端发送原始字节流 | Rust 端将 PTY stdout 原始数据直接 WebSocket 广播 | 简单直接，SwiftTerm 自己做 VT100 解析；但失去增量优化 |
| B: 保留 JSON 协议 | 客户端将 JSON ScreenFrame 转换为 VT100 序列再 feed | 复杂，等于做两次解析（服务端解析+客户端重建），不推荐 |

**推荐方案 A**：让 Rust 服务端直接转发 PTY 的原始字节流。SwiftTerm 内置了完整的 VT100/ANSI 解析器（支持 CSI、SGR、OSC、256色、TrueColor、Sixel、Kitty 图形协议等），比 Vibing 自己的解析器更完善。这意味着：
- 移除 Vibing 客户端的 VT100Parser、TerminalState、DirtyRegions 等代码
- 移除 Vibing 客户端的 Metal 渲染代码（使用 SwiftTerm 内置的 Metal 渲染器）
- Rust 服务端简化为 PTY 管理 + WebSocket 转发

---

## 4. 字体/主题控制

### 字体

```swift
// macOS - 设置字体
terminalView.font = NSFont(name: "SF Mono", size: 14)!

// iOS - 设置字体
terminalView.font = UIFont(name: "Menlo", size: 14)!

// iOS - 分别设置各变体
terminalView.setFonts(normal: normalFont, bold: boldFont, italic: italicFont, boldItalic: boldItalicFont)

// 重置为默认字体
terminalView.resetFontSize()
```

字体变更时 SwiftTerm 会自动重新计算 cell 尺寸并触发 resize。

### 颜色/主题

```swift
// 前景/背景色
terminalView.nativeForegroundColor = NSColor.white
terminalView.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)

// 安装自定义 16 色 ANSI 调色板
terminalView.installColors([
    Color(red8: 0x2e, green8: 0x34, blue8: 0x36),  // color 0
    Color(red8: 0xcc, green8: 0x00, blue8: 0x00),  // color 1
    // ... 共 16 个
])

// 选中文本背景色
terminalView.selectedTextBackgroundColor = NSColor.systemBlue.withAlphaComponent(0.3)

// 光标颜色
terminalView.caretColor = NSColor.systemGreen
terminalView.caretTextColor = NSColor.black

// 光标样式
// 通过 TerminalOptions 设置初始样式，或由远程应用通过转义序列控制
```

内置调色板：`paleColors`、`vgaColors`、`terminalAppColors`。

### 渲染选项

```swift
// 自定义方块/线条绘制字符（通常比字体自带的更准确）
terminalView.customBlockGlyphs = true
terminalView.antiAliasCustomBlockGlyphs = true

// 粗体文本使用亮色
terminalView.useBrightColors = true
```

---

## 5. macOS 和 iOS 支持

### macOS (AppKit)

- `TerminalView` 是 `NSView` 子类
- 嵌入 SwiftUI 使用 `NSViewRepresentable`：

```swift
struct TerminalViewWrapper: NSViewRepresentable {
    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        return view
    }
    func updateNSView(_ nsView: TerminalView, context: Context) {}
    func makeCoordinator() -> TerminalCoordinator { ... }
}
```

### iOS (UIKit)

- `TerminalView` 是 `UIScrollView` 子类
- 嵌入 SwiftUI 使用 `UIViewRepresentable`
- SwiftTerm 仓库中有一个内部测试用的 `SwiftUITerminalView` 可参考
- 支持 `UIKeyInput` 协议处理键盘输入
- 有内置的辅助键盘视图 (`iOSAccessoryView`)

### Metal GPU 渲染（macOS + iOS）

两个平台都支持可选的 Metal 渲染：

```swift
try terminalView.setUseMetal(true)
terminalView.metalBufferingMode = .perRowPersistent  // 或 .perFrameAggregated
```

特性支持：
- 所有文本属性（粗体、斜体、下划线、删除线、暗淡、反转、闪烁）
- 下划线样式：单线、双线、波浪线、点线、虚线
- ANSI、256色、TrueColor
- 光标渲染和闪烁
- 选择高亮
- 内联图片（Sixel、iTerm2、Kitty 图形协议）
- 自定义方块元素和框线字符
- Emoji 和彩色字形渲染

---

## 6. 集成对 Vibing 架构的影响

### 可以移除的 Vibing 代码

| 现有模块 | 状态 | 原因 |
|----------|------|------|
| `VT100Parser.swift` | 移除 | SwiftTerm 内置更完善的解析器 |
| `TerminalProtocol.swift` | 简化 | 不再需要 ScreenFrame/Cell 类型 |
| `OptimizedMetalRenderer.swift` | 移除 | 使用 SwiftTerm Metal 渲染器 |
| `TerminalMetalView.swift` | 移除 | 使用 SwiftTerm TerminalView |
| `Shaders.metal` | 移除 | 使用 SwiftTerm 内置着色器 |
| `WorkingTerminalView.swift` | 重写 | 改为包装 SwiftTerm TerminalView |

### 需要修改的 Rust 服务端

- 添加"原始字节流转发"模式：PTY stdout -> WebSocket（不做 VT100 解析）
- 保留现有的 JSON 增量协议作为备选（兼容性）
- 或者在服务端同时支持两种模式，客户端在连接时协商

### SPM 依赖

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
]
```

平台要求：macOS 13.0+, iOS 14.0+（与 Vibing 兼容）

---

## 7. 风险和注意事项

1. **协议变更成本**：切换到原始字节流意味着 Rust 服务端的增量渲染优化（脏区域检测、按行合并）变得无用。但 SwiftTerm 自身的渲染性能已经很好（有 Metal GPU 渲染），这些优化可能本就不需要在协议层做。

2. **SwiftTerm 的 `Color` 类型冲突**：SwiftTerm 定义了自己的 `Color` 类型（`SwiftTerm.Color`），会与 `SwiftUI.Color` 冲突。需要在代码中使用完整限定名。（注：Vibing 现有代码已有此问题并已知如何处理。）

3. **多会话同步**：Vibing 的核心场景是多设备共享。使用原始字节流转发时，新加入的客户端需要"追赶"当前状态。方案：
   - 服务端缓存最近的 N 字节数据，新客户端连接时先发送缓存
   - 或服务端维护一个终端快照，新客户端连接时先发送完整屏幕状态

4. **输入冲突**：多个客户端同时输入时需要服务端做仲裁，这与当前架构一致，不受 SwiftTerm 集成影响。

5. **visionOS 支持**：SwiftTerm 支持 visionOS 1.0+，这为 Vibing 未来扩展到 Apple Vision Pro 提供了可能。
