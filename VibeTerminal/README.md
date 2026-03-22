# VibeTerminal - macOS 终端应用

使用 SwiftUI + Metal 构建的现代化终端应用，支持多设备同步。

## 功能特性

- ✅ **Metal 渲染** - 高性能 GPU 加速终端渲染
- ✅ **账号体系** - 基于密钥对的账号管理
- ✅ **二维码配对** - 扫码即可连接其他设备
- ✅ **端到端加密** - 通过中继服务器的安全连接
- ✅ **多设备支持** - Mac, iOS, Android, Web

## 项目结构

```
VibeTerminal/
├── VibeTerminalApp.swift      # 主应用入口
├── Models/
│   └── AccountManager.swift    # 账号和配对管理
├── Views/
│   ├── ContentView.swift        # 主界面
│   └── SettingsView.swift       # 设置界面
└── Rendering/
    └── TerminalMetalView.swift  # Metal 渲染视图
```

## 构建方式

### 使用 Xcode

1. 打开 Xcode
2. 创建新的 macOS App 项目
3. 选择 SwiftUI 作为界面框架
4. 将上述文件添加到项目中
5. 确保 Deployment Target 设置为 macOS 13.0+
6. 构建运行

### 使用 Swift Package Manager

```bash
cd /Volumes/NBDATA/PersonalProjects/YiY/VibeTerminal
swift build
```

## 配对流程

1. **桌面端生成配对码**
   - 打开 Settings → Account
   - 点击 "Show QR Code"
   - 二维码包含：版本 + 账号ID + 设备ID + 时间戳 + 签名

2. **移动端扫描配对码**
   - 打开 Vibe iOS 应用
   - 点击 "Scan QR Code"
   - 扫描桌面端显示的二维码

3. **配对确认**
   - 桌面端收到配对请求
   - 点击 Accept 确认
   - 设备配对成功

## 后端依赖

应用需要 `vibe-terminal-server` 后台运行：

```bash
/Volumes/NBDATA/PersonalProjects/YiY/vibing-server/target/release/vibe-terminal-server
```

默认监听端口：`127.0.0.1:8765`

## 开发计划

- [ ] 完成 Metal 渲染管线
- [ ] 实现 PTY 会话管理
- [ ] 添加 VT100/ANSI 解析
- [ ] 完善配对流程 UI
- [ ] 添加中继连接支持
- [ ] 端到端测试

## 许可证

MIT
