//
//  AppDelegate.swift
//  VibeTerminal
//
//  Application Delegate
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    private var backendProcess: Process?
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // 启动 Rust 后端
        startBackend()

        // 设置窗口样式
        if let window = NSApp.windows.first {
            window.title = "Vibing"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            self.window = window
        }
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

        let contentView = ContentView()
        window.contentView = NSHostingView(rootView: contentView)
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: - Backend Management

    private func startBackend() {
        let backendURL = Bundle.main.url(forResource: "vibing-server", withExtension: nil)

        guard let backendPath = backendURL?.path else {
            print("Backend executable not found, using bundled path")

            // 开发模式：使用构建目录
            let devPath = "/Volumes/NBDATA/PersonalProjects/YiY/vibing-server/target/release/vibing-server"
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

        // 配置环境
        process.arguments = [
            "--bind", "127.0.0.1:8765",
            "--log", "info"
        ]

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
}
