//
//  ConnectionStatusBannerView.swift
//  VibeTerminal
//
//  连接状态横幅视图
//

import UIKit

class ConnectionStatusBannerView: UIView {

    // MARK: - Types

    enum ConnectionStatus {
        case connected
        case connecting
        case disconnected
        case error(String)

        var displayColor: UIColor {
            switch self {
            case .connected:
                return .systemGreen
            case .connecting:
                return .systemOrange
            case .disconnected:
                return .systemRed
            case .error:
                return .systemRed
            }
        }

        var displayText: String {
            switch self {
            case .connected:
                return "Connected"
            case .connecting:
                return "Connecting..."
            case .disconnected:
                return "Disconnected"
            case .error(let message):
                return "Error: \(message)"
            }
        }

        var iconName: String? {
            switch self {
            case .connected:
                return "checkmark.circle.fill"
            case .connecting:
                return "arrow.triangle.2.circlepath"
            case .disconnected:
                return "xmark.circle.fill"
            case .error:
                return "exclamationmark.triangle.fill"
            }
        }
    }

    // MARK: - Properties

    private let statusIndicator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 6
        return view
    }()

    private let statusIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .label
        return imageView
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .label
        return label
    }()

    private let hostInfoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private var currentStatus: ConnectionStatus = .disconnected
    private var isCompactMode: Bool = false

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .systemBackground
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 2

        addSubview(statusIndicator)
        addSubview(statusIconView)
        addSubview(statusLabel)
        addSubview(hostInfoLabel)
        addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            statusIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusIndicator.widthAnchor.constraint(equalToConstant: 12),
            statusIndicator.heightAnchor.constraint(equalToConstant: 12),

            statusIconView.leadingAnchor.constraint(equalTo: statusIndicator.trailingAnchor, constant: 8),
            statusIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusIconView.widthAnchor.constraint(equalToConstant: 20),
            statusIconView.heightAnchor.constraint(equalToConstant: 20),

            statusLabel.leadingAnchor.constraint(equalTo: statusIconView.trailingAnchor, constant: 8),
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: activityIndicator.leadingAnchor, constant: -8),

            hostInfoLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            hostInfoLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            hostInfoLabel.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),

            activityIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    // MARK: - Public Methods

    /// 更新连接状态
    func updateStatus(_ status: ConnectionStatus, host: String? = nil, isCompact: Bool = false) {
        self.currentStatus = status
        self.isCompactMode = isCompact

        // 更新指示器颜色
        statusIndicator.backgroundColor = status.displayColor

        // 更新图标
        if let iconName = status.iconName {
            statusIconView.image = UIImage(systemName: iconName)
            statusIconView.isHidden = false
        } else {
            statusIconView.isHidden = true
        }

        // 更新文本
        statusLabel.text = status.displayText

        // 更新主机信息
        if let host = host, !isCompact {
            hostInfoLabel.text = host
            hostInfoLabel.isHidden = false
        } else {
            hostInfoLabel.isHidden = true
        }

        // 更新活动指示器
        switch status {
        case .connecting:
            activityIndicator.startAnimating()
        default:
            activityIndicator.stopAnimating()
        }

        // 更新约束（紧凑模式）
        updateConstraintsForCompactMode(isCompact)

        // 触发动画
        animateStatusChange()
    }

    /// 设置是否为紧凑模式
    func setCompactMode(_ isCompact: Bool, animated: Bool = true) {
        self.isCompactMode = isCompact
        updateConstraintsForCompactMode(isCompact)

        if animated {
            UIView.animate(withDuration: 0.25) {
                self.layoutIfNeeded()
            }
        }
    }

    // MARK: - Private Methods

    private func updateConstraintsForCompactMode(_ isCompact: Bool) {
        statusLabel.isHidden = isCompact
        hostInfoLabel.isHidden = isCompact || hostInfoLabel.text == nil

        if isCompact {
            // 紧凑模式：只显示指示器和图标
            statusIconView.leadingAnchor.constraint(equalTo: statusIndicator.trailingAnchor, constant: 4).isActive = true
        } else {
            // 标准模式
            statusIconView.leadingAnchor.constraint(equalTo: statusIndicator.trailingAnchor, constant: 8).isActive = true
        }
    }

    private func animateStatusChange() {
        // 淡入淡出动画
        alpha = 0.7
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1.0
        }

        // 指示器脉冲动画
        statusIndicator.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) {
            self.statusIndicator.transform = .identity
        }
    }
}

// MARK: - UIView Extension for Pulse Animation

extension UIView {
    func pulseAnimation(duration: TimeInterval = 0.3) {
        UIView.animate(withDuration: duration, animations: {
            self.alpha = 0.6
            self.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        }) { _ in
            UIView.animate(withDuration: duration) {
                self.alpha = 1.0
                self.transform = .identity
            }
        }
    }
}
