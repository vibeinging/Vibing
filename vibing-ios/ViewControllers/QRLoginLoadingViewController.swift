//
//  QRLoginLoadingViewController.swift
//  Vibing (iOS)
//
//  扫码后的自动登录加载页 — 解析 vibing://login URL 并完成登录
//

import UIKit

class QRLoginLoadingViewController: UIViewController {

    let server: String
    let code: String
    var onSuccess: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private let accent = UIColor(red: 106/255, green: 194/255, blue: 120/255, alpha: 1)

    // UI
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let checkmark = UIImageView()

    init(server: String, code: String) {
        self.server = server
        self.code = code
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildUI()
        performLogin()
    }

    private func buildUI() {
        // Icon
        iconView.image = UIImage(systemName: "qrcode", withConfiguration: UIImage.SymbolConfiguration(pointSize: 48, weight: .light))
        iconView.tintColor = accent
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Title
        titleLabel.text = L("login.qrTitle")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Status
        statusLabel.text = L("sessions.connecting")
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // Spinner
        spinner.color = accent
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        // Checkmark (hidden initially)
        checkmark.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 48, weight: .medium))
        checkmark.tintColor = accent
        checkmark.contentMode = .scaleAspectFit
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.alpha = 0
        checkmark.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, statusLabel, spinner])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addSubview(checkmark)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),

            checkmark.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
        ])
    }

    private func performLogin() {
        // 先设置服务器地址，qrLogin 会读这个
        UserDefaults.standard.set(server, forKey: "relayServerURL")

        Task {
            do {
                try await AccountManager.shared.qrLogin(code: code)

                await MainActor.run {
                    showSuccess()
                }

                // 延迟后跳转
                try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s
                await MainActor.run {
                    onSuccess?()
                }
            } catch {
                await MainActor.run {
                    showError(error.localizedDescription)
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                await MainActor.run {
                    onFailure?(error.localizedDescription)
                }
            }
        }
    }

    private func showSuccess() {
        statusLabel.text = "Login successful"
        statusLabel.textColor = accent
        spinner.stopAnimating()

        // Animate checkmark in, icon out
        UIView.animate(withDuration: 0.15) {
            self.iconView.alpha = 0
            self.iconView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }

        UIView.animate(withDuration: 0.5, delay: 0.1, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8, options: []) {
            self.checkmark.alpha = 1
            self.checkmark.transform = .identity
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func showError(_ message: String) {
        statusLabel.text = message
        statusLabel.textColor = .systemRed
        spinner.stopAnimating()
        iconView.tintColor = .systemRed
        iconView.image = UIImage(systemName: "xmark.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 48, weight: .light))
    }
}
