//
//  KeyboardAccessoryView.swift
//  Vibing
//
//  键盘辅助视图 - 为终端输入提供额外的按键支持
//  参考 OpenTerm 的 InputAssistant 设计
//

import UIKit

// MARK: - Key Configuration

/// 按键配置结构
struct KeyConfiguration {
    struct Key {
        let title: String
        let keyType: AccessoryKey
        let width: CGFloat // 相对宽度，1.0 为标准宽度
        let row: Int // 行索引
        let isToggle: Bool // 是否为切换键（如 Ctrl、Alt）
        let longPressKeys: [AccessoryKey]? // 长按显示的额外按键
    }

    let keys: [[Key]] // 按行组织的按键
    let height: CGFloat

    /// iPhone 竖屏配置
    static var iPhonePortrait: KeyConfiguration {
        let row1: [Key] = [
            Key(title: "Esc", keyType: .escape, width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "Tab", keyType: .tab, width: 1.2, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "Ctrl", keyType: .modifier(.control), width: 1.2, row: 0, isToggle: true, longPressKeys: nil),
            Key(title: "Alt", keyType: .modifier(.alt), width: 1.2, row: 0, isToggle: true, longPressKeys: nil),
            Key(title: "-", keyType: .character("-"), width: 1.0, row: 0, isToggle: false, longPressKeys: [.character("_")]),
            Key(title: "/", keyType: .character("/"), width: 1.0, row: 0, isToggle: false, longPressKeys: [.character("\\")]),
        ]

        let row2: [Key] = [
            Key(title: "FN", keyType: .functionKey, width: 1.0, row: 1, isToggle: true, longPressKeys: nil),
            Key(title: "↑", keyType: .arrowUp, width: 1.0, row: 1, isToggle: false, longPressKeys: nil),
            Key(title: "↓", keyType: .arrowDown, width: 1.0, row: 1, isToggle: false, longPressKeys: nil),
            Key(title: "←", keyType: .arrowLeft, width: 1.0, row: 1, isToggle: false, longPressKeys: nil),
            Key(title: "→", keyType: .arrowRight, width: 1.0, row: 1, isToggle: false, longPressKeys: nil),
            Key(title: "|", keyType: .character("|"), width: 1.0, row: 1, isToggle: false, longPressKeys: nil),
        ]

        return KeyConfiguration(keys: [row1, row2], height: 50)
    }

    /// iPhone 横屏配置 - 更多空间，显示更多按键
    static var iPhoneLandscape: KeyConfiguration {
        let row1: [Key] = [
            Key(title: "Esc", keyType: .escape, width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "Tab", keyType: .tab, width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "Ctrl", keyType: .modifier(.control), width: 1.0, row: 0, isToggle: true, longPressKeys: nil),
            Key(title: "Alt", keyType: .modifier(.alt), width: 1.0, row: 0, isToggle: true, longPressKeys: nil),
            Key(title: "-", keyType: .character("-"), width: 0.8, row: 0, isToggle: false, longPressKeys: [.character("_")]),
            Key(title: "/", keyType: .character("/"), width: 0.8, row: 0, isToggle: false, longPressKeys: [.character("\\")]),
            Key(title: "|", keyType: .character("|"), width: 0.8, row: 0, isToggle: false, longPressKeys: nil),
        ]

        let row2: [Key] = [
            Key(title: "Home", keyType: .home, width: 1.0, row: 1, isToggle: false, longPressKeys: nil),
            Key(title: "End", keyType: .end, width: 1.0, row: 1, isToggle: false, longPressKeys: nil),
            Key(title: "PgUp", keyType: .pageUp, width: 1.0, row: 1, isToggle: false, longPressKeys: nil),
            Key(title: "PgDn", keyType: .pageDown, width: 1.0, row: 1, isToggle: false, longPressKeys: nil),
            Key(title: "FN", keyType: .functionKey, width: 1.0, row: 1, isToggle: true, longPressKeys: nil),
        ]

        let row3: [Key] = [
            Key(title: "↑", keyType: .arrowUp, width: 1.0, row: 2, isToggle: false, longPressKeys: nil),
            Key(title: "←", keyType: .arrowLeft, width: 1.0, row: 2, isToggle: false, longPressKeys: nil),
            Key(title: "↓", keyType: .arrowDown, width: 1.0, row: 2, isToggle: false, longPressKeys: nil),
            Key(title: "→", keyType: .arrowRight, width: 1.0, row: 2, isToggle: false, longPressKeys: nil),
        ]

        return KeyConfiguration(keys: [row1, row2, row3], height: 45)
    }

    /// iPad 竖屏配置 - 完整键盘布局
    static var iPadPortrait: KeyConfiguration {
        let row1: [Key] = [
            Key(title: "Esc", keyType: .escape, width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F1", keyType: .f(1), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F2", keyType: .f(2), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F3", keyType: .f(3), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F4", keyType: .f(4), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F5", keyType: .f(5), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F6", keyType: .f(6), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F7", keyType: .f(7), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F8", keyType: .f(8), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F9", keyType: .f(9), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F10", keyType: .f(10), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F11", keyType: .f(11), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
            Key(title: "F12", keyType: .f(12), width: 1.0, row: 0, isToggle: false, longPressKeys: nil),
        ]

        let row2: [Key] = [
            Key(title: "Tab", keyType: .tab, width: 1.2, row: 1, isToggle: false, longPressKeys: nil),
            Key(title: "Ctrl", keyType: .modifier(.control), width: 1.2, row: 1, isToggle: true, longPressKeys: nil),
            Key(title: "Alt", keyType: .modifier(.alt), width: 1.2, row: 1, isToggle: true, longPressKeys: nil),
            Key(title: "-", keyType: .character("-"), width: 1.0, row: 1, isToggle: false, longPressKeys: [.character("_")]),
            Key(title: "/", keyType: .character("/"), width: 1.0, row: 1, isToggle: false, longPressKeys: [.character("\\")]),
            Key(title: "|", keyType: .character("|"), width: 1.0, row: 1, isToggle: false, longPressKeys: nil),
            Key(title: "~", keyType: .character("~"), width: 1.0, row: 1, isToggle: false, longPressKeys: [.character("`")]),
        ]

        let row3: [Key] = [
            Key(title: "Home", keyType: .home, width: 1.0, row: 2, isToggle: false, longPressKeys: nil),
            Key(title: "End", keyType: .end, width: 1.0, row: 2, isToggle: false, longPressKeys: nil),
            Key(title: "PgUp", keyType: .pageUp, width: 1.0, row: 2, isToggle: false, longPressKeys: nil),
            Key(title: "PgDn", keyType: .pageDown, width: 1.0, row: 2, isToggle: false, longPressKeys: nil),
            Key(title: "Ins", keyType: .insert, width: 1.0, row: 2, isToggle: false, longPressKeys: nil),
            Key(title: "Del", keyType: .delete, width: 1.0, row: 2, isToggle: false, longPressKeys: nil),
        ]

        let row4: [Key] = [
            Key(title: "↑", keyType: .arrowUp, width: 1.0, row: 3, isToggle: false, longPressKeys: nil),
            Key(title: "←", keyType: .arrowLeft, width: 1.0, row: 3, isToggle: false, longPressKeys: nil),
            Key(title: "↓", keyType: .arrowDown, width: 1.0, row: 3, isToggle: false, longPressKeys: nil),
            Key(title: "→", keyType: .arrowRight, width: 1.0, row: 3, isToggle: false, longPressKeys: nil),
        ]

        return KeyConfiguration(keys: [row1, row2, row3, row4], height: 40)
    }

    /// iPad 横屏配置 - 完整键盘布局
    static var iPadLandscape: KeyConfiguration {
        return iPadPortrait // 横屏使用相同布局
    }
}

// MARK: - Accessory Key Type

/// 键盘辅助按键类型
enum AccessoryKey {
    case escape
    case tab
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case home
    case end
    case pageUp
    case pageDown
    case insert
    case delete
    case f(UInt8)
    case character(String)
    case modifier(ModifierKey)
    case functionKey // 用于展开 F1-F12

    enum ModifierKey {
        case control
        case alt
        case shift
    }
}

// MARK: - Delegate Protocol

/// 键盘辅助视图代理协议
protocol KeyboardAccessoryDelegate: AnyObject {
    func accessoryView(_ view: KeyboardAccessoryView, didPressKey key: AccessoryKey, modifiers: KeyModifiers)
    func accessoryViewDidChangeModifierState(_ view: KeyboardAccessoryView, modifiers: KeyModifiers)
}

/// 按键修饰符状态
struct KeyModifiers: OptionSet {
    let rawValue: UInt8
    static let control = KeyModifiers(rawValue: 1 << 0)
    static let alt = KeyModifiers(rawValue: 1 << 1)
    static let shift = KeyModifiers(rawValue: 1 << 2)
    static let meta = KeyModifiers(rawValue: 1 << 3)
}

// MARK: - Keyboard Accessory View

/// 键盘辅助视图 - 终端输入的扩展按键栏
class KeyboardAccessoryView: UIInputView {

    // MARK: - Properties

    weak var delegate: KeyboardAccessoryDelegate?

    private var keyButtons: [[KeyButton]] = []
    private let keyConfig: KeyConfiguration
    private var modifierState: KeyModifiers = []

    // F 键切换状态
    private var isFunctionKeysExpanded = false
    private var baseKeyConfig: KeyConfiguration

    // 视觉样式
    private let backgroundColorNormal: UIColor
    private let backgroundColorHighlighted: UIColor
    private let backgroundColorToggleActive: UIColor

    // MARK: - Initialization

    init(keyConfig: KeyConfiguration = .iPhonePortrait) {
        self.keyConfig = keyConfig
        self.baseKeyConfig = keyConfig

        // 根据当前外观设置颜色
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        if isDark {
            self.backgroundColorNormal = UIColor(white: 0.2, alpha: 1.0)
            self.backgroundColorHighlighted = UIColor(white: 0.4, alpha: 1.0)
            self.backgroundColorToggleActive = UIColor(white: 0.15, alpha: 1.0)
        } else {
            self.backgroundColorNormal = UIColor(white: 0.9, alpha: 1.0)
            self.backgroundColorHighlighted = UIColor(white: 0.7, alpha: 1.0)
            self.backgroundColorToggleActive = UIColor(white: 0.85, alpha: 1.0)
        }

        super.init(frame: .zero, inputViewStyle: .default)

        setup()
    }

    required init?(coder: NSCoder) {
        self.keyConfig = .iPhonePortrait
        self.baseKeyConfig = .iPhonePortrait

        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        if isDark {
            self.backgroundColorNormal = UIColor(white: 0.2, alpha: 1.0)
            self.backgroundColorHighlighted = UIColor(white: 0.4, alpha: 1.0)
            self.backgroundColorToggleActive = UIColor(white: 0.15, alpha: 1.0)
        } else {
            self.backgroundColorNormal = UIColor(white: 0.9, alpha: 1.0)
            self.backgroundColorHighlighted = UIColor(white: 0.7, alpha: 1.0)
            self.backgroundColorToggleActive = UIColor(white: 0.85, alpha: 1.0)
        }

        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        self.allowsSelfSizing = true

        // 主容器 - 垂直堆叠行
        let mainStackView = UIStackView()
        mainStackView.axis = .vertical
        mainStackView.spacing = 1
        mainStackView.alignment = .fill
        mainStackView.distribution = .fill

        // 为每一行创建按键
        for (rowIndex, rowKeys) in keyConfig.keys.enumerated() {
            let rowStackView = createRowStackView(for: rowKeys, rowIndex: rowIndex)
            mainStackView.addArrangedSubview(rowStackView)
        }

        addSubview(mainStackView)
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            mainStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            mainStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            mainStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    private func createRowStackView(for keys: [KeyConfiguration.Key], rowIndex: Int) -> UIStackView {
        let rowStackView = UIStackView()
        rowStackView.axis = .horizontal
        rowStackView.spacing = 1
        rowStackView.alignment = .fill
        rowStackView.distribution = .fill

        var rowButtons: [KeyButton] = []

        for key in keys {
            let button = createButton(for: key)
            rowStackView.addArrangedSubview(button)
            rowButtons.append(button)
        }

        keyButtons.append(rowButtons)

        // 设置高度约束
        rowStackView.heightAnchor.constraint(equalToConstant: keyConfig.height - 4).isActive = true

        return rowStackView
    }

    private func createButton(for key: KeyConfiguration.Key) -> KeyButton {
        let button = KeyButton(key: key)

        button.setTitle(key.title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        // 设置按钮样式
        button.setBackgroundImage(createImage(with: backgroundColorNormal), for: .normal)
        button.setBackgroundImage(createImage(with: backgroundColorHighlighted), for: .highlighted)
        button.setBackgroundImage(createImage(with: backgroundColorToggleActive), for: .selected)

        button.layer.cornerRadius = 4
        button.layer.masksToBounds = true
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.separator.cgColor

        // 添加点击事件
        button.addTarget(self, action: #selector(keyButtonTapped(_:)), for: .touchUpInside)

        // 添加长按手势
        if let longPressKeys = key.longPressKeys, !longPressKeys.isEmpty {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            button.addGestureRecognizer(longPress)
        }

        return button
    }

    private func createImage(with color: UIColor) -> UIImage {
        let size = CGSize(width: 1, height: 1)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Layout

    func updateLayout(for size: CGSize) {
        // 根据屏幕尺寸更新配置
        let isCompact = UIScreen.main.traitCollection.horizontalSizeClass == .compact
        let isPortrait = size.width < size.height

        let newConfig: KeyConfiguration

        if !isCompact {
            // iPad
            newConfig = isPortrait ? .iPadPortrait : .iPadLandscape
        } else {
            // iPhone
            newConfig = isPortrait ? .iPhonePortrait : .iPhoneLandscape
        }

        if newConfig.keys.count != keyConfig.keys.count {
            // 需要重新构建整个视图
            rebuild(with: newConfig)
        }
    }

    private func rebuild(with config: KeyConfiguration) {
        // 移除所有子视图
        subviews.forEach { $0.removeFromSuperview() }
        keyButtons.removeAll()

        // 更新配置并重新设置
        // 注意：由于 struct 是值类型，这里需要特殊处理
        // 实际实现中可以存储为引用类型或使用其他方式
        setup()
    }

    // MARK: - Actions

    @objc private func keyButtonTapped(_ sender: KeyButton) {
        UIDevice.current.playInputClick()

        let key = sender.key
        var modifiers = modifierState

        // 处理特殊按键
        switch key.keyType {
        case .modifier(let modifierKey):
            toggleModifier(modifierKey)
            updateButtonStates()
            return

        case .functionKey:
            toggleFunctionKeys()
            return

        default:
            break
        }

        // 通知代理
        delegate?.accessoryView(self, didPressKey: key.keyType, modifiers: modifiers)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? KeyButton,
              let longPressKeys = button.key.longPressKeys,
              !longPressKeys.isEmpty,
              gesture.state == .began else {
            return
        }

        UIDevice.current.playInputClick()

        // 显示长按选项菜单
        showLongPressMenu(for: longPressKeys, from: button)
    }

    private func showLongPressMenu(for keys: [AccessoryKey], from button: UIButton) {
        let menuController = UIMenuController.shared

        let menuItems = keys.map { key -> UIMenuItem in
            let title: String
            switch key {
            case .character(let char):
                title = char
            case .f(let num):
                title = "F\(num)"
            default:
                title = ""
            }
            return UIMenuItem(title: title, action: #selector(longPressMenuItemSelected(_:)))
        }

        menuController.menuItems = menuItems
        menuController.showMenu(from: self, rect: button.frame)
    }

    @objc private func longPressMenuItemSelected(_ sender: UIMenuItem) {
        // 处理长按菜单项选择
        guard let key = parseKeyFromMenuItemTitle(sender.title) else { return }
        delegate?.accessoryView(self, didPressKey: key, modifiers: modifierState)
    }

    private func parseKeyFromMenuItemTitle(_ title: String) -> AccessoryKey? {
        if title.hasPrefix("F"), let num = UInt8(title.dropFirst()) {
            return .f(num)
        }
        return .character(title)
    }

    // MARK: - Modifier State Management

    private func toggleModifier(_ modifier: AccessoryKey.ModifierKey) {
        switch modifier {
        case .control:
            modifierState.toggle(.control)
        case .alt:
            modifierState.toggle(.alt)
        case .shift:
            modifierState.toggle(.shift)
        }

        delegate?.accessoryViewDidChangeModifierState(self, modifiers: modifierState)
    }

    private func updateButtonStates() {
        for row in keyButtons {
            for button in row {
                if button.key.isToggle {
                    let isActive: Bool
                    switch button.key.keyType {
                    case .modifier(let mod):
                        switch mod {
                        case .control:
                            isActive = modifierState.contains(.control)
                        case .alt:
                            isActive = modifierState.contains(.alt)
                        case .shift:
                            isActive = modifierState.contains(.shift)
                        }
                    default:
                        isActive = false
                    }
                    button.isSelected = isActive
                }
            }
        }
    }

    // MARK: - Function Keys Expansion

    private func toggleFunctionKeys() {
        isFunctionKeysExpanded.toggle()

        if isFunctionKeysExpanded {
            // 展开显示 F1-F12
            showFunctionKeysAlert()
        }
    }

    private func showFunctionKeysAlert() {
        let alert = UIAlertController(title: "Function Keys", message: "Select a function key", preferredStyle: .actionSheet)

        for i in 1...12 {
            alert.addAction(UIAlertAction(title: "F\(i)", style: .default) { [weak self] _ in
                self?.delegate?.accessoryView(self!, didPressKey: .f(UInt8(i)), modifiers: self?.modifierState ?? [])
                self?.isFunctionKeysExpanded = false
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.isFunctionKeysExpanded = false
        })

        // 获取当前视图控制器
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }

    // MARK: - Cleanup

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Key Button

/// 自定义按键按钮
private class KeyButton: UIButton {
    let key: KeyConfiguration.Key
    private var widthConstraint: NSLayoutConstraint?

    init(key: KeyConfiguration.Key) {
        self.key = key
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        // 设置宽度约束
        let multiplier = key.width
        widthConstraint = widthAnchor.constraint(equalTo: heightAnchor, multiplier: multiplier)
        widthConstraint?.isActive = true
    }
}

// MARK: - UIInputViewAudioFeedback

extension KeyboardAccessoryView: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool {
        return true
    }
}
