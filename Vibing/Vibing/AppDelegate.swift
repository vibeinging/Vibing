//
//  AppDelegate.swift
//  Vibing
//
//  应用程序入口
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 设置应用全局配置
        configureApp()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // 当新场景连接时调用
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // 当场景被丢弃时调用
    }

    // MARK: - App Configuration

    private func configureApp() {
        // 配置日志
        #if DEBUG
        // 在调试模式下启用详细日志
        #endif

        // 配置 UserDefaults 默认值
        registerDefaults()

        // 配置网络
        configureNetworking()
    }

    private func registerDefaults() {
        let defaults: [String: Any] = [
            // 连接设置
            "serverAddress": "ws://192.168.1.100:8765",
            "autoReconnect": true,

            // 终端设置
            "fontSize": 14,
            "colorTheme": "dark",
            "cursorStyle": "block",

            // 高级设置
            "heartbeatInterval": 30
        ]

        UserDefaults.standard.register(defaults: defaults)
    }

    private func configureNetworking() {
        // 配置 URLSession
        URLSessionConfiguration.default
    }
}
