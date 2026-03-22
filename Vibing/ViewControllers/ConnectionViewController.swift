//
//  ConnectionViewController.swift
//  VibeTerminal
//
//  连接状态视图控制器
//

import UIKit

// MARK: - Connection State
enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case reconnecting

    var displayText: String {
        switch self {
        case .disconnected: return "未连接"
        case .connecting: return "正在连接..."
        case .connected: return "已连接"
        case .reconnecting: return "正在重连..."
        }
    }

    var color: UIColor {
        switch self {
        case .disconnected: return .systemRed
        case .connecting: return .systemOrange
        case .connected: return .systemGreen
        case .reconnecting: return .systemYellow
        }
    }

    var isAnimating: Bool {
        switch self {
        case .connecting, .reconnecting: return true
        case .disconnected, .connected: return false
        }
    }
}

// MARK: - Connection View Controller
class ConnectionViewController: UIViewController {

    // MARK: - Properties
    private var connectionState: ConnectionState = .disconnected {
        didSet {
            updateUI()
        }
    }

    private var serverAddress: String {
        get { UserDefaults.standard.string(forKey: "serverAddress") ?? "ws://192.168.1.100:8765" }
        set { UserDefaults.standard.set(newValue, forKey: "serverAddress") }
    }

    private var autoReconnect: Bool {
        get { UserDefaults.standard.bool(forKey: "autoReconnect") }
        set { UserDefaults.standard.set(newValue, forKey: "autoReconnect") }
    }

    // MARK: - UI Components
    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        return scroll
    }()

    private let contentView = UIView()

    private let statusContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 16
        return view
    }()

    private let statusIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemRed
        imageView.image = UIImage(systemName: "wifi.slash")
        return imageView
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "未连接"
        label.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        label.textAlignment = .center
        return label
    }()

    private let serverInfoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "ws://192.168.1.100:8765"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private let connectionTimeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "--:--:--"
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.textColor = .tertiaryLabel
        return label
    }()

    private lazy var connectButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("连接", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        button.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var disconnectButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("断开", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = .systemRed
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        button.addTarget(self, action: #selector(disconnectButtonTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var settingsButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        button.tintColor = .systemGray
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        button.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        return button
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // Connection timing
    private var connectionStartTime: Date?
    private var connectionTimer: Timer?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "连接"
        view.backgroundColor = .systemGroupedBackground

        setupUI()
        updateUI()

        // 加载保存的地址
        serverInfoLabel.text = serverAddress

        // 监听键盘事件
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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // 如果启用了自动重连且当前未连接
        if autoReconnect && connectionState == .disconnected {
            connect()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopConnectionTimer()
    }

    deinit {
        stopConnectionTimer()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup
    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false

        // Status Container
        statusContainerView.addSubview(statusIconView)
        statusContainerView.addSubview(statusLabel)
        statusContainerView.addSubview(serverInfoLabel)
        statusContainerView.addSubview(connectionTimeLabel)
        contentView.addSubview(statusContainerView)

        // Buttons
        let buttonStackView = UIStackView(arrangedSubviews: [connectButton, disconnectButton])
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = 12
        buttonStackView.distribution = .fillEqually
        contentView.addSubview(buttonStackView)

        // Settings button
        contentView.addSubview(settingsButton)

        // Activity indicator
        statusContainerView.addSubview(activityIndicator)

        // Title label for connection time
        let connectionTimeTitleLabel = UILabel()
        connectionTimeTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        connectionTimeTitleLabel.text = "连接时长"
        connectionTimeTitleLabel.font = UIFont.systemFont(ofSize: 12)
        connectionTimeTitleLabel.textColor = .tertiaryLabel
        connectionTimeTitleLabel.textAlignment = .center
        contentView.addSubview(connectionTimeTitleLabel)

        NSLayoutConstraint.activate([
            // ScrollView
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // ContentView
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Status Container
            statusContainerView.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 20),
            statusContainerView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            statusContainerView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.9),
            statusContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),

            // Status Icon
            statusIconView.topAnchor.constraint(equalTo: statusContainerView.topAnchor, constant: 24),
            statusIconView.centerXAnchor.constraint(equalTo: statusContainerView.centerXAnchor),
            statusIconView.widthAnchor.constraint(equalToConstant: 60),
            statusIconView.heightAnchor.constraint(equalToConstant: 60),

            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: statusIconView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: statusIconView.centerYAnchor),

            // Status Label
            statusLabel.topAnchor.constraint(equalTo: statusIconView.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: statusContainerView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: statusContainerView.trailingAnchor, constant: -16),

            // Server Info Label
            serverInfoLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            serverInfoLabel.leadingAnchor.constraint(equalTo: statusContainerView.leadingAnchor, constant: 16),
            serverInfoLabel.trailingAnchor.constraint(equalTo: statusContainerView.trailingAnchor, constant: -16),

            // Connection Time Title
            connectionTimeTitleLabel.topAnchor.constraint(equalTo: serverInfoLabel.bottomAnchor, constant: 16),
            connectionTimeTitleLabel.leadingAnchor.constraint(equalTo: statusContainerView.leadingAnchor, constant: 16),
            connectionTimeTitleLabel.trailingAnchor.constraint(equalTo: statusContainerView.trailingAnchor, constant: -16),

            // Connection Time Label
            connectionTimeLabel.topAnchor.constraint(equalTo: connectionTimeTitleLabel.bottomAnchor, constant: 4),
            connectionTimeLabel.leadingAnchor.constraint(equalTo: statusContainerView.leadingAnchor, constant: 16),
            connectionTimeLabel.trailingAnchor.constraint(equalTo: statusContainerView.trailingAnchor, constant: -16),
            connectionTimeLabel.bottomAnchor.constraint(equalTo: statusContainerView.bottomAnchor, constant: -16),

            // Button Stack
            buttonStackView.topAnchor.constraint(equalTo: statusContainerView.bottomAnchor, constant: 24),
            buttonStackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            buttonStackView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.9),
            buttonStackView.heightAnchor.constraint(equalToConstant: 48),

            // Settings Button
            settingsButton.topAnchor.constraint(equalTo: buttonStackView.bottomAnchor, constant: 20),
            settingsButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),
            settingsButton.heightAnchor.constraint(equalToConstant: 44),
            settingsButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        // 添加服务器地址编辑功能
        let serverTapGesture = UITapGestureRecognizer(target: self, action: #selector(serverAddressTapped))
        serverInfoLabel.isUserInteractionEnabled = true
        serverInfoLabel.addGestureRecognizer(serverTapGesture)
    }

    // MARK: - UI Updates
    private func updateUI() {
        statusLabel.text = connectionState.displayText
        statusLabel.textColor = connectionState.color

        switch connectionState {
        case .disconnected:
            statusIconView.image = UIImage(systemName: "wifi.slash")
            statusIconView.tintColor = .systemRed
            activityIndicator.stopAnimating()
            connectButton.isHidden = false
            disconnectButton.isHidden = true
            connectButton.isEnabled = true
            connectButton.alpha = 1.0
            stopConnectionTimer()
            connectionTimeLabel.text = "--:--:--"

        case .connecting:
            statusIconView.image = UIImage(systemName: "wifi.exclamationmark")
            statusIconView.tintColor = .systemOrange
            activityIndicator.startAnimating()
            connectButton.isHidden = false
            disconnectButton.isHidden = true
            connectButton.isEnabled = false
            connectButton.alpha = 0.5
            stopConnectionTimer()
            connectionTimeLabel.text = "--:--:--"

        case .connected:
            statusIconView.image = UIImage(systemName: "wifi")
            statusIconView.tintColor = .systemGreen
            activityIndicator.stopAnimating()
            connectButton.isHidden = true
            disconnectButton.isHidden = false
            startConnectionTimer()

        case .reconnecting:
            statusIconView.image = UIImage(systemName: "arrow.clockwise")
            statusIconView.tintColor = .systemYellow
            activityIndicator.startAnimating()
            connectButton.isHidden = true
            disconnectButton.isHidden = false
        }
    }

    // MARK: - Connection Timer
    private func startConnectionTimer() {
        connectionStartTime = Date()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateConnectionTime()
        }
    }

    private func stopConnectionTimer() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        connectionStartTime = nil
    }

    private func updateConnectionTime() {
        guard let startTime = connectionStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(startTime))

        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        connectionTimeLabel.text = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // MARK: - Actions
    @objc private func connectButtonTapped() {
        connect()
    }

    @objc private func disconnectButtonTapped() {
        disconnect()
    }

    @objc private func settingsButtonTapped() {
        let settingsVC = SettingsViewController()
        settingsVC.delegate = self
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    @objc private func serverAddressTapped() {
        showServerAddressEditAlert()
    }

    private func showServerAddressEditAlert() {
        let alert = UIAlertController(title: "服务器地址", message: "输入 WebSocket 服务器地址", preferredStyle: .alert)

        alert.addTextField { [weak self] textField in
            textField.text = self?.serverAddress
            textField.placeholder = "ws://192.168.1.100:8765"
            textField.keyboardType = .URL
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let newAddress = alert?.textFields?.first?.text, !newAddress.isEmpty else {
                return
            }

            self?.updateServerAddress(newAddress)
        })

        present(alert, animated: true)
    }

    private func updateServerAddress(_ address: String) {
        // 验证地址格式
        guard validateServerAddress(address) else {
            let errorAlert = UIAlertController(
                title: "无效的地址",
                message: "请输入有效的服务器地址，格式为 ws://host:port 或 wss://host:port",
                preferredStyle: .alert
            )
            errorAlert.addAction(UIAlertAction(title: "确定", style: .default))
            present(errorAlert, animated: true)
            return
        }

        serverAddress = address
        serverInfoLabel.text = address

        // 如果已连接，提示是否重新连接
        if connectionState == .connected {
            let reconnectAlert = UIAlertController(
                title: "地址已更新",
                message: "是否使用新地址重新连接？",
                preferredStyle: .alert
            )

            reconnectAlert.addAction(UIAlertAction(title: "取消", style: .cancel))

            reconnectAlert.addAction(UIAlertAction(title: "重新连接", style: .default) { [weak self] _ in
                self?.reconnect()
            })

            present(reconnectAlert, animated: true)
        }
    }

    // MARK: - Validation
    private func validateServerAddress(_ address: String) -> Bool {
        guard address.hasPrefix("ws://") || address.hasPrefix("wss://") else {
            return false
        }

        let pattern = "^wss?://[^:]+(?::\\d+)?$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(address.startIndex..., in: address)
        let matches = regex?.firstMatch(in: address, range: range)

        return matches != nil
    }

    // MARK: - Keyboard Handling
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let info = notification.userInfo,
              let keyboardFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let keyboardHeight = keyboardFrame.height
        scrollView.contentInset.bottom = keyboardHeight
        scrollView.verticalScrollIndicatorInsets.bottom = keyboardHeight
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }
}

// MARK: - Connection Control
extension ConnectionViewController {

    func connect() {
        guard connectionState != .connected && connectionState != .connecting else {
            return
        }

        connectionState = .connecting

        // TODO: 实际的 WebSocket 连接逻辑
        // 这里使用模拟延迟来演示连接过程
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            // 模拟连接成功
            self?.connectionState = .connected
        }
    }

    func disconnect() {
        connectionState = .disconnected

        // TODO: 实际的 WebSocket 断开逻辑
    }

    func reconnect() {
        connectionState = .reconnecting

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.connect()
            }
        }
    }

    func updateConnectionState(_ state: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = state
        }
    }
}

// MARK: - Settings Delegate
extension ConnectionViewController: SettingsDelegate {

    func didUpdateSettings() {
        // 设置已更新，刷新 UI
        serverInfoLabel.text = serverAddress

        // 如果自动重连状态改变，处理相应逻辑
        // 这里可以添加额外的处理逻辑
    }
}

// MARK: - Connection Status Banner View
class ConnectionStatusBannerView: UIView {

    private let statusView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowRadius = 4
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        return view
    }()

    private let statusIndicator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 6
        return view
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "未连接"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        return label
    }()

    private let chevronImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "chevron.right")
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        addSubview(statusView)
        statusView.addSubview(statusIndicator)
        statusView.addSubview(statusLabel)
        statusView.addSubview(chevronImageView)

        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: topAnchor),
            statusView.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusView.heightAnchor.constraint(equalToConstant: 44),

            statusIndicator.leadingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: 16),
            statusIndicator.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),
            statusIndicator.widthAnchor.constraint(equalToConstant: 12),
            statusIndicator.heightAnchor.constraint(equalToConstant: 12),

            statusLabel.leadingAnchor.constraint(equalTo: statusIndicator.trailingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),

            chevronImageView.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -16),
            chevronImageView.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 12),
            chevronImageView.heightAnchor.constraint(equalToConstant: 12)
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
    }

    func configure(state: ConnectionState) {
        statusIndicator.backgroundColor = state.color
        statusLabel.text = state.displayText
    }

    @objc private func handleTap() {
        onTap?()
    }
}

// MARK: - Connection Info View
class ConnectionInfoView: UIView {

    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "连接信息"
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        return label
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(stackView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            stackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16)
        ])
    }

    func addInfoItem(title: String, value: String) {
        let itemView = InfoItemView()
        itemView.configure(title: title, value: value)
        stackView.addArrangedSubview(itemView)
    }

    func updateInfo(title: String, value: String) {
        for case let itemView as InfoItemView in stackView.arrangedSubviews {
            if itemView.titleLabel.text == title {
                itemView.valueLabel.text = value
                break
            }
        }
    }
}

// MARK: - Info Item View
class InfoItemView: UIView {

    let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()

    let valueLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .right
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        addSubview(titleLabel)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            valueLabel.topAnchor.constraint(equalTo: topAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
    }

    func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
    }
}
