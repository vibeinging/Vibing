//
//  KeyboardAccessoryView.swift
//  Vibing
//
//  键盘辅助视图 - 为终端提供额外按键
//

import UIKit

// MARK: - Accessory Key Type

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
    case modifier(KeyModifiers)
    case functionKey(String)

    var title: String {
        switch self {
        case .escape: return "Esc"
        case .tab: return "Tab"
        case .arrowUp: return "↑"
        case .arrowDown: return "↓"
        case .arrowLeft: return "←"
        case .arrowRight: return "→"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PgUp"
        case .pageDown: return "PgDn"
        case .insert: return "Ins"
        case .delete: return "Del"
        case .f(let num): return "F\(num)"
        case .character(let char): return char
        case .modifier(let mod):
            switch mod {
            case .control: return "Ctrl"
            case .alt: return "Alt"
            case .shift: return "Shift"
            case .meta: return "Cmd"
            default: return ""
            }
        case .functionKey(let name): return name
        }
    }
}

// MARK: - Key Modifiers

struct KeyModifiers: OptionSet {
    let rawValue: UInt8

    static let control = KeyModifiers(rawValue: 1 << 0)
    static let alt = KeyModifiers(rawValue: 1 << 1)
    static let shift = KeyModifiers(rawValue: 1 << 2)
    static let meta = KeyModifiers(rawValue: 1 << 3)
}

// MARK: - Keyboard Accessory Delegate

protocol KeyboardAccessoryDelegate: AnyObject {
    func accessoryView(_ view: KeyboardAccessoryView, didPressKey key: AccessoryKey, modifiers: KeyModifiers)
    func accessoryViewDidChangeModifierState(_ view: KeyboardAccessoryView, modifiers: KeyModifiers)
}

// MARK: - Keyboard Accessory View

class KeyboardAccessoryView: UIView {

    weak var delegate: KeyboardAccessoryDelegate?

    // 当前激活的修饰键
    private var activeModifiers: KeyModifiers = []

    // 修饰键按钮
    private var modifierButtons: [UIButton: KeyModifiers] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .systemGray6

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 1
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // 第一行按键
        let row1Keys: [AccessoryKey] = [
            .escape, .f(1), .f(2), .f(3), .f(4), .f(5),
            .arrowLeft, .arrowUp, .arrowDown, .arrowRight
        ]

        for key in row1Keys {
            let button = createKeyButton(for: key)
            stackView.addArrangedSubview(button)
        }

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    private func createKeyButton(for key: AccessoryKey) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(key.title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 4
        button.tag = hashKey(key)

        button.addTarget(self, action: #selector(keyPressed(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(keyReleased(_:)), for: [.touchUpInside, .touchUpOutside])

        return button
    }

    private func hashKey(_ key: AccessoryKey) -> Int {
        switch key {
        case .escape: return 1000
        case .tab: return 1001
        case .arrowUp: return 1010
        case .arrowDown: return 1011
        case .arrowLeft: return 1012
        case .arrowRight: return 1013
        case .home: return 1020
        case .end: return 1021
        case .pageUp: return 1022
        case .pageDown: return 1023
        case .insert: return 1024
        case .delete: return 1025
        case .f(let num): return 2000 + Int(num)
        case .character(let char): return char.hashValue
        case .modifier(let mod): return 3000 + Int(mod.rawValue)
        case .functionKey(let name): return name.hashValue
        }
    }

    @objc private func keyPressed(_ button: UIButton) {
        button.backgroundColor = .systemGray4

        let key = keyForTag(button.tag)
        delegate?.accessoryView(self, didPressKey: key, modifiers: activeModifiers)
    }

    @objc private func keyReleased(_ button: UIButton) {
        button.backgroundColor = .systemBackground
    }

    private func keyForTag(_ tag: Int) -> AccessoryKey {
        if tag >= 2000 && tag < 2013 {
            return .f(UInt8(tag - 2000))
        }
        switch tag {
        case 1000: return .escape
        case 1001: return .tab
        case 1010: return .arrowUp
        case 1011: return .arrowDown
        case 1012: return .arrowLeft
        case 1013: return .arrowRight
        case 1020: return .home
        case 1021: return .end
        case 1022: return .pageUp
        case 1023: return .pageDown
        case 1024: return .insert
        case 1025: return .delete
        default: return .character("")
        }
    }
}
