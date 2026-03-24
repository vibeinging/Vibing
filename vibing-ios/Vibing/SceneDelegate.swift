//
//  SceneDelegate.swift
//  Vibing
//
//  场景代理 - 处理窗口和界面生命周期 + Deep Link
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: windowScene)

        if AccountManager.shared.isSignedIn {
            showMainApp()
        } else {
            showLogin()
        }

        window?.makeKeyAndVisible()

        // 处理冷启动时的 URL
        if let urlContext = connectionOptions.urlContexts.first {
            handleDeepLink(urlContext.url)
        }
    }

    // App 已运行时收到 URL
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleDeepLink(url)
    }

    // MARK: - Deep Link: vibing://login?server=...&code=...

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "vibing" else { return }

        switch url.host {
        case "login":
            handleQRLogin(url)
        default:
            break
        }
    }

    private func handleQRLogin(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let params = components.queryItems else { return }

        let server = params.first(where: { $0.name == "server" })?.value
        let code = params.first(where: { $0.name == "code" })?.value

        guard let server = server, !server.isEmpty,
              let code = code, !code.isEmpty else { return }

        // 显示登录进度
        let loadingVC = QRLoginLoadingViewController(server: server, code: code)
        loadingVC.onSuccess = { [weak self] in
            self?.showMainApp()
        }
        loadingVC.onFailure = { [weak self] error in
            self?.showLogin()
            // 延迟弹出错误提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = UIAlertController(title: L("common.error"), message: error, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
                self?.window?.rootViewController?.present(alert, animated: true)
            }
        }
        window?.rootViewController = loadingVC
    }

    // MARK: - Navigation

    func showLogin() {
        let loginVC = LoginViewController()
        loginVC.onLoginSuccess = { [weak self] in
            self?.showMainApp()
        }
        window?.rootViewController = loginVC
    }

    func showMainApp() {
        let deviceListVC = DeviceListViewController()
        let nav = UINavigationController(rootViewController: deviceListVC)
        configureNavigationBar(nav)

        // 平滑过渡
        if let window = window, window.rootViewController != nil {
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: {
                window.rootViewController = nav
            })
        } else {
            window?.rootViewController = nav
        }
    }

    func showTerminalViewer() {
        let vc = TerminalViewerController(serverURL: "ws://mock", sessionCode: "mock")
        let nav = UINavigationController(rootViewController: vc)
        nav.isNavigationBarHidden = true
        window?.rootViewController = nav
    }

    private func configureNavigationBar(_ nav: UINavigationController) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.tintColor = UIColor(red: 106/255, green: 194/255, blue: 120/255, alpha: 1)
    }
}
