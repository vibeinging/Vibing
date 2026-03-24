//
//  TerminalViewController.swift
//  VibeTerminal
//
//  主终端控制器 - 支持 iPhone/iPad 响应式布局
//

import UIKit

class TerminalViewController: UIViewController {

    // MARK: - Properties

    private var terminalView: TerminalMetalView!
    private var keyboardAccessoryView: KeyboardAccessoryView?
    private var connectionBanner: ConnectionStatusBannerView?

    private var webSocketClient: WebSocketClient?
    private var currentSessionId: String?
    private var layoutConfig: LayoutManager.LayoutConfiguration!

    // 布局约束
    private var terminalViewLeadingConstraint: NSLayoutConstraint?
    private var terminalViewTrailingConstraint: NSLayoutConstraint?
    private var terminalViewTopConstraint: NSLayoutConstraint?
    private var terminalViewBottomConstraint: NSLayoutConstraint?
    private var connectionBannerHeightConstraint: NSLayoutConstraint?

    // 侧边栏 (iPad)
    private var sidebarView: UIView?
    private var sidebarWidthConstraint: NSLayoutConstraint?

    // 终端状态保存（用于横竖屏切换）
    private var savedLayoutState: LayoutState?

    private var connectionURL: String {
        UserDefaults.standard.string(forKey: "connection_url") ?? "ws://100.x.x.x:8765"
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Vibe Terminal"
        view.backgroundColor = .systemBackground

        // 获取当前布局配置
        layoutConfig = LayoutManager.LayoutConfiguration.current(for: self)

        setupViews()
        setupConstraints()
        setupKeyboardObservers()

        updateLayout(for: traitCollection)

        // 自动连接
        connect()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 确保终端视图成为第一响应者以显示键盘
        terminalView.becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        disconnect()
    }

    // MARK: - Trait Collection Changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // 检查是否需要更新布局
        if traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass ||
           traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass ||
           traitCollection.userInterfaceIdiom != previousTraitCollection?.userInterfaceIdiom {
            updateLayout(for: traitCollection)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // 保存当前终端状态
        savedLayoutState = LayoutState(
            cols: terminalView.gridCols,
            rows: terminalView.gridRows,
            scrollOffset: 0,
            cursorVisible: true
        )

        let isNewLayoutLandscape = size.width > size.height

        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updateLayout(for: self?.traitCollection ?? UITraitCollection())
        }) { [weak self] _ in
            // 旋转完成后恢复终端状态并调整 PTY 大小
            self?.handleRotationCompletion(toSize: size)
        }
    }

    // MARK: - Setup

    private func setupViews() {
        // 1. 创建连接状态横幅
        connectionBanner = ConnectionStatusBannerView()
        connectionBanner?.translatesAutoresizingMaskIntoConstraints = false
        if let banner = connectionBanner {
            view.addSubview(banner)
        }

        // 2. 创建终端视图
        terminalView = TerminalMetalView(frame: .zero)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.delegate = self
        view.addSubview(terminalView)

        // 3. 创建侧边栏 (iPad)
        if layoutConfig.showSidebar {
            setupSidebar()
        }

        // 4. 创建键盘辅助视图
        setupKeyboardAccessoryView()
    }

    private func setupSidebar() {
        let sidebar = UIView()
        sidebar.backgroundColor = .secondarySystemBackground
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebar)
        sidebarView = sidebar

        // 添加会话列表标题
        let titleLabel = UILabel()
        titleLabel.text = "Sessions"
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16)
        ])

        // TODO: 添加会话列表
    }

    private func setupKeyboardAccessoryView() {
        let deviceType = LayoutManager.deviceType(for: self)
        let layoutStyle = KeyboardAccessoryView.LayoutStylerecommendedStyle(for: deviceType)

        keyboardAccessoryView = KeyboardAccessoryView()
        keyboardAccessoryView?.updateLayout(style: layoutStyle, fontSize: layoutConfig.keyboardAccessoryFontSize)
        keyboardAccessoryView?.delegate = self
    }

    private func setupConstraints() {
        guard let banner = connectionBanner else { return }

        // 连接状态横幅约束
        connectionBannerHeightConstraint = banner.heightAnchor.constraint(equalToConstant: layoutConfig.connectionBannerHeight)
        connectionBannerHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // 终端视图约束
        terminalViewTopConstraint = terminalView.topAnchor.constraint(equalTo: banner.bottomAnchor)
        terminalViewLeadingConstraint = terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        terminalViewTrailingConstraint = terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        terminalViewBottomConstraint = terminalView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        terminalViewTopConstraint?.isActive = true
        terminalViewLeadingConstraint?.isActive = true
        terminalViewTrailingConstraint?.isActive = true
        terminalViewBottomConstraint?.isActive = true

        // 侧边栏约束 (iPad)
        if let sidebar = sidebarView {
            sidebarWidthConstraint = sidebar.widthAnchor.constraint(equalToConstant: layoutConfig.sidebarWidth)

            NSLayoutConstraint.activate([
                sidebar.topAnchor.constraint(equalTo: view.topAnchor),
                sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                sidebarWidthConstraint!
            ])

            // 调整终端视图以适应侧边栏
            terminalViewLeadingConstraint?.isActive = false
            terminalViewLeadingConstraint = terminalView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor)
            terminalViewLeadingConstraint?.isActive = true
        }
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidChangeFrame(_:)),
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil
        )
    }

    // MARK: - Layout Updates

    func updateLayout(for traitCollection: UITraitCollection) {
        // 更新布局配置
        layoutConfig = LayoutManager.LayoutConfiguration.current(for: self)

        let deviceType = LayoutManager.deviceType(for: self)

        // 更新连接横幅
        updateConnectionBanner(for: deviceType)

        // 更新侧边栏 (iPad)
        updateSidebar(for: deviceType)

        // 更新终端视图约束
        updateTerminalViewConstraints(for: deviceType)

        // 更新键盘辅助视图
        updateKeyboardAccessoryView(for: deviceType)

        // 更新终端字体大小
        updateTerminalFontSize(for: deviceType)

        // 触发布局更新动画
        UIView.animate(
            withDuration: LayoutManager.layoutAnimationDuration(for: deviceType),
            delay: 0,
            usingSpringWithDamping: LayoutManager.rotationSpringDamping(for: deviceType),
            initialSpringVelocity: 0
        ) {
            self.view.layoutIfNeeded()
        }

        // 重新计算终端网格大小
        updateTerminalGridSize()
    }

    private func updateConnectionBanner(for deviceType: LayoutManager.DeviceType) {
        guard let banner = connectionBanner else { return }

        let isCompact = deviceType == .iPhoneLandscape
        connectionBannerHeightConstraint?.constant = LayoutManager.connectionBannerHeight(for: deviceType, isCompact: isCompact)
        banner.setCompactMode(isCompact, animated: true)
    }

    private func updateSidebar(for deviceType: LayoutManager.DeviceType) {
        let shouldShowSidebar = LayoutManager.shouldShowSidebar(for: deviceType)

        if shouldShowSidebar && sidebarView == nil {
            // 需要添加侧边栏
            setupSidebar()
            setupConstraints()
        } else if !shouldShowSidebar && sidebarView != nil {
            // 移除侧边栏
            sidebarView?.removeFromSuperview()
            sidebarView = nil
            sidebarWidthConstraint = nil

            // 恢复终端视图约束
            terminalViewLeadingConstraint?.isActive = false
            terminalViewLeadingConstraint = terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            terminalViewLeadingConstraint?.isActive = true
        }

        // 更新侧边栏宽度
        if let sidebar = sidebarView {
            let newWidth = LayoutManager.sidebarWidth(for: deviceType)
            sidebarWidthConstraint?.constant = newWidth
        }
    }

    private func updateTerminalViewConstraints(for deviceType: LayoutManager.DeviceType) {
        let insets = LayoutManager.terminalInsets(for: deviceType)

        // 根据设备类型调整边距
        if deviceType.isiPad {
            // iPad: 终端居中显示
            let maxWidth = view.bounds.width - insets.left - insets.right - (sidebarView?.bounds.width ?? 0)
            let maxHeight = view.bounds.height - insets.top - insets.bottom - (connectionBanner?.bounds.height ?? 0)

            // 可以在这里添加居中约束
        }
    }

    private func updateKeyboardAccessoryView(for deviceType: LayoutManager.DeviceType) {
        let layoutStyle = KeyboardAccessoryView.LayoutStylerecommendedStyle(for: deviceType)
        keyboardAccessoryView?.updateLayout(style: layoutStyle, fontSize: layoutConfig.keyboardAccessoryFontSize)
    }

    private func updateTerminalFontSize(for deviceType: LayoutManager.DeviceType) {
        let fontSize = LayoutManager.terminalFontSize(for: deviceType)
        // TODO: 更新终端视图的字体大小
    }

    private func updateTerminalGridSize() {
        let deviceType = LayoutManager.deviceType(for: self)
        let availableSize = CGSize(
            width: view.bounds.width - (sidebarView?.bounds.width ?? 0),
            height: view.bounds.height - (connectionBanner?.bounds.height ?? 0)
        )

        let gridSize = LayoutManager.calculateTerminalGridSize(
            availableSize: availableSize,
            deviceType: deviceType,
            fontSize: layoutConfig.fontSize
        )

        terminalView.gridCols = gridSize.cols
        terminalView.gridRows = gridSize.rows

        // 通知服务器 PTY 大小变化
        notifyTerminalSizeChanged(cols: gridSize.cols, rows: gridSize.rows)
    }

    // MARK: - Rotation Handling

    private func handleRotationCompletion(toSize size: CGSize) {
        // 重新计算终端网格大小
        updateTerminalGridSize()

        // 恢复终端状态
        if let savedState = savedLayoutState {
            // 可以在这里恢复滚动位置等状态
            savedLayoutState = nil
        }

        // 通知服务器新的 PTY 大小
        let gridSize = LayoutManager.calculateTerminalGridSize(
            availableSize: size,
            deviceType: LayoutManager.deviceType(for: self),
            fontSize: layoutConfig.fontSize
        )

        notifyTerminalSizeChanged(cols: gridSize.cols, rows: gridSize.rows)
    }

    private func notifyTerminalSizeChanged(cols: Int, rows: Int) {
        guard let sessionId = currentSessionId,
              let client = webSocketClient else {
            return
        }

        Task {
            try? await client.resizeSession(sessionId: sessionId, cols: UInt16(cols), rows: UInt16(rows))
        }
    }

    // MARK: - Keyboard Observers

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let keyboardHeight = keyboardFrame.height

        // 调整终端视图底部约束
        UIView.animate(withDuration: 0.25) {
            self.terminalViewBottomConstraint?.constant = -keyboardHeight
            self.view.layoutIfNeeded()
        }

        // 键盘显示后重新计算终端大小
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.updateTerminalGridSize()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        UIView.animate(withDuration: 0.25) {
            self.terminalViewBottomConstraint?.constant = 0
            self.view.layoutIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.updateTerminalGridSize()
        }
    }

    @objc private func keyboardDidChangeFrame(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let keyboardHeight = view.bounds.height - keyboardFrame.minY
        let isKeyboardVisible = keyboardHeight > 0

        UIView.animate(withDuration: 0.25) {
            self.terminalViewBottomConstraint?.constant = isKeyboardVisible ? -keyboardHeight : 0
            self.view.layoutIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.updateTerminalGridSize()
        }
    }

    // MARK: - Connection

    private func connect() {
        guard let url = URL(string: connectionURL) else {
            showAlert(title: "连接错误", message: "无效的 URL")
            return
        }

        webSocketClient = WebSocketClient(url: url)
        webSocketClient?.delegate = self
        webSocketClient?.connect()

        updateConnectionStatus(.connecting)
    }

    private func disconnect() {
        webSocketClient?.disconnect()
        webSocketClient = nil
        currentSessionId = nil
        updateConnectionStatus(.disconnected)
    }

    // MARK: - Actions

    @objc private func statusButtonTapped() {
        if webSocketClient != nil {
            disconnect()
        } else {
            connect()
        }
    }

    @objc private func settingsTapped() {
        let settingsVC = ConnectionSettingsViewController()
        settingsVC.delegate = self
        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
    }

    // MARK: - UI Updates

    private func updateConnectionStatus(_ status: ConnectionStatus) {
        // 更新导航栏状态按钮
        let statusButton = navigationItem.leftBarButtonItem?.customView as? UIButton

        switch status {
        case .connected:
            statusButton?.setTitleColor(.systemGreen, for: .normal)
            connectionBanner?.updateStatus(.connected, host: connectionURL)

        case .connecting:
            statusButton?.setTitleColor(.systemOrange, for: .normal)
            connectionBanner?.updateStatus(.connecting, host: connectionURL)

        case .disconnected:
            statusButton?.setTitleColor(.systemRed, for: .normal)
            connectionBanner?.updateStatus(.disconnected, host: connectionURL)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Cleanup

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - ConnectionStatus

enum ConnectionStatus {
    case connected
    case connecting
    case disconnected
}

// MARK: - TerminalMetalViewDelegate

extension TerminalViewController: TerminalMetalViewDelegate {

    func terminalView(_ view: TerminalMetalView, didReceiveKeyPress keyEvent: KeyPressEvent) {
        // 将按键事件发送到服务器
        guard let sessionId = currentSessionId else { return }

        // 转换按键事件为数据
        let inputData = encodeKeyPressEvent(keyEvent)

        Task {
            try? await webSocketClient?.sendInput(sessionId: sessionId, data: inputData)
        }
    }

    func terminalViewDidChangeSize(_ view: TerminalMetalView, cols: Int, rows: Int) {
        // 终端大小变化时通知服务器
        notifyTerminalSizeChanged(cols: cols, rows: rows)
    }

    private func encodeKeyPressEvent(_ event: KeyPressEvent) -> Data {
        // TODO: 实现按键事件编码
        return Data()
    }
}

// MARK: - KeyboardAccessoryViewDelegate

extension TerminalViewController: KeyboardAccessoryDelegate {

    func accessoryView(_ view: KeyboardAccessoryView, didPressKey key: AccessoryKey, modifiers: KeyModifiers) {
        guard let sessionId = currentSessionId else { return }

        // 转换辅助按键事件
        let keyPressEvent = convertAccessoryKeyToKeyPressEvent(key, modifiers: modifiers)
        let inputData = encodeKeyPressEvent(keyPressEvent)

        Task {
            try? await webSocketClient?.sendInput(sessionId: sessionId, data: inputData)
        }
    }

    func accessoryViewDidChangeModifierState(_ view: KeyboardAccessoryView, modifiers: KeyModifiers) {
        // 修饰键状态变化
    }

    private func convertAccessoryKeyToKeyPressEvent(_ key: AccessoryKey, modifiers: KeyModifiers) -> KeyPressEvent {
        let keyModifiers = KeyPressEvent.KeyModifiers(rawValue: modifiers.rawValue)

        switch key {
        case .escape:
            return KeyPressEvent(key: .escape, modifiers: keyModifiers)
        case .tab:
            return KeyPressEvent(key: .tab, modifiers: keyModifiers)
        case .arrowUp:
            return KeyPressEvent(key: .arrowUp, modifiers: keyModifiers)
        case .arrowDown:
            return KeyPressEvent(key: .arrowDown, modifiers: keyModifiers)
        case .arrowLeft:
            return KeyPressEvent(key: .arrowLeft, modifiers: keyModifiers)
        case .arrowRight:
            return KeyPressEvent(key: .arrowRight, modifiers: keyModifiers)
        case .home:
            return KeyPressEvent(key: .home, modifiers: keyModifiers)
        case .end:
            return KeyPressEvent(key: .end, modifiers: keyModifiers)
        case .pageUp:
            return KeyPressEvent(key: .pageUp, modifiers: keyModifiers)
        case .pageDown:
            return KeyPressEvent(key: .pageDown, modifiers: keyModifiers)
        case .insert:
            return KeyPressEvent(key: .insert, modifiers: keyModifiers)
        case .delete:
            return KeyPressEvent(key: .delete, modifiers: keyModifiers)
        case .f(let num):
            return KeyPressEvent(key: .f(num), modifiers: keyModifiers)
        case .character(let char):
            return KeyPressEvent(key: .character(Character(char)), modifiers: keyModifiers)
        case .modifier, .functionKey:
            return KeyPressEvent(key: .character(" "), modifiers: keyModifiers)
        }
    }
}

// MARK: - WebSocketClientDelegate

extension TerminalViewController: WebSocketClientDelegate {

    func webSocketDidConnect(_ client: WebSocketClient) {
        print("Connected to terminal server")
        updateConnectionStatus(.connected)

        // 连接成功后创建 Shell 会话
        Task {
            do {
                try await client.createShellSession()
                // sessionId 将在 sessionCreated 帧中返回
            } catch {
                print("Failed to create shell session: \(error)")
            }
        }
    }

    func webSocketDidDisconnect(_ client: WebSocketClient, error: Error?) {
        print("Disconnected from terminal server: \(error?.localizedDescription ?? "No error")")
        updateConnectionStatus(.disconnected)
        currentSessionId = nil

        if let error = error {
            showAlert(title: "连接断开", message: error.localizedDescription)
        }
    }

    func webSocket(_ client: WebSocketClient, didReceiveFrame frame: Frame) {
        DispatchQueue.main.async { [weak self] in
            switch frame {
            case .sessionOutput(_, let screenFrame):
                self?.terminalView.update(dirtyRegions: screenFrame.dirtyRegions)

            case .cursorUpdate(let cursorFrame):
                self?.terminalView.updateCursor(cursorFrame)

            case .modeUpdate(let modeFrame):
                print("Mode changed: \(modeFrame.mode)")

            case .sessionCreated(let sessionId):
                self?.currentSessionId = sessionId
                print("Session created: \(sessionId)")

                // 通知 WebSocket 客户端
                self?.webSocketClient?.handleSessionCreated(sessionId)

            case .sessionClosed(let sessionId):
                if sessionId == self?.currentSessionId {
                    self?.currentSessionId = nil
                }
                print("Session closed: \(sessionId)")

            case .error(let message):
                self?.showAlert(title: "服务器错误", message: message)

            default:
                break
            }
        }
    }

    func webSocket(_ client: WebSocketClient, didReceiveError error: Error) {
        print("WebSocket error: \(error)")
        showAlert(title: "通信错误", message: error.localizedDescription)
    }
}

// MARK: - ConnectionSettingsDelegate

extension TerminalViewController: ConnectionSettingsDelegate {
    func didUpdateConnectionURL(_ url: String) {
        disconnect()
        connect()
    }
}

// MARK: - KeyboardAccessoryView.LayoutStyle Extension

extension KeyboardAccessoryView.LayoutStyle {
    static func recommendedStyle(for deviceType: LayoutManager.DeviceType) -> KeyboardAccessoryView.LayoutStyle {
        switch deviceType {
        case .iPhonePortrait:
            return .standard
        case .iPhoneLandscape:
            return .expanded
        case .iPadPortrait:
            return .expanded
        case .iPadLandscape:
            return .full
        }
    }
}
