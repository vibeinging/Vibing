//
//  SessionDetailViewController.swift
//  Vibing (iOS)
//
//  终端 Session 查看器 — 查看输出 + 发送消息
//  为 Claude Code 等 CLI 工具的远程观察和控制而设计
//

import UIKit

class SessionDetailViewController: UIViewController {

    private let sessionId: String
    private weak var wsClient: WebSocketClient?
    private var isSubscribed = false
    private var autoScroll = true

    // MARK: - UI

    private let outputTextView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.backgroundColor = VibingColor.terminalBg
        tv.textColor = VibingColor.terminalFg
        tv.font = VibingFont.mono(14)
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.indicatorStyle = .white
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.keyboardDismissMode = .interactive
        return tv
    }()

    private let inputBar: UIView = {
        let v = UIView()
        v.backgroundColor = VibingColor.cardBg
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let inputBarSeparator: UIView = {
        let v = UIView()
        v.backgroundColor = VibingColor.separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let inputField: UITextField = {
        let tf = UITextField()
        tf.font = VibingFont.mono(15)
        tf.textColor = .label
        tf.backgroundColor = VibingColor.inputBg
        tf.layer.cornerRadius = 10
        tf.layer.cornerCurve = .continuous
        tf.returnKeyType = .send
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.attributedPlaceholder = NSAttributedString(
            string: L("session.typeCommand"),
            attributes: [.foregroundColor: UIColor.tertiaryLabel, .font: VibingFont.mono(15)]
        )
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        tf.leftView = paddingView
        tf.leftViewMode = .always
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let sendButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        b.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config), for: .normal)
        b.tintColor = VibingColor.accent
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let quickActionsScroll: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let quickActionsStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 8
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private var inputBarBottom: NSLayoutConstraint!

    // Quick action definitions: (label, sequence)
    private let quickActions: [(String, String)] = [
        ("⌃C", "\u{03}"),
        ("⌃D", "\u{04}"),
        ("⌃Z", "\u{1A}"),
        ("⌃L", "\u{0C}"),
        ("Tab", "\t"),
        ("↑", "\u{1B}[A"),
        ("↓", "\u{1B}[B"),
        ("Esc", "\u{1B}"),
    ]

    // MARK: - Init

    init(sessionId: String, wsClient: WebSocketClient?) {
        self.sessionId = sessionId
        self.wsClient = wsClient
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let shortId = String(sessionId.prefix(8))
        title = "Session \(shortId)"
        view.backgroundColor = VibingColor.terminalBg
        navigationItem.largeTitleDisplayMode = .never

        buildLayout()
        setupActions()
        setupKeyboardObservers()
        subscribe()

        // DEBUG: 注入假终端输出
        if wsClient == nil {
            injectMockOutput()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    private func buildLayout() {
        view.addSubview(outputTextView)
        view.addSubview(inputBar)
        inputBar.addSubview(inputBarSeparator)
        inputBar.addSubview(quickActionsScroll)
        quickActionsScroll.addSubview(quickActionsStack)
        inputBar.addSubview(inputField)
        inputBar.addSubview(sendButton)

        inputBarBottom = inputBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            outputTextView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            outputTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outputTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outputTextView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarBottom,

            inputBarSeparator.topAnchor.constraint(equalTo: inputBar.topAnchor),
            inputBarSeparator.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor),
            inputBarSeparator.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor),
            inputBarSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            quickActionsScroll.topAnchor.constraint(equalTo: inputBar.topAnchor, constant: 8),
            quickActionsScroll.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor),
            quickActionsScroll.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor),
            quickActionsScroll.heightAnchor.constraint(equalToConstant: 34),

            quickActionsStack.topAnchor.constraint(equalTo: quickActionsScroll.topAnchor),
            quickActionsStack.leadingAnchor.constraint(equalTo: quickActionsScroll.leadingAnchor, constant: 12),
            quickActionsStack.trailingAnchor.constraint(equalTo: quickActionsScroll.trailingAnchor, constant: -12),
            quickActionsStack.bottomAnchor.constraint(equalTo: quickActionsScroll.bottomAnchor),
            quickActionsStack.heightAnchor.constraint(equalTo: quickActionsScroll.heightAnchor),

            inputField.topAnchor.constraint(equalTo: quickActionsScroll.bottomAnchor, constant: 8),
            inputField.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputField.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor, constant: -10),
            inputField.heightAnchor.constraint(equalToConstant: 42),

            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
        ])

        // Build quick action buttons
        for (i, (label, _)) in quickActions.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(label, for: .normal)
            btn.titleLabel?.font = VibingFont.mono(13, weight: .medium)
            btn.tintColor = .secondaryLabel
            btn.backgroundColor = VibingColor.inputBg
            btn.layer.cornerRadius = 8
            btn.layer.cornerCurve = .continuous
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
            btn.tag = i
            btn.addTarget(self, action: #selector(quickActionTapped(_:)), for: .touchUpInside)
            quickActionsStack.addArrangedSubview(btn)
        }
    }

    // MARK: - Actions

    private func setupActions() {
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        inputField.delegate = self
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    // MARK: - WebSocket

    private func subscribe() {
        wsClient?.sendTextMessage([
            "type": "subscribe",
            "session_ids": [sessionId]
        ])
        isSubscribed = true
    }

    private func sendInput(_ text: String) {
        wsClient?.sendTextInput(sessionId: sessionId, text: text)
    }

    // MARK: - Output

    func handleFrame(_ frame: Frame) {
        switch frame {
        case .sessionOutput(_, let screenFrame):
            appendScreenFrame(screenFrame)
        default:
            break
        }
    }

    private func appendScreenFrame(_ frame: ScreenFrame) {
        var text = ""
        for region in frame.dirtyRegions {
            for cell in region.cells {
                text += cell.char
            }
            text += "\n"
        }

        guard !text.isEmpty else { return }

        DispatchQueue.main.async {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: VibingFont.mono(14),
                .foregroundColor: VibingColor.terminalFg
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let mutable = NSMutableAttributedString(attributedString: self.outputTextView.attributedText ?? NSAttributedString())
            mutable.append(attrStr)

            if mutable.length > 10000 {
                mutable.deleteCharacters(in: NSRange(location: 0, length: mutable.length - 8000))
            }

            self.outputTextView.attributedText = mutable

            if self.autoScroll && mutable.length > 0 {
                self.outputTextView.scrollRangeToVisible(NSRange(location: mutable.length - 1, length: 1))
            }
        }
    }

    // MARK: - Actions

    @objc private func sendTapped() {
        guard let text = inputField.text, !text.isEmpty else { return }
        sendInput(text + "\r")

        // Brief visual feedback
        UIView.animate(withDuration: 0.08) {
            self.sendButton.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        } completion: { _ in
            UIView.animate(withDuration: 0.08) {
                self.sendButton.transform = .identity
            }
        }

        inputField.text = ""
    }

    @objc private func quickActionTapped(_ sender: UIButton) {
        guard sender.tag < quickActions.count else { return }
        let (_, sequence) = quickActions[sender.tag]
        sendInput(sequence)

        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }

        let keyboardVisible = frame.origin.y < UIScreen.main.bounds.height
        let offset = keyboardVisible ? -(frame.height - view.safeAreaInsets.bottom) : 0

        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16)) {
            self.inputBarBottom.constant = offset
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Mock (DEBUG)

    private func injectMockOutput() {
        let mockText = """
        \u{1B}[32m❯\u{1B}[0m claude --model opus
        \u{1B}[36m╭─────────────────────────────────────────╮\u{1B}[0m
        \u{1B}[36m│\u{1B}[0m  Claude Code v1.0.23                    \u{1B}[36m│\u{1B}[0m
        \u{1B}[36m│\u{1B}[0m  /Users/four/Projects/vibing             \u{1B}[36m│\u{1B}[0m
        \u{1B}[36m╰─────────────────────────────────────────╯\u{1B}[0m

        \u{1B}[1m>\u{1B}[0m 添加用户登录和注册功能

        \u{1B}[33m⏳\u{1B}[0m Analyzing codebase...

        \u{1B}[32m✓\u{1B}[0m Read vibing-relay/src/main.rs (261 lines)
        \u{1B}[32m✓\u{1B}[0m Read vibing-relay/src/auth.rs (new file)
        \u{1B}[32m✓\u{1B}[0m Read vibing-relay/src/api.rs (new file)
        \u{1B}[32m✓\u{1B}[0m Read vibing-relay/src/db.rs (new file)
        \u{1B}[32m✓\u{1B}[0m Modified vibing-macos/Models/AccountManager.swift
        \u{1B}[32m✓\u{1B}[0m Modified vibing-macos/Views/SettingsView.swift

        \u{1B}[1mRelay Server Changes:\u{1B}[0m
          • Added SQLite database (users + devices tables)
          • JWT authentication with Argon2 password hashing
          • REST API: /auth/register, /auth/login, /devices
          • WebSocket token authentication required

        \u{1B}[1mmacOS Client Changes:\u{1B}[0m
          • AccountManager rewritten for relay API
          • Settings → Account section (login/register/devices)
          • Token stored in Keychain (not UserDefaults)

        \u{1B}[32m$ cargo build\u{1B}[0m
        Compiling vibe-relay v0.2.0
        \u{1B}[32m    Finished\u{1B}[0m dev [unoptimized + debuginfo] in 5.77s

        \u{1B}[32m$ swift build\u{1B}[0m
        Build complete! (9.04s)

        \u{1B}[32m❯\u{1B}[0m _
        """

        // 简单渲染：去掉 ANSI 转义，直接显示纯文本
        let clean = mockText.replacingOccurrences(
            of: "\\u{1B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )

        let attrs: [NSAttributedString.Key: Any] = [
            .font: VibingFont.mono(14),
            .foregroundColor: VibingColor.terminalFg
        ]
        outputTextView.attributedText = NSAttributedString(string: clean, attributes: attrs)
    }
}

// MARK: - UITextFieldDelegate

extension SessionDetailViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return false
    }
}
