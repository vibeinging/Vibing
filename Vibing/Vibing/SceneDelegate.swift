//
//  SceneDelegate.swift
//  Vibing
//
//  场景代理 - 处理窗口和界面生命周期
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // 创建窗口
        window = UIWindow(windowScene: windowScene)

        // 创建根视图控制器
        let connectionVC = ConnectionViewController()
        let navigationController = UINavigationController(rootViewController: connectionVC)

        // 设置导航栏样式
        configureNavigationBar(navigationController)

        // 设置根视图控制器
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()

        // 处理快捷方式或 URL（如果有）
        handleConnectionOptions(connectionOptions)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // 场景断开连接时调用
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 场景变为活动状态时调用
        // 可以在这里重新建立连接
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // 场景即将变为非活动状态时调用
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // 场景即将进入前台时调用
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // 场景已进入后台时调用
        // 可以在这里保存状态
    }

    // MARK: - Configuration

    private func configureNavigationBar(_ navigationController: UINavigationController) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        navigationController.navigationBar.compactAppearance = appearance

        // 设置导航栏.tintColor
        navigationController.navigationBar.tintColor = .systemBlue
    }

    private func handleConnectionOptions(_ options: UIScene.ConnectionOptions) {
        // 处理 URL Contexts
        if let urlContext = options.urlContexts.first {
            let url = urlContext.url
            handleURL(url)
        }

        // 处理快捷方式
        if !options.shortcutItem.isBlank {
            // 处理快捷方式
        }
    }

    private func handleURL(_ url: URL) {
        // 处理自定义 URL Scheme
        // 例如: vibing://connect?host=192.168.1.100&port=8765
        if url.scheme == "vibing" {
            // 解析 URL 参数
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            // 处理连接参数...
        }
    }
}

// MARK: - WindowScene Extension for Quick Actions

extension UIScene.ConnectionOptions {
    var shortcutItem: NSString {
        return NSString()
    }
}
