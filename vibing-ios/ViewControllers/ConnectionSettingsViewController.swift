//
//  ConnectionSettingsViewController.swift
//  VibeTerminal
//
//  连接设置视图控制器
//  支持直连模式和中继模式
//

import UIKit

// MARK: - 连接模式

enum ConnectionMode: Int {
    case direct = 0
    case relay = 1

    var displayName: String {
        switch self {
        case .direct: return "直连模式"
        case .relay: return "中继模式"
        }
    }
}

// MARK: - 连接配置

struct ConnectionConfig {
    let mode: ConnectionMode
    let directURL: String?
    let relayURL: String?
    let sessionId: String?

    static let `default` = ConnectionConfig(
        mode: .direct,
        directURL: nil,
        relayURL: nil,
        sessionId: nil
    )

    func toDict() -> [String: Any] {
        var dict: [String: Any] = ["mode": mode.rawValue]
        if let directURL = directURL {
            dict["direct_url"] = directURL
        }
        if let relayURL = relayURL {
            dict["relay_url"] = relayURL
        }
        if let sessionId = sessionId {
            dict["session_id"] = sessionId
        }
        return dict
    }

    static func from(dict: [String: Any]) -> ConnectionConfig {
        let mode = ConnectionMode(rawValue: dict["mode"] as? Int ?? 0) ?? .direct
        return ConnectionConfig(
            mode: mode,
            directURL: dict["direct_url"] as? String,
            relayURL: dict["relay_url"] as? String,
            sessionId: dict["session_id"] as? String
        )
    }
}

// MARK: - 委托协议

protocol ConnectionSettingsDelegate: AnyObject {
    func didUpdateConnectionConfig(_ config: ConnectionConfig)
}

// MARK: - 视图控制器

class ConnectionSettingsViewController: UIViewController {

    weak var delegate: ConnectionSettingsDelegate?

    // MARK: - Properties

    private var currentMode: ConnectionMode = .direct

    // 直连模式控件
    private let urlTextField: UITextField = {
        let field = UITextField()
        field.placeholder = "ws://192.168.1.100:8765"
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.borderStyle = .roundedRect
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 40))
        field.leftView = paddingView
        field.leftViewMode = .always
        return field
    }()

    // 中继模式控件
    private let relayUrlTextField: UITextField = {
        let field = UITextField()
        field.placeholder = "wss://relay.example.com:8766"
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.borderStyle = .roundedRect
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 40))
        field.leftView = paddingView
        field.leftViewMode = .always
        return field
    }()

    private let sessionIdTextField: UITextField = {
        let field = UITextField()
        field.placeholder = "输入16位会话码"
        field.keyboardType = .alphanumericsOnly
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.borderStyle = .roundedRect
        field.textAlignment = .center
        field.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 40))
        field.leftView = paddingView
        field.leftViewMode = .always
        return field
    }()

    // 模式切换
    private let modeSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["直连模式", "中继模式"])
        control.selectedSegmentIndex = 0
        return control
    }()

    // 容器视图
    private var directContainerView: UIView!
    private var relayContainerView: UIView!

    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("保存并连接", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "连接设置"
        view.backgroundColor = .systemGroupedBackground

        setupUI()
        loadSavedConfig()

        // 键盘通知
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

        // 导航栏按钮
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }

    // MARK: - Setup

    private func setupUI() {
        // 模式切换
        modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        modeSegmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        view.addSubview(modeSegmentedControl)

        // 直连容器
        directContainerView = createDirectContainer()
        directContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(directContainerView)

        // 中继容器
        relayContainerView = createRelayContainer()
        relayContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(relayContainerView)

        // 保存按钮
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saveButton)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        // 约束
        NSLayoutConstraint.activate([
            // 模式切换
            modeSegmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            modeSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            modeSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // 直连容器
            directContainerView.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 20),
            directContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            directContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // 中继容器
            relayContainerView.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 20),
            relayContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            relayContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // 保存按钮
            saveButton.topAnchor.constraint(equalTo: directContainerView.bottomAnchor, constant: 20),
            saveButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 150),
            saveButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        // 初始状态
        updateModeViews()
    }

    private func createDirectContainer() -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "终端服务器地址"
        titleLabel.font = UIFont.systemFont(ofSize: 17)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        urlTextField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(urlTextField)

        let infoLabel = UILabel()
        infoLabel.text = "直连模式需要与服务器在同一局域网"
        infoLabel.font = UIFont.systemFont(ofSize: 13)
        infoLabel.textColor = .secondaryLabel
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(infoLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            urlTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            urlTextField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            urlTextField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            urlTextField.heightAnchor.constraint(equalToConstant: 44),

            infoLabel.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            infoLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        return container
    }

    private func createRelayContainer() -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.isHidden = true

        let relayLabel = UILabel()
        relayLabel.text = "中继服务器地址"
        relayLabel.font = UIFont.systemFont(ofSize: 17)
        relayLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(relayLabel)

        relayUrlTextField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(relayUrlTextField)

        let sessionLabel = UILabel()
        sessionLabel.text = "会话码"
        sessionLabel.font = UIFont.systemFont(ofSize: 17)
        sessionLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sessionLabel)

        sessionIdTextField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sessionIdTextField)

        let generateButton = UIButton(type: .system)
        generateButton.setTitle("生成会话码", for: .normal)
        generateButton.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        generateButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(generateButton)
        generateButton.addTarget(self, action: #selector(generateSessionId), for: .touchUpInside)

        let infoLabel = UILabel()
        infoLabel.text = "中继模式可通过互联网连接，需双方使用相同会话码"
        infoLabel.font = UIFont.systemFont(ofSize: 13)
        infoLabel.textColor = .secondaryLabel
        infoLabel.numberOfLines = 0
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(infoLabel)

        NSLayoutConstraint.activate([
            relayLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            relayLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            relayLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            relayUrlTextField.topAnchor.constraint(equalTo: relayLabel.bottomAnchor, constant: 8),
            relayUrlTextField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            relayUrlTextField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            relayUrlTextField.heightAnchor.constraint(equalToConstant: 44),

            sessionLabel.topAnchor.constraint(equalTo: relayUrlTextField.bottomAnchor, constant: 16),
            sessionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            sessionIdTextField.topAnchor.constraint(equalTo: sessionLabel.bottomAnchor, constant: 8),
            sessionIdTextField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            sessionIdTextField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            sessionIdTextField.heightAnchor.constraint(equalToConstant: 50),

            generateButton.topAnchor.constraint(equalTo: sessionIdTextField.bottomAnchor, constant: 8),
            generateButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            infoLabel.topAnchor.constraint(equalTo: generateButton.bottomAnchor, constant: 16),
            infoLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            infoLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        return container
    }

    private func loadSavedConfig() {
        guard let dict = UserDefaults.standard.dictionary(forKey: "connection_config"),
              let modeValue = dict["mode"] as? Int,
              let mode = ConnectionMode(rawValue: modeValue) else {
            return
        }

        currentMode = mode
        modeSegmentedControl.selectedSegmentIndex = mode.rawValue

        if let directURL = dict["direct_url"] as? String {
            urlTextField.text = directURL
        }

        if let relayURL = dict["relay_url"] as? String {
            relayUrlTextField.text = relayURL
        }

        if let sessionId = dict["session_id"] as? String {
            sessionIdTextField.text = sessionId
        }

        updateModeViews()
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        currentMode = ConnectionMode(rawValue: modeSegmentedControl.selectedSegmentIndex) ?? .direct
        updateModeViews()
    }

    private func updateModeViews() {
        UIView.animate(withDuration: 0.3) {
            self.directContainerView.isHidden = self.currentMode != .direct
            self.relayContainerView.isHidden = self.currentMode != .relay
        }
    }

    @objc private func generateSessionId() {
        let chars = "abcdefghjkmnpqrstuvwxyz23456789"
        let sessionId = String((0..<16).map { _ in chars.randomElement()! })
        sessionIdTextField.text = sessionId
    }

    @objc private func saveTapped() {
        let config: ConnectionConfig

        switch currentMode {
        case .direct:
            guard let url = urlTextField.text, !url.isEmpty else {
                showAlert(title: "错误", message: "请输入服务器地址")
                return
            }

            if !url.hasPrefix("ws://") && !url.hasPrefix("wss://") {
                showAlert(title: "错误", message: "URL 必须以 ws:// 或 wss:// 开头")
                return
            }

            config = ConnectionConfig(
                mode: .direct,
                directURL: url,
                relayURL: nil,
                sessionId: nil
            )

        case .relay:
            guard let relayURL = relayUrlTextField.text, !relayURL.isEmpty else {
                showAlert(title: "错误", message: "请输入中继服务器地址")
                return
            }

            guard let sessionId = sessionIdTextField.text, !sessionId.isEmpty else {
                showAlert(title: "错误", message: "请输入会话码")
                return
            }

            guard sessionId.count == 16 && sessionId.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                showAlert(title: "错误", message: "会话码必须是16位字母或数字")
                return
            }

            config = ConnectionConfig(
                mode: .relay,
                directURL: nil,
                relayURL: relayURL,
                sessionId: sessionId
            )
        }

        // 保存配置
        UserDefaults.standard.set(config.toDict(), forKey: "connection_config")
        delegate?.didUpdateConnectionConfig(config)

        dismiss(animated: true)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let info = notification.userInfo,
              let keyboardFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let keyboardHeight = view.bounds.maxY - keyboardFrame.maxY

        UIView.animate(withDuration: 0.3) {
            self.view.transform = CGAffineTransform(translationX: 0, y: -keyboardHeight / 2)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        UIView.animate(withDuration: 0.3) {
            self.view.transform = .identity
        }
    }

    // MARK: - Helper

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
