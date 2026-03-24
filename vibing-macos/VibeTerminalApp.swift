//
//  VibeTerminalApp.swift
//  VibeTerminal
//
//  主应用入口
//

import SwiftUI
import AppKit

/// 通过 NotificationCenter 发送菜单动作
private func postMenuAction(_ action: String) {
    NotificationCenter.default.post(name: .init("MenuAction"), object: action)
}

@main
struct VibeTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")

    var body: some Scene {
        WindowGroup {
            if onboardingCompleted {
                MainWindowRepresentable()
                    .frame(minWidth: 800, minHeight: 500)
            } else {
                OnboardingView(isCompleted: $onboardingCompleted)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            let zh = AppLanguage.current == .chinese

            // MARK: App Menu
            CommandGroup(replacing: .appSettings) {
                Button(zh ? "设置..." : "Settings...") {
                    NotificationCenter.default.post(name: .init("OpenSettings"), object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            // MARK: File Menu
            CommandGroup(replacing: .newItem) {
                Button(zh ? "新建标签页" : "New Tab") {
                    postMenuAction("NewTab")
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button(zh ? "新建窗口" : "New Window") {
                    AppDelegate.shared.newWindow()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Button(zh ? "关闭窗格" : "Close Pane") {
                    postMenuAction("ClosePane")
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            // MARK: Edit Menu
            CommandGroup(after: .pasteboard) {
                Divider()

                Button(zh ? "查找..." : "Find...") {
                    postMenuAction("Find")
                }
                .keyboardShortcut("f", modifiers: [.command])
            }

            // MARK: View Menu
            CommandGroup(replacing: .sidebar) {
                Button(zh ? "命令面板" : "Command Palette") {
                    postMenuAction("CommandPalette")
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button(zh ? "水平分屏" : "Split Horizontal") {
                    postMenuAction("SplitHorizontal")
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button(zh ? "垂直分屏" : "Split Vertical") {
                    postMenuAction("SplitVertical")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button(zh ? "下一个窗格" : "Next Pane") {
                    postMenuAction("NextPane")
                }
                .keyboardShortcut("]", modifiers: [.command])

                Button(zh ? "上一个窗格" : "Previous Pane") {
                    postMenuAction("PreviousPane")
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button(zh ? "最大化窗格" : "Maximize Pane") {
                    postMenuAction("MaximizePane")
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])

                Divider()

                Button(zh ? "放大" : "Zoom In") {
                    postMenuAction("ZoomIn")
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button(zh ? "缩小" : "Zoom Out") {
                    postMenuAction("ZoomOut")
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button(zh ? "重置缩放" : "Reset Zoom") {
                    postMenuAction("ZoomReset")
                }
                .keyboardShortcut("0", modifiers: [.command])

                Divider()

                Button(zh ? "切换主题" : "Next Theme") {
                    postMenuAction("NextTheme")
                }

                Button(zh ? "保存布局..." : "Save Layout...") {
                    postMenuAction("SaveLaunchConfig")
                }
            }
        }
    }

    private func postMenuAction(_ name: String) {
        NotificationCenter.default.post(name: Notification.Name("MenuAction.\(name)"), object: nil)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    private var backendProcess: Process?

    var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 必须在窗口显示前设置，SPM 构建的 app 默认是后台进程
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // 启动 Rust 后端
        startBackend()

        // 窗口样式：标题栏透明，内容延伸到标题栏区域
        // 交通灯按钮嵌入我们的 tab 栏中（和 Warp 一样）
        if let window = NSApp.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.title = ""
            self.window = window
        }

        // 强制激活应用
        NSApp.activate(ignoringOtherApps: true)

        // 延迟确保终端获得焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 新架构下不需要原生输入栏，SwiftTerm 自身处理键盘
        }
    }

    private var nativeInputField: NSTextField?

    private func addNativeInputBar() {
        guard let window = NSApp.windows.first,
              let contentView = window.contentView else { return }

        let inputField = NSTextField()
        inputField.placeholderString = "Type command, press Enter"
        inputField.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        inputField.isBezeled = true
        inputField.bezelStyle = .roundedBezel
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.target = self
        inputField.action = #selector(inputFieldAction(_:))

        contentView.addSubview(inputField)
        NSLayoutConstraint.activate([
            inputField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            inputField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            inputField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            inputField.heightAnchor.constraint(equalToConstant: 28),
        ])

        self.nativeInputField = inputField
        window.makeFirstResponder(inputField)
    }

    @objc private func inputFieldAction(_ sender: NSTextField) {
        let text = sender.stringValue
        guard !text.isEmpty else { return }

        // 写日志确认被调用
        let msg = "NATIVE INPUT: '\(text)'\n"
        try? msg.write(toFile: "/tmp/vibing-native.log", atomically: false, encoding: .utf8)

        // 发送到终端 - 通过 NotificationCenter
        NotificationCenter.default.post(name: .init("TerminalInput"), object: text + "\n")
        sender.stringValue = ""
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // 保持应用运行
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 停止后端
        stopBackend()
    }

    func newWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vibing"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)

        let mainView = MainWindowRepresentable()
        window.contentView = NSHostingView(rootView: mainView)
    }

    func openSettings() {
        NotificationCenter.default.post(name: .init("OpenSettings"), object: nil)
    }

    // MARK: - Backend Management

    private func startBackend() {
        let backendURL = Bundle.main.url(forResource: "vibing-server", withExtension: nil)

        guard let backendPath = backendURL?.path else {
            print("Backend executable not found, using bundled path")

            // 开发模式：使用构建目录
            // 开发路径：vibing-server 现在在 vibing-macos 内部
            let currentDir = FileManager.default.currentDirectoryPath
            let possiblePaths = [
                "\(currentDir)/vibing-server/target/release/vibing-server",
                "\(currentDir)/vibing-server/target/debug/vibing-server",
                // 项目根目录的相对路径
                Bundle.main.bundlePath + "/../vibing-server/target/release/vibing-server",
                Bundle.main.bundlePath + "/../vibing-server/target/debug/vibing-server",
            ]
            let devPath = possiblePaths.first { FileManager.default.fileExists(atPath: $0) }
                ?? possiblePaths[0]
            if FileManager.default.fileExists(atPath: devPath) {
                startBackendProcess(path: devPath)
            }
            return
        }

        startBackendProcess(path: backendPath)
    }

    private func startBackendProcess(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)

        // 基础参数
        var args = [
            "--bind", "127.0.0.1:8765",
            "--log", "info"
        ]

        // Hook API: 仅当用户在设置中显式开启时启用
        let hookApiEnabled = UserDefaults.standard.bool(forKey: "hookApiEnabled")
        if hookApiEnabled {
            args.append("--hook-api")
            args.append("--hook-api-bind")
            args.append("127.0.0.1:8767")

            // 从 Keychain 读取或生成 token
            let token = Self.getOrCreateHookApiToken()
            args.append("--hook-api-token")
            args.append(token)
        }

        process.arguments = args

        // 设置工作目录
        process.currentDirectoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Vibing")

        try? FileManager.default.createDirectory(at: process.currentDirectoryURL!, withIntermediateDirectories: true)

        // 捕获输出
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            backendProcess = process
            print("Backend started: \(path)")
        } catch {
            print("Failed to start backend: \(error)")
        }
    }

    private func stopBackend() {
        backendProcess?.terminate()
        backendProcess = nil
    }

    /// 重启后端（Hook API 设置变更时调用）
    func restartBackend() {
        stopBackend()
        // 短暂延迟确保端口释放
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startBackend()
        }
    }

    // MARK: - Hook API Token (Keychain)

    private static let keychainService = "com.vibing.hook-api"
    private static let keychainAccount = "hook-api-token"

    /// 从 Keychain 获取 token，不存在则生成并存储
    static func getOrCreateHookApiToken() -> String {
        if let existing = readTokenFromKeychain() {
            return existing
        }
        let token = "vb_" + randomAlphanumeric(count: 48)
        saveTokenToKeychain(token)
        return token
    }

    /// 重新生成 token（用户点击"重新生成"按钮时）
    static func regenerateHookApiToken() -> String {
        let token = "vb_" + randomAlphanumeric(count: 48)
        saveTokenToKeychain(token)
        return token
    }

    private static func randomAlphanumeric(count: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<count).map { _ in chars.randomElement()! })
    }

    private static func readTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveTokenToKeychain(_ token: String) {
        // 先删除旧的
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // 存入新的
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: token.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
