//
//  DesignSystem.swift
//  Vibing (iOS)
//
//  统一设计系统 — 色彩、字体、间距、动画
//

import UIKit

// MARK: - Brand Colors

enum VibingColor {
    /// 品牌主色 — 春天嫩绿
    static let accent = UIColor(red: 106/255, green: 194/255, blue: 120/255, alpha: 1)
    static let accentSubtle = accent.withAlphaComponent(0.12)
    static let accentMedium = accent.withAlphaComponent(0.25)

    /// 终端背景
    static let terminalBg = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 22/255, green: 21/255, blue: 20/255, alpha: 1)
            : UIColor(red: 250/255, green: 248/255, blue: 245/255, alpha: 1)
    }

    /// 终端前景
    static let terminalFg = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 210/255, green: 206/255, blue: 197/255, alpha: 1)
            : UIColor(red: 38/255, green: 35/255, blue: 30/255, alpha: 1)
    }

    /// 在线状态绿
    static let online = UIColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 1)

    /// 微弱分隔线
    static let separator = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.black.withAlphaComponent(0.06)
    }

    /// 卡片/Cell 背景
    static let cardBg = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 30/255, green: 29/255, blue: 27/255, alpha: 1)
            : .white
    }

    /// 输入框背景
    static let inputBg = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 42/255, green: 40/255, blue: 37/255, alpha: 1)
            : UIColor(red: 242/255, green: 240/255, blue: 237/255, alpha: 1)
    }

    /// 页面背景
    static let pageBg = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 16/255, green: 15/255, blue: 14/255, alpha: 1)
            : UIColor(red: 242/255, green: 240/255, blue: 237/255, alpha: 1)
    }
}

// MARK: - Typography

enum VibingFont {
    static func largeTitle() -> UIFont {
        .systemFont(ofSize: 34, weight: .bold)
    }
    static func title1() -> UIFont {
        .systemFont(ofSize: 28, weight: .bold)
    }
    static func title2() -> UIFont {
        .systemFont(ofSize: 22, weight: .bold)
    }
    static func title3() -> UIFont {
        .systemFont(ofSize: 20, weight: .semibold)
    }
    static func headline() -> UIFont {
        .systemFont(ofSize: 17, weight: .semibold)
    }
    static func body() -> UIFont {
        .systemFont(ofSize: 17, weight: .regular)
    }
    static func callout() -> UIFont {
        .systemFont(ofSize: 16, weight: .regular)
    }
    static func subheadline() -> UIFont {
        .systemFont(ofSize: 15, weight: .regular)
    }
    static func footnote() -> UIFont {
        .systemFont(ofSize: 13, weight: .regular)
    }
    static func caption() -> UIFont {
        .systemFont(ofSize: 12, weight: .regular)
    }
    static func mono(_ size: CGFloat = 13, weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

// MARK: - Spacing

enum VibingSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Animation

enum VibingAnimation {
    static func spring(_ animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.1,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: animations,
            completion: completion
        )
    }

    static func quick(_ animations: @escaping () -> Void) {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: animations)
    }
}

// MARK: - Reusable Components

class VibingTextField: UITextField {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = VibingColor.inputBg
        textColor = .label
        font = VibingFont.body()
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        autocapitalizationType = .none
        autocorrectionType = .no

        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
        leftView = paddingView
        leftViewMode = .always
        rightView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
        rightViewMode = .always

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 50).isActive = true
    }

    func setPlaceholder(_ text: String) {
        attributedPlaceholder = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: UIColor.tertiaryLabel]
        )
    }
}

class VibingPrimaryButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = VibingColor.accent
        setTitleColor(.white, for: .normal)
        titleLabel?.font = VibingFont.headline()
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 54).isActive = true
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.alpha = self.isHighlighted ? 0.85 : 1
            }
        }
    }

    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.5
        }
    }
}

class VibingSecondaryButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = VibingColor.inputBg
        setTitleColor(.label, for: .normal)
        titleLabel?.font = VibingFont.callout()
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = VibingColor.separator.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 54).isActive = true
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.alpha = self.isHighlighted ? 0.7 : 1
            }
        }
    }
}
