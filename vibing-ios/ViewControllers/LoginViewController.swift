//
//  LoginViewController.swift
//  Vibing (iOS)
//
//  登录/注册/扫码登录
//

import UIKit

class LoginViewController: UIViewController {

    var onLoginSuccess: (() -> Void)?
    private let account = AccountManager.shared
    private var isRegistering = false

    // MARK: - UI

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.alwaysBounceVertical = true
        sv.keyboardDismissMode = .interactive
        return sv
    }()

    private lazy var stack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 16
        s.alignment = .fill
        return s
    }()

    private let logoIcon = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let serverField = UITextField()
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let errorLabel = UILabel()
    private let submitBtn = UIButton(type: .system)
    private let toggleBtn = UIButton(type: .system)
    private let dividerLabel = UILabel()
    private let qrBtn = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    // MARK: - Colors

    private let accent = UIColor(red: 106/255, green: 194/255, blue: 120/255, alpha: 1)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupViews()
        layoutViews()
        setupActions()
    }

    // MARK: - Setup

    private func setupViews() {
        // Logo
        logoIcon.image = UIImage(systemName: "terminal.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .medium))
        logoIcon.tintColor = accent
        logoIcon.contentMode = .scaleAspectFit

        // Title
        titleLabel.text = L("login.welcome")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        // Subtitle
        subtitleLabel.text = L("login.subtitle")
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        // Server URL
        configureField(serverField, placeholder: L("login.serverPlaceholder"))
        serverField.text = UserDefaults.standard.string(forKey: "relayServerURL") ?? ""
        serverField.keyboardType = .URL
        serverField.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        serverField.textColor = .secondaryLabel

        // Username
        configureField(usernameField, placeholder: L("login.username"))

        // Password
        configureField(passwordField, placeholder: L("login.password"))
        passwordField.isSecureTextEntry = true

        // Error
        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        // Submit
        submitBtn.setTitle(L("login.signIn"), for: .normal)
        submitBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        submitBtn.backgroundColor = accent
        submitBtn.setTitleColor(.white, for: .normal)
        submitBtn.layer.cornerRadius = 12

        // Toggle
        toggleBtn.setTitle(L("login.noAccount"), for: .normal)
        toggleBtn.titleLabel?.font = .systemFont(ofSize: 13)
        toggleBtn.setTitleColor(.secondaryLabel, for: .normal)

        // Divider
        dividerLabel.text = L("login.or")
        dividerLabel.font = .systemFont(ofSize: 12)
        dividerLabel.textColor = .tertiaryLabel
        dividerLabel.textAlignment = .center

        // QR
        qrBtn.setTitle("  " + L("login.qrScan"), for: .normal)
        qrBtn.setImage(UIImage(systemName: "qrcode.viewfinder"), for: .normal)
        qrBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        qrBtn.tintColor = .label
        qrBtn.backgroundColor = .secondarySystemBackground
        qrBtn.layer.cornerRadius = 12
        qrBtn.layer.borderWidth = 0.5
        qrBtn.layer.borderColor = UIColor.separator.cgColor

        // Spinner
        spinner.hidesWhenStopped = true

        // Tap to dismiss
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func configureField(_ tf: UITextField, placeholder: String) {
        tf.placeholder = placeholder
        tf.font = .systemFont(ofSize: 17)
        tf.backgroundColor = .secondarySystemBackground
        tf.layer.cornerRadius = 10
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        tf.leftViewMode = .always
    }

    private func layoutViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 60),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
        ])

        // Add views to stack
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 20).isActive = true

        stack.addArrangedSubview(logoIcon)
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(8, after: titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.setCustomSpacing(24, after: subtitleLabel)
        stack.addArrangedSubview(serverField)
        stack.setCustomSpacing(16, after: serverField)
        stack.addArrangedSubview(usernameField)
        stack.addArrangedSubview(passwordField)
        stack.addArrangedSubview(errorLabel)
        stack.addArrangedSubview(submitBtn)
        stack.addArrangedSubview(toggleBtn)
        stack.setCustomSpacing(24, after: toggleBtn)
        stack.addArrangedSubview(dividerLabel)
        stack.addArrangedSubview(qrBtn)

        // Heights
        logoIcon.heightAnchor.constraint(equalToConstant: 60).isActive = true
        serverField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        usernameField.heightAnchor.constraint(equalToConstant: 48).isActive = true
        passwordField.heightAnchor.constraint(equalToConstant: 48).isActive = true
        submitBtn.heightAnchor.constraint(equalToConstant: 50).isActive = true
        qrBtn.heightAnchor.constraint(equalToConstant: 50).isActive = true

        // Spinner on submit button
        spinner.translatesAutoresizingMaskIntoConstraints = false
        submitBtn.addSubview(spinner)
        spinner.centerYAnchor.constraint(equalTo: submitBtn.centerYAnchor).isActive = true
        spinner.trailingAnchor.constraint(equalTo: submitBtn.trailingAnchor, constant: -16).isActive = true
    }

    // MARK: - Actions

    private func setupActions() {
        submitBtn.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        toggleBtn.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)
        qrBtn.addTarget(self, action: #selector(qrTapped), for: .touchUpInside)
    }

    @objc private func submitTapped() {
        guard let username = usernameField.text, !username.isEmpty,
              let password = passwordField.text, !password.isEmpty else {
            showError(L("login.fillFields"))
            return
        }

        // 保存服务器地址
        if let url = serverField.text, !url.isEmpty {
            UserDefaults.standard.set(url, forKey: "relayServerURL")
        }

        setLoading(true)
        errorLabel.isHidden = true

        Task {
            do {
                if isRegistering {
                    try await account.register(username: username, password: password)
                } else {
                    try await account.login(username: username, password: password)
                }
                await MainActor.run {
                    setLoading(false)
                    onLoginSuccess?()
                }
            } catch {
                await MainActor.run {
                    setLoading(false)
                    showError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func toggleTapped() {
        isRegistering.toggle()
        errorLabel.isHidden = true
        UIView.animate(withDuration: 0.25) {
            self.submitBtn.setTitle(self.isRegistering ? L("login.createAccount") : L("login.signIn"), for: .normal)
            self.toggleBtn.setTitle(
                self.isRegistering ? L("login.hasAccount") : L("login.noAccount"),
                for: .normal)
            self.dividerLabel.alpha = self.isRegistering ? 0 : 1
            self.qrBtn.alpha = self.isRegistering ? 0 : 1
        }
    }

    @objc private func qrTapped() {
        // 优先选择方式
        let sheet = UIAlertController(title: L("login.qrTitle"), message: nil, preferredStyle: .actionSheet)

        // 摄像头扫码
        sheet.addAction(UIAlertAction(title: L("login.qrScanCamera"), style: .default) { [weak self] _ in
            self?.openCameraScanner()
        })

        // 手动输入
        sheet.addAction(UIAlertAction(title: L("login.qrManualInput"), style: .default) { [weak self] _ in
            self?.showManualQRInput()
        })

        sheet.addAction(UIAlertAction(title: L("login.cancel"), style: .cancel))
        sheet.view.tintColor = accent

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = qrBtn
            popover.sourceRect = qrBtn.bounds
        }
        present(sheet, animated: true)
    }

    private func openCameraScanner() {
        let scanner = QRScannerSimpleController { [weak self] result in
            guard let self = self else { return }
            self.dismiss(animated: true)

            guard let url = URL(string: result),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let params = components.queryItems else {
                // 不是 URL 格式，尝试当作纯 code
                self.performQRLogin(code: result)
                return
            }

            let server = params.first(where: { $0.name == "server" })?.value
            let code = params.first(where: { $0.name == "code" })?.value

            if let server = server, let code = code {
                UserDefaults.standard.set(server, forKey: "relayServerURL")
                self.serverField.text = server
                self.performQRLogin(code: code)
            } else {
                self.performQRLogin(code: result)
            }
        }
        scanner.modalPresentationStyle = .fullScreen
        present(scanner, animated: true)
    }

    private func showManualQRInput() {
        let alert = UIAlertController(title: L("login.qrTitle"), message: L("login.qrMessage"), preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "VIBE_QR|..."; $0.autocapitalizationType = .none }
        alert.addAction(UIAlertAction(title: L("login.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("login.login"), style: .default) { [weak self] _ in
            guard let code = alert.textFields?.first?.text, !code.isEmpty else { return }
            self?.performQRLogin(code: code)
        })
        alert.view.tintColor = accent
        present(alert, animated: true)
    }

    private func performQRLogin(code: String) {
        setLoading(true)
        Task {
            do {
                try await account.qrLogin(code: code)
                await MainActor.run { setLoading(false); onLoginSuccess?() }
            } catch {
                await MainActor.run { setLoading(false); showError(error.localizedDescription) }
            }
        }
    }

    private func setLoading(_ on: Bool) {
        submitBtn.isEnabled = !on
        qrBtn.isEnabled = !on
        on ? spinner.startAnimating() : spinner.stopAnimating()
    }

    private func showError(_ msg: String) {
        errorLabel.text = msg
        errorLabel.isHidden = false
    }
}
