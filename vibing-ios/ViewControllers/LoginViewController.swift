//
//  LoginViewController.swift
//  Vibing (iOS)
//
//  登录/注册/扫码登录 — 温暖简约设计
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
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private lazy var stack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = VibingSpacing.md  // 16pt 默认间距
        s.alignment = .fill
        return s
    }()

    private let logoIcon = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let serverField = VibingTextField()
    private let usernameField = VibingTextField()
    private let passwordField = VibingTextField()
    private let errorLabel = UILabel()
    private let submitBtn = VibingPrimaryButton()
    private let toggleBtn = UIButton(type: .system)
    private let dividerView = UIView()
    private let qrBtn = VibingSecondaryButton()
    private let spinner = UIActivityIndicatorView(style: .medium)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = VibingColor.pageBg
        setupViews()
        layoutViews()
        setupActions()
    }

    // MARK: - Setup

    private func setupViews() {
        // Logo — 品牌绿色终端图标
        logoIcon.image = UIImage(
            systemName: "terminal.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 48, weight: .medium)
        )
        logoIcon.tintColor = VibingColor.accent
        logoIcon.contentMode = .scaleAspectFit

        // Title — 大标题，居中
        titleLabel.text = L("login.welcome")
        titleLabel.font = VibingFont.title1()
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        // Subtitle — 副标题，柔和色
        subtitleLabel.text = L("login.subtitle")
        subtitleLabel.font = VibingFont.subheadline()
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        // Server URL — 等宽字体
        serverField.setPlaceholder(L("login.serverPlaceholder"))
        serverField.text = UserDefaults.standard.string(forKey: "relayServerURL") ?? ""
        serverField.keyboardType = .URL
        serverField.font = VibingFont.mono(14, weight: .regular)
        serverField.textColor = .secondaryLabel

        // Username
        usernameField.setPlaceholder(L("login.username"))

        // Password
        passwordField.setPlaceholder(L("login.password"))
        passwordField.isSecureTextEntry = true

        // Error
        errorLabel.font = VibingFont.footnote()
        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        // Submit
        submitBtn.setTitle(L("login.signIn"), for: .normal)

        // Toggle — 注册/登录切换
        toggleBtn.setTitle(L("login.noAccount"), for: .normal)
        toggleBtn.titleLabel?.font = VibingFont.footnote()
        toggleBtn.setTitleColor(.secondaryLabel, for: .normal)

        // Divider — 带文字的分隔线
        setupDivider()

        // QR — 扫码登录
        qrBtn.setTitle("  " + L("login.qrScan"), for: .normal)
        qrBtn.setImage(UIImage(systemName: "qrcode.viewfinder"), for: .normal)
        qrBtn.tintColor = .label

        // Spinner
        spinner.hidesWhenStopped = true

        // Tap to dismiss keyboard
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func setupDivider() {
        dividerView.translatesAutoresizingMaskIntoConstraints = false

        let line1 = UIView()
        line1.backgroundColor = VibingColor.separator
        line1.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = L("login.or")
        label.font = VibingFont.caption()
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let line2 = UIView()
        line2.backgroundColor = VibingColor.separator
        line2.translatesAutoresizingMaskIntoConstraints = false

        dividerView.addSubview(line1)
        dividerView.addSubview(label)
        dividerView.addSubview(line2)

        NSLayoutConstraint.activate([
            dividerView.heightAnchor.constraint(equalToConstant: 20),
            line1.leadingAnchor.constraint(equalTo: dividerView.leadingAnchor),
            line1.centerYAnchor.constraint(equalTo: dividerView.centerYAnchor),
            line1.heightAnchor.constraint(equalToConstant: 0.5),
            line1.trailingAnchor.constraint(equalTo: label.leadingAnchor, constant: -12),

            label.centerXAnchor.constraint(equalTo: dividerView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: dividerView.centerYAnchor),

            line2.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            line2.centerYAnchor.constraint(equalTo: dividerView.centerYAnchor),
            line2.heightAnchor.constraint(equalToConstant: 0.5),
            line2.trailingAnchor.constraint(equalTo: dividerView.trailingAnchor),
        ])
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

            // 内容居中，左右 margin 24pt，最大宽度 380pt
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: VibingSpacing.xxl + VibingSpacing.md), // 64pt — 慷慨的顶部呼吸空间
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: VibingSpacing.lg),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -VibingSpacing.lg),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -VibingSpacing.xxl),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
        ])

        // 视觉节奏：Logo → 标题组（紧凑）→ 输入组（紧凑）→ 操作组（紧凑）→ 分隔 → QR
        stack.addArrangedSubview(logoIcon)
        stack.setCustomSpacing(VibingSpacing.lg, after: logoIcon)  // 24pt — logo 和标题间宽松

        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(VibingSpacing.sm, after: titleLabel)  // 8pt — 标题副标题紧凑

        stack.addArrangedSubview(subtitleLabel)
        stack.setCustomSpacing(VibingSpacing.xl, after: subtitleLabel)  // 32pt — 标题组和输入组间慷慨分隔

        stack.addArrangedSubview(serverField)
        stack.setCustomSpacing(VibingSpacing.md, after: serverField)  // 16pt

        stack.addArrangedSubview(usernameField)
        stack.setCustomSpacing(VibingSpacing.sm, after: usernameField)  // 8pt — 输入框间紧凑

        stack.addArrangedSubview(passwordField)
        stack.setCustomSpacing(VibingSpacing.sm, after: passwordField)  // 8pt

        stack.addArrangedSubview(errorLabel)

        stack.addArrangedSubview(submitBtn)
        stack.setCustomSpacing(VibingSpacing.sm, after: submitBtn)  // 8pt

        stack.addArrangedSubview(toggleBtn)
        stack.setCustomSpacing(VibingSpacing.xl, after: toggleBtn)  // 32pt — 操作组和 QR 组间慷慨分隔

        stack.addArrangedSubview(dividerView)
        stack.setCustomSpacing(VibingSpacing.md, after: dividerView)  // 16pt

        stack.addArrangedSubview(qrBtn)

        // Logo 高度
        logoIcon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        // Spinner 叠加在 submit 按钮上
        submitBtn.addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.centerYAnchor.constraint(equalTo: submitBtn.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: submitBtn.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Actions

    private func setupActions() {
        submitBtn.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        toggleBtn.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)
        qrBtn.addTarget(self, action: #selector(qrTapped), for: .touchUpInside)
    }

    @objc private func submitTapped() {
        let server = serverField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = usernameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""

        guard !username.isEmpty, !password.isEmpty else {
            showError(L("login.fillFields"))
            return
        }

        // 保存服务器地址
        if !server.isEmpty {
            UserDefaults.standard.set(server, forKey: "relayServerURL")
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
        UIView.animate(withDuration: 0.2) {
            self.submitBtn.setTitle(
                self.isRegistering ? L("login.register") : L("login.signIn"),
                for: .normal
            )
            self.toggleBtn.setTitle(
                self.isRegistering ? L("login.hasAccount") : L("login.noAccount"),
                for: .normal
            )
        }
    }

    @objc private func qrTapped() {
        let scanner = QRScannerSimpleController { [weak self] code in
            self?.dismiss(animated: true) {
                self?.handleQRCode(code)
            }
        }
        present(scanner, animated: true)
    }

    private func handleQRCode(_ code: String) {
        guard let url = URL(string: code),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let server = components.queryItems?.first(where: { $0.name == "server" })?.value,
              let qrCode = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            showError("Invalid QR code")
            return
        }

        let loading = QRLoginLoadingViewController(server: server, code: qrCode)
        loading.onSuccess = { [weak self] in
            self?.dismiss(animated: true) {
                self?.onLoginSuccess?()
            }
        }
        present(loading, animated: true)
    }

    // MARK: - Helpers

    private func showError(_ text: String) {
        errorLabel.text = text
        errorLabel.isHidden = false
        // 微妙的抖动动画
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.duration = 0.4
        animation.values = [-8, 6, -4, 2, 0]
        errorLabel.layer.add(animation, forKey: "shake")
    }

    private func setLoading(_ loading: Bool) {
        submitBtn.isEnabled = !loading
        if loading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }
}
