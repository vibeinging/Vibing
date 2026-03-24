//
//  TerminalViewerController.swift
//  Vibing (iOS)
//
//  ⚡ OVERDRIVE — 沉浸式终端观察和控制器
//
//  设计语言：
//  - 全屏沉浸，顶部半透明融合
//  - 浮动毛玻璃输入栏
//  - Session 横滑手势切换 + 弹簧物理
//  - 下拉交互式面板
//  - 终端新内容逐行淡入
//

import UIKit
import Speech
import AVFoundation

class TerminalViewerController: UIViewController {

    private let serverURL: String
    private let sessionCode: String
    private weak var wsClient: WebSocketClient?

    private var sessions: [SessionInfo] = []
    private var selectedIndex: Int = 0
    private var sessionOutputs: [String: NSMutableAttributedString] = [:]
    private var autoScroll = true

    // MARK: - Colors

    private let bg = UIColor(red: 15/255, green: 15/255, blue: 16/255, alpha: 1)
    private let bgCard = UIColor(red: 24/255, green: 25/255, blue: 28/255, alpha: 1)
    private let fgPrimary = UIColor(red: 210/255, green: 210/255, blue: 205/255, alpha: 1)
    private let fgDim = UIColor.white.withAlphaComponent(0.35)
    private let accent = UIColor(red: 106/255, green: 194/255, blue: 120/255, alpha: 1)
    private let accentGlow = UIColor(red: 106/255, green: 194/255, blue: 120/255, alpha: 0.3)

    // MARK: - Top Bar

    private let topBarBg = UIView()
    private let handlePill = UIView()
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let tabScroll = UIScrollView()
    private let tabStack = UIStackView()
    private let tabIndicator = UIView()

    // MARK: - Terminal

    private let outputTextView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.showsHorizontalScrollIndicator = false
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.keyboardDismissMode = .interactive
        tv.contentInsetAdjustmentBehavior = .never
        return tv
    }()

    // MARK: - Input Bar

    private let inputBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let inputField = UITextField()
    private let micButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let quickScroll = UIScrollView()
    private let quickStack = UIStackView()
    private let smartInsertScroll = UIScrollView()
    private let smartInsertStack = UIStackView()
    private var inputBarBottom: NSLayoutConstraint!

    // MARK: - File Browser & Command Palette

    private var fileBrowserDimmer: UIView?
    private var fileBrowserContainer: UIView?
    private var fileBrowserTable: UITableView?
    private var fileBrowserEntries: [[String: Any]] = []
    private var fileBrowserPath: String = "."
    private weak var fileBrowserPathLabel: UILabel?
    private var isRecording = false
    private let speechRecognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Smart Prompt Bar (Claude Code 交互优化)

    private let promptBar = UIView()
    private let promptLabel = UILabel()
    private let promptStack = UIStackView()
    private var promptBarBottom: NSLayoutConstraint!
    private var currentPromptType: PromptType = .none

    enum PromptType {
        case none
        case yesNo(String)      // y/n 确认
        case approve            // tool approval
        case waitingInput       // 等待自由输入
        case running            // 正在执行中
    }

    // MARK: - Pull-down Panel

    private let panelDimmer = UIView()
    private let panelContainer = UIView()
    private var panelTop: NSLayoutConstraint!
    private var isPanelOpen = false
    private var panelAnimator: UIViewPropertyAnimator?

    // MARK: - Gesture

    private var swipeStartX: CGFloat = 0

    private let quickActions: [(String, String)] = [
        ("⌃C", "\u{03}"), ("⌃D", "\u{04}"), ("⌃Z", "\u{1A}"),
        ("⌃L", "\u{0C}"), ("Tab", "\t"), ("↑", "\u{1B}[A"),
        ("↓", "\u{1B}[B"), ("Esc", "\u{1B}"),
    ]

    // MARK: - Init

    init(serverURL: String, sessionCode: String, sessions: [SessionInfo] = []) {
        self.serverURL = serverURL
        self.sessionCode = sessionCode
        self.sessions = sessions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        view.backgroundColor = bg

        buildTerminalView()
        buildTopBar()
        buildInputBar()
        buildPromptBar()
        buildPanel()
        setupGestures()
        setupKeyboard()

        if sessions.isEmpty && sessionCode == "mock" {
            injectMockSessions()
        }

        refreshTabs()

        if let first = sessions.first {
            selectSession(at: 0, animated: false)
            if sessionCode == "mock" { injectMockOutput(for: first.id) }
        }

        // Hook into text messages for dir_listing responses (chain with existing handler)
        let existingHandler = wsClient?.onTextMessage
        wsClient?.onTextMessage = { [weak self] text in
            // Forward to existing handler first
            existingHandler?(text)
            // Then handle our messages
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { return }
            if type == "dir_listing" {
                self?.handleDirListing(json)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update terminal insets for top bar + input bar
        let topInset = topBarBg.frame.maxY
        let bottomInset = view.frame.height - inputBlur.frame.minY + 8
        outputTextView.contentInset = UIEdgeInsets(top: topInset + 4, left: 0, bottom: bottomInset, right: 0)
        outputTextView.scrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: true)
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - BUILD: Terminal
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func buildTerminalView() {
        outputTextView.backgroundColor = bg
        outputTextView.textColor = fgPrimary
        outputTextView.font = VibingFont.mono(13)
        outputTextView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        outputTextView.indicatorStyle = .white
        view.addSubview(outputTextView)

        NSLayoutConstraint.activate([
            outputTextView.topAnchor.constraint(equalTo: view.topAnchor),
            outputTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outputTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outputTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - BUILD: Top Bar (frosted)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func buildTopBar() {
        topBarBg.backgroundColor = bgCard.withAlphaComponent(0.95)
        topBarBg.translatesAutoresizingMaskIntoConstraints = false
        topBarBg.clipsToBounds = false
        view.addSubview(topBarBg)

        // topBarBg.layer.borderWidth = 2; topBarBg.layer.borderColor = UIColor.red.cgColor

        // Pill handle
        handlePill.backgroundColor = .white.withAlphaComponent(0.25)
        handlePill.layer.cornerRadius = 2.5
        handlePill.translatesAutoresizingMaskIntoConstraints = false
        topBarBg.addSubview(handlePill)

        // Back
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)), for: .normal)
        backButton.tintColor = .white.withAlphaComponent(0.6)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        topBarBg.addSubview(backButton)

        // Status
        statusDot.backgroundColor = accent
        statusDot.layer.cornerRadius = 3.5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        addPulseAnimation(to: statusDot)

        statusLabel.text = L("sessions.connected")
        statusLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        statusLabel.textColor = .white.withAlphaComponent(0.4)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusRow = UIStackView(arrangedSubviews: [statusDot, statusLabel])
        statusRow.spacing = 5
        statusRow.alignment = .center
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        topBarBg.addSubview(statusRow)

        // Tabs
        tabScroll.showsHorizontalScrollIndicator = false
        tabScroll.translatesAutoresizingMaskIntoConstraints = false
        topBarBg.addSubview(tabScroll)

        tabStack.axis = .horizontal
        tabStack.spacing = 2
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabScroll.addSubview(tabStack)

        // Indicator
        tabIndicator.backgroundColor = accent
        tabIndicator.layer.cornerRadius = 1.5
        tabIndicator.layer.shadowColor = accent.cgColor
        tabIndicator.layer.shadowRadius = 6
        tabIndicator.layer.shadowOpacity = 0.5
        tabIndicator.layer.shadowOffset = .zero
        view.addSubview(tabIndicator)

        // 一行布局：[< back] [tabs scroll...] [● status]
        view.addSubview(backButton)
        view.addSubview(tabScroll)
        view.addSubview(statusDot)
        view.addSubview(statusLabel)

        // handlePill 在 tab 栏下方
        view.addSubview(handlePill)

        NSLayoutConstraint.activate([
            topBarBg.topAnchor.constraint(equalTo: view.topAnchor),
            topBarBg.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBarBg.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // 返回按钮 — safe area 顶部紧贴
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 36),
            backButton.heightAnchor.constraint(equalToConstant: 36),

            // Tab 标签 — 和返回按钮同一行
            tabScroll.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 0),
            tabScroll.trailingAnchor.constraint(equalTo: statusDot.leadingAnchor, constant: -8),
            tabScroll.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            tabScroll.heightAnchor.constraint(equalToConstant: 34),

            tabStack.topAnchor.constraint(equalTo: tabScroll.topAnchor),
            tabStack.leadingAnchor.constraint(equalTo: tabScroll.leadingAnchor, constant: 4),
            tabStack.trailingAnchor.constraint(equalTo: tabScroll.trailingAnchor, constant: -4),
            tabStack.bottomAnchor.constraint(equalTo: tabScroll.bottomAnchor),
            tabStack.heightAnchor.constraint(equalTo: tabScroll.heightAnchor),

            // 状态点 — 右侧
            statusDot.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusDot.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),

            // Handle pill — tab 栏下方
            handlePill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handlePill.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 2),
            handlePill.widthAnchor.constraint(equalToConstant: 36),
            handlePill.heightAnchor.constraint(equalToConstant: 4),

            // topBarBg 底部
            topBarBg.bottomAnchor.constraint(equalTo: handlePill.bottomAnchor, constant: 4),
        ])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - BUILD: Input Bar (floating glass)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func buildInputBar() {
        inputBlur.layer.cornerRadius = 22
        inputBlur.layer.cornerCurve = .continuous
        inputBlur.clipsToBounds = true
        inputBlur.translatesAutoresizingMaskIntoConstraints = false

        inputBlur.layer.borderWidth = 0.5
        inputBlur.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor

        view.addSubview(inputBlur)

        // ── Row 1: Smart insert buttons (@, /, !, ~) ──
        smartInsertScroll.showsHorizontalScrollIndicator = false
        smartInsertScroll.translatesAutoresizingMaskIntoConstraints = false
        smartInsertStack.axis = .horizontal
        smartInsertStack.spacing = 6
        smartInsertStack.translatesAutoresizingMaskIntoConstraints = false
        smartInsertScroll.addSubview(smartInsertStack)

        let smartItems: [(String, String, Selector)] = [
            ("@", "doc.text", #selector(smartAtTapped)),
            ("/", "command", #selector(smartSlashTapped)),
            ("!", "exclamationmark.triangle", #selector(smartBangTapped)),
            ("~", "house", #selector(smartTildeTapped)),
        ]

        for (title, icon, action) in smartItems {
            let btn = UIButton(type: .system)
            let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            let img = UIImage(systemName: icon, withConfiguration: config)
            btn.setImage(img, for: .normal)
            btn.setTitle(" " + title, for: .normal)
            btn.titleLabel?.font = VibingFont.mono(12, weight: .bold)
            btn.setTitleColor(accent, for: .normal)
            btn.tintColor = accent
            btn.backgroundColor = accent.withAlphaComponent(0.12)
            btn.layer.cornerRadius = 7
            btn.layer.cornerCurve = .continuous
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            btn.addTarget(self, action: action, for: .touchUpInside)
            smartInsertStack.addArrangedSubview(btn)
        }

        // ── Row 2: Quick actions (⌃C, ⌃D, etc.) ──
        quickScroll.showsHorizontalScrollIndicator = false
        quickScroll.translatesAutoresizingMaskIntoConstraints = false
        quickStack.axis = .horizontal
        quickStack.spacing = 5
        quickStack.translatesAutoresizingMaskIntoConstraints = false
        quickScroll.addSubview(quickStack)

        for (i, (label, _)) in quickActions.enumerated() {
            let btn = makeQuickButton(title: label, tag: i)
            quickStack.addArrangedSubview(btn)
        }

        // ── Row 3: Input field + send ──
        inputField.font = VibingFont.mono(14)
        inputField.textColor = .white
        inputField.backgroundColor = .white.withAlphaComponent(0.12)
        inputField.layer.cornerRadius = 14
        inputField.layer.cornerCurve = .continuous
        inputField.autocapitalizationType = .none
        inputField.autocorrectionType = .no
        inputField.spellCheckingType = .no
        inputField.returnKeyType = .send
        inputField.keyboardAppearance = .dark
        inputField.delegate = self
        inputField.attributedPlaceholder = NSAttributedString(
            string: "$ command...",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.4), .font: VibingFont.mono(14)]
        )
        inputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        inputField.leftViewMode = .always
        inputField.translatesAutoresizingMaskIntoConstraints = false

        let micConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        micButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: micConfig), for: .normal)
        micButton.tintColor = .white.withAlphaComponent(0.4)
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micButton.translatesAutoresizingMaskIntoConstraints = false

        let sendConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: sendConfig), for: .normal)
        sendButton.tintColor = accent
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        inputBlur.contentView.addSubview(smartInsertScroll)
        inputBlur.contentView.addSubview(quickScroll)
        inputBlur.contentView.addSubview(inputField)
        inputBlur.contentView.addSubview(micButton)
        inputBlur.contentView.addSubview(sendButton)

        inputBarBottom = inputBlur.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6)

        NSLayoutConstraint.activate([
            inputBlur.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            inputBlur.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            inputBarBottom,

            // Smart insert row (top)
            smartInsertScroll.topAnchor.constraint(equalTo: inputBlur.contentView.topAnchor, constant: 8),
            smartInsertScroll.leadingAnchor.constraint(equalTo: inputBlur.contentView.leadingAnchor),
            smartInsertScroll.trailingAnchor.constraint(equalTo: inputBlur.contentView.trailingAnchor),
            smartInsertScroll.heightAnchor.constraint(equalToConstant: 28),

            smartInsertStack.topAnchor.constraint(equalTo: smartInsertScroll.topAnchor),
            smartInsertStack.leadingAnchor.constraint(equalTo: smartInsertScroll.leadingAnchor, constant: 12),
            smartInsertStack.trailingAnchor.constraint(equalTo: smartInsertScroll.trailingAnchor, constant: -12),
            smartInsertStack.bottomAnchor.constraint(equalTo: smartInsertScroll.bottomAnchor),
            smartInsertStack.heightAnchor.constraint(equalTo: smartInsertScroll.heightAnchor),

            // Quick actions row
            quickScroll.topAnchor.constraint(equalTo: smartInsertScroll.bottomAnchor, constant: 5),
            quickScroll.leadingAnchor.constraint(equalTo: inputBlur.contentView.leadingAnchor),
            quickScroll.trailingAnchor.constraint(equalTo: inputBlur.contentView.trailingAnchor),
            quickScroll.heightAnchor.constraint(equalToConstant: 30),

            quickStack.topAnchor.constraint(equalTo: quickScroll.topAnchor),
            quickStack.leadingAnchor.constraint(equalTo: quickScroll.leadingAnchor, constant: 12),
            quickStack.trailingAnchor.constraint(equalTo: quickScroll.trailingAnchor, constant: -12),
            quickStack.bottomAnchor.constraint(equalTo: quickScroll.bottomAnchor),
            quickStack.heightAnchor.constraint(equalTo: quickScroll.heightAnchor),

            // Input field row
            inputField.topAnchor.constraint(equalTo: quickScroll.bottomAnchor, constant: 6),
            inputField.leadingAnchor.constraint(equalTo: inputBlur.contentView.leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: micButton.leadingAnchor, constant: -4),
            inputField.bottomAnchor.constraint(equalTo: inputBlur.contentView.bottomAnchor, constant: -10),
            inputField.heightAnchor.constraint(equalToConstant: 40),

            micButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 32),

            sendButton.leadingAnchor.constraint(equalTo: micButton.trailingAnchor, constant: 2),
            sendButton.trailingAnchor.constraint(equalTo: inputBlur.contentView.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func makeQuickButton(title: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = VibingFont.mono(11, weight: .semibold)
        btn.setTitleColor(.white.withAlphaComponent(0.65), for: .normal)
        btn.backgroundColor = .white.withAlphaComponent(0.1)
        btn.layer.cornerRadius = 7
        btn.layer.cornerCurve = .continuous
        btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 11, bottom: 5, right: 11)
        btn.tag = tag
        btn.addTarget(self, action: #selector(quickActionTapped(_:)), for: .touchUpInside)
        return btn
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - BUILD: Smart Prompt Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func buildPromptBar() {
        promptBar.backgroundColor = UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 0.97)
        promptBar.layer.cornerRadius = 16
        promptBar.layer.cornerCurve = .continuous
        promptBar.layer.borderWidth = 0.5
        promptBar.layer.borderColor = accent.withAlphaComponent(0.3).cgColor
        promptBar.clipsToBounds = true
        promptBar.translatesAutoresizingMaskIntoConstraints = false
        promptBar.alpha = 0
        promptBar.transform = CGAffineTransform(translationX: 0, y: 10)
        view.addSubview(promptBar)

        // Left indicator line
        let indicator = UIView()
        indicator.backgroundColor = accent
        indicator.layer.cornerRadius = 1.5
        indicator.translatesAutoresizingMaskIntoConstraints = false
        promptBar.addSubview(indicator)

        promptLabel.font = .systemFont(ofSize: 12, weight: .medium)
        promptLabel.textColor = .white.withAlphaComponent(0.5)
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptBar.addSubview(promptLabel)

        promptStack.axis = .horizontal
        promptStack.spacing = 8
        promptStack.translatesAutoresizingMaskIntoConstraints = false
        promptBar.addSubview(promptStack)

        promptBarBottom = promptBar.bottomAnchor.constraint(equalTo: inputBlur.topAnchor, constant: -8)

        NSLayoutConstraint.activate([
            promptBarBottom,
            promptBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            promptBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            indicator.leadingAnchor.constraint(equalTo: promptBar.leadingAnchor, constant: 12),
            indicator.centerYAnchor.constraint(equalTo: promptBar.centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 3),
            indicator.heightAnchor.constraint(equalToConstant: 20),

            promptLabel.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 10),
            promptLabel.centerYAnchor.constraint(equalTo: promptBar.centerYAnchor),

            promptStack.trailingAnchor.constraint(equalTo: promptBar.trailingAnchor, constant: -12),
            promptStack.centerYAnchor.constraint(equalTo: promptBar.centerYAnchor),
            promptStack.leadingAnchor.constraint(greaterThanOrEqualTo: promptLabel.trailingAnchor, constant: 8),

            promptBar.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func updatePromptBar(type: PromptType) {
        guard !isPromptEqual(currentPromptType, type) else { return }
        currentPromptType = type

        // Clear old buttons
        promptStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch type {
        case .none:
            hidePromptBar()
            return

        case .yesNo(let question):
            promptLabel.text = question.isEmpty ? "Confirm?" : String(question.prefix(30))
            addPromptButton("Yes", color: accent, input: "y\n")
            addPromptButton("No", color: .systemRed.withAlphaComponent(0.8), input: "n\n")
            addPromptButton("⌃C", color: .white.withAlphaComponent(0.15), input: "\u{03}", textColor: .white.withAlphaComponent(0.5))

        case .approve:
            promptLabel.text = "Tool approval"
            addPromptButton("Allow", color: accent, input: "y\n")
            addPromptButton("Deny", color: .systemRed.withAlphaComponent(0.8), input: "n\n")
            addPromptButton("Always", color: accent.withAlphaComponent(0.5), input: "a\n")

        case .waitingInput:
            promptLabel.text = "Waiting for input"
            addPromptButton("⌃C Cancel", color: .white.withAlphaComponent(0.15), input: "\u{03}", textColor: .white.withAlphaComponent(0.6))

        case .running:
            promptLabel.text = "Running..."
            addPromptButton("⌃C Stop", color: .systemRed.withAlphaComponent(0.6), input: "\u{03}", textColor: .white)
        }

        showPromptBar()
    }

    private func addPromptButton(_ title: String, color: UIColor, input: String, textColor: UIColor = .white) {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.setTitleColor(textColor, for: .normal)
        btn.backgroundColor = color
        btn.layer.cornerRadius = 10
        btn.layer.cornerCurve = .continuous
        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)

        btn.addAction(UIAction { [weak self] _ in
            guard let self = self, self.selectedIndex < self.sessions.count else { return }
            let sid = self.sessions[self.selectedIndex].id
            self.wsClient?.sendTextInput(sessionId: sid, text: input)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // Flash feedback
            UIView.animate(withDuration: 0.08, animations: {
                btn.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            }) { _ in
                UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8, options: []) {
                    btn.transform = .identity
                }
            }
        }, for: .touchUpInside)

        promptStack.addArrangedSubview(btn)
    }

    private func showPromptBar() {
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5, options: .curveEaseOut) {
            self.promptBar.alpha = 1
            self.promptBar.transform = .identity
        }
    }

    private func hidePromptBar() {
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
            self.promptBar.alpha = 0
            self.promptBar.transform = CGAffineTransform(translationX: 0, y: 10)
        }
    }

    private func isPromptEqual(_ a: PromptType, _ b: PromptType) -> Bool {
        switch (a, b) {
        case (.none, .none), (.approve, .approve), (.waitingInput, .waitingInput), (.running, .running): return true
        case (.yesNo(let x), .yesNo(let y)): return x == y
        default: return false
        }
    }

    /// 分析终端输出末尾，检测 Claude Code 等工具的交互提示
    private func detectPrompt(in text: String) {
        let tail = String(text.suffix(500)).lowercased()

        // Claude Code y/n 确认
        if tail.contains("(y/n)") || tail.contains("[y/n]") || tail.contains("? (y)es/(n)o") {
            let lines = text.components(separatedBy: "\n")
            let promptLine = lines.last(where: { $0.lowercased().contains("y/n") || $0.lowercased().contains("yes") && $0.lowercased().contains("no") }) ?? ""
            updatePromptBar(type: .yesNo(promptLine.trimmingCharacters(in: .whitespaces)))
            return
        }

        // Tool approval
        if tail.contains("allow") && tail.contains("deny") {
            updatePromptBar(type: .approve)
            return
        }

        // Claude Code waiting for user prompt (shows > or ❯ at end)
        if tail.hasSuffix("> ") || tail.hasSuffix("❯ ") || tail.hasSuffix("> _") || tail.hasSuffix("❯ _") {
            updatePromptBar(type: .waitingInput)
            return
        }

        // Running (spinner or progress indicator)
        if tail.contains("⏳") || tail.contains("analyzing") || tail.contains("thinking") || tail.contains("reading") || tail.contains("writing") {
            updatePromptBar(type: .running)
            return
        }

        // Default: hide
        updatePromptBar(type: .none)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - BUILD: Pull-down Panel
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func buildPanel() {
        panelDimmer.backgroundColor = .black
        panelDimmer.alpha = 0
        panelDimmer.translatesAutoresizingMaskIntoConstraints = false
        panelDimmer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closePanel)))
        view.insertSubview(panelDimmer, belowSubview: inputBlur)

        panelContainer.backgroundColor = UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 0.97)
        panelContainer.layer.cornerRadius = 24
        panelContainer.layer.cornerCurve = .continuous
        panelContainer.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        panelContainer.layer.shadowColor = UIColor.black.cgColor
        panelContainer.layer.shadowOpacity = 0.5
        panelContainer.layer.shadowRadius = 30
        panelContainer.layer.shadowOffset = CGSize(width: 0, height: 10)
        panelContainer.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(panelContainer, belowSubview: inputBlur)

        let panelHeight: CGFloat = 320
        panelTop = panelContainer.topAnchor.constraint(equalTo: topBarBg.bottomAnchor, constant: -panelHeight)

        NSLayoutConstraint.activate([
            panelDimmer.topAnchor.constraint(equalTo: view.topAnchor),
            panelDimmer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panelDimmer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panelDimmer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panelTop,
            panelContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panelContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panelContainer.heightAnchor.constraint(equalToConstant: panelHeight),
        ])

        rebuildPanelContent()
    }

    private func rebuildPanelContent() {
        panelContainer.subviews.forEach { $0.removeFromSuperview() }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panelContainer.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor, constant: -16),
        ])

        // Section title
        let title = UILabel()
        title.text = L("sessions.terminalSessions").uppercased()
        title.font = .systemFont(ofSize: 11, weight: .bold)
        title.textColor = .white.withAlphaComponent(0.3)
        title.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(10, after: title)

        for (i, session) in sessions.enumerated() {
            let row = buildPanelRow(index: i, session: session)
            stack.addArrangedSubview(row)
        }
    }

    private func buildPanelRow(index: Int, session: SessionInfo) -> UIView {
        let isSelected = index == selectedIndex
        let btn = UIButton(type: .system)
        btn.backgroundColor = isSelected ? accent.withAlphaComponent(0.12) : .clear
        btn.layer.cornerRadius = 12
        btn.layer.cornerCurve = .continuous
        btn.tag = index
        btn.addTarget(self, action: #selector(panelRowTapped(_:)), for: .touchUpInside)

        let icon = UIImageView(image: UIImage(systemName: "terminal.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)))
        icon.tintColor = isSelected ? accent : .white.withAlphaComponent(0.3)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let name = UILabel()
        name.text = String(format: L("sessions.sessionNumber"), index + 1)
        name.font = .systemFont(ofSize: 15, weight: isSelected ? .semibold : .regular)
        name.textColor = isSelected ? .white : .white.withAlphaComponent(0.55)

        let sid = UILabel()
        sid.text = String(session.id.prefix(12))
        sid.font = VibingFont.mono(10)
        sid.textColor = .white.withAlphaComponent(0.2)

        let dot = UIView()
        dot.backgroundColor = session.isActive ? accent : .gray.withAlphaComponent(0.4)
        dot.layer.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [name, sid])
        textStack.axis = .vertical
        textStack.spacing = 1

        let spacer = UIView()
        let mainStack = UIStackView(arrangedSubviews: [icon, textStack, spacer, dot])
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.alignment = .center
        mainStack.isUserInteractionEnabled = false
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        btn.addSubview(mainStack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 22),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            mainStack.topAnchor.constraint(equalTo: btn.topAnchor, constant: 11),
            mainStack.leadingAnchor.constraint(equalTo: btn.leadingAnchor, constant: 14),
            mainStack.trailingAnchor.constraint(equalTo: btn.trailingAnchor, constant: -14),
            mainStack.bottomAnchor.constraint(equalTo: btn.bottomAnchor, constant: -11),
        ])

        return btn
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Tab Management
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func refreshTabs() {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (i, _) in sessions.enumerated() {
            let btn = UIButton(type: .system)
            let title = String(format: L("sessions.sessionNumber"), i + 1)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: i == selectedIndex ? .bold : .medium)
            btn.setTitleColor(i == selectedIndex ? .white : .white.withAlphaComponent(0.35), for: .normal)
            btn.backgroundColor = i == selectedIndex ? .white.withAlphaComponent(0.08) : .clear
            btn.layer.cornerRadius = 8
            btn.layer.cornerCurve = .continuous
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
            btn.tag = i
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabStack.addArrangedSubview(btn)
        }

        // Defer indicator update to next layout pass
        DispatchQueue.main.async { self.updateIndicator(animated: false) }
    }

    private func updateIndicator(animated: Bool) {
        guard selectedIndex < tabStack.arrangedSubviews.count else {
            tabIndicator.frame = .zero
            return
        }
        let tab = tabStack.arrangedSubviews[selectedIndex]
        let f = tab.convert(tab.bounds, to: view)
        let target = CGRect(x: f.minX + 6, y: f.maxY + 1, width: f.width - 12, height: 3)

        if animated {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut) {
                self.tabIndicator.frame = target
            }
        } else {
            tabIndicator.frame = target
        }
    }

    private func selectSession(at index: Int, animated: Bool = true) {
        guard index >= 0, index < sessions.count else { return }
        selectedIndex = index
        let sid = sessions[index].id

        // Output
        if let cached = sessionOutputs[sid] {
            outputTextView.attributedText = cached
        } else {
            outputTextView.attributedText = nil
        }

        refreshTabs()
        rebuildPanelContent()

        if animated, autoScroll, let buf = sessionOutputs[sid], buf.length > 0 {
            outputTextView.scrollRangeToVisible(NSRange(location: buf.length - 1, length: 1))
        }

        // Subscribe
        wsClient?.sendTextMessage(["type": "subscribe", "session_ids": [sid]])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Gestures
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func setupGestures() {
        // Pull-down on handle
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanelPan(_:)))
        topBarBg.addGestureRecognizer(pan)

        let handleTap = UITapGestureRecognizer(target: self, action: #selector(togglePanel))
        handlePill.isUserInteractionEnabled = true
        handlePill.addGestureRecognizer(handleTap)

        // Swipe between sessions
        let swipe = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipe.delegate = self
        outputTextView.addGestureRecognizer(swipe)

        // Dismiss keyboard
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        outputTextView.addGestureRecognizer(tap)
    }

    @objc private func handleSwipe(_ gesture: UIPanGestureRecognizer) {
        let tx = gesture.translation(in: view).x
        let vx = gesture.velocity(in: view).x

        switch gesture.state {
        case .began:
            swipeStartX = 0
        case .ended:
            if tx < -60 || vx < -500 {
                // Swipe left → next
                if selectedIndex < sessions.count - 1 {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    selectSession(at: selectedIndex + 1)
                }
            } else if tx > 60 || vx > 500 {
                // Swipe right → previous
                if selectedIndex > 0 {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    selectSession(at: selectedIndex - 1)
                }
            }
        default: break
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Panel Animation (interactive spring)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @objc private func togglePanel() {
        isPanelOpen ? closePanel() : openPanel()
    }

    @objc private func openPanel() {
        isPanelOpen = true
        rebuildPanelContent()
        animatePanel(open: true)
    }

    @objc private func closePanel() {
        isPanelOpen = false
        animatePanel(open: false)
    }

    private func animatePanel(open: Bool) {
        panelAnimator?.stopAnimation(true)

        let animator = UIViewPropertyAnimator(duration: 0.55, dampingRatio: 0.78) {
            self.panelTop.constant = open ? 0 : -320
            self.panelDimmer.alpha = open ? 0.5 : 0
            self.view.layoutIfNeeded()
        }
        animator.startAnimation()
        panelAnimator = animator
    }

    @objc private func handlePanelPan(_ gesture: UIPanGestureRecognizer) {
        let ty = gesture.translation(in: view).y
        let vy = gesture.velocity(in: view).y

        switch gesture.state {
        case .changed:
            if !isPanelOpen && ty > 0 {
                let clamped = min(ty, 320)
                panelTop.constant = -320 + clamped
                panelDimmer.alpha = clamped / 640
            } else if isPanelOpen && ty < 0 {
                panelTop.constant = max(ty, -320)
                panelDimmer.alpha = max(0, 0.5 + ty / 640)
            }
        case .ended:
            if !isPanelOpen && (ty > 120 || vy > 600) {
                openPanel()
            } else if isPanelOpen && (ty < -80 || vy < -400) {
                closePanel()
            } else {
                animatePanel(open: isPanelOpen)
            }
        default: break
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func tabTapped(_ sender: UIButton) {
        guard sender.tag != selectedIndex else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectSession(at: sender.tag)
    }

    @objc private func panelRowTapped(_ sender: UIButton) {
        selectSession(at: sender.tag)
        closePanel()
    }

    @objc private func sendTapped() {
        guard let text = inputField.text, !text.isEmpty, selectedIndex < sessions.count else { return }
        let sid = sessions[selectedIndex].id
        wsClient?.sendTextInput(sessionId: sid, text: text + "\r")

        // Spring bounce
        UIView.animate(withDuration: 0.08, animations: {
            self.sendButton.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.9, options: []) {
                self.sendButton.transform = .identity
            }
        }

        inputField.text = ""
    }

    @objc private func micTapped() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self, status == .authorized else { return }
                self.performRecording()
            }
        }
    }

    private func performRecording() {
        // Stop any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest, let speechRecognizer = speechRecognizer else { return }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.inputField.text = result.bestTranscription.formattedString
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do { try audioEngine.start() } catch { return }

        isRecording = true
        updateMicButton()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false
        updateMicButton()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateMicButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        if isRecording {
            micButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: config), for: .normal)
            micButton.tintColor = .systemRed

            // Pulsing animation
            UIView.animate(withDuration: 0.6, delay: 0, options: [.repeat, .autoreverse, .allowUserInteraction]) {
                self.micButton.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            }
        } else {
            micButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: config), for: .normal)
            micButton.tintColor = .white.withAlphaComponent(0.4)
            micButton.layer.removeAllAnimations()
            micButton.transform = .identity
        }
    }

    @objc private func quickActionTapped(_ sender: UIButton) {
        guard sender.tag < quickActions.count, selectedIndex < sessions.count else { return }
        let sid = sessions[selectedIndex].id
        wsClient?.sendTextInput(sessionId: sid, text: quickActions[sender.tag].1)

        // Subtle flash
        UIView.animate(withDuration: 0.05, animations: {
            sender.backgroundColor = self.accent.withAlphaComponent(0.25)
            sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }) { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) {
                sender.backgroundColor = .white.withAlphaComponent(0.1)
                sender.transform = .identity
            }
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Smart Insert Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @ — 打开文件选择器
    @objc private func smartAtTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showFileBrowser(path: ".")
    }

    /// / — 打开命令选择器
    @objc private func smartSlashTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showCommandPalette()
    }

    /// ! — 插入 ! 到输入框
    @objc private func smartBangTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        insertTextToInput("! ")
    }

    /// ~ — 插入 ~ 到输入框
    @objc private func smartTildeTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        insertTextToInput("~/")
    }

    private func insertTextToInput(_ text: String) {
        let current = inputField.text ?? ""
        inputField.text = current + text
        inputField.becomeFirstResponder()
    }

    // MARK: - Command Palette

    private func showCommandPalette() {
        let commands: [(String, String, String)] = [
            ("/help", "帮助", "questionmark.circle"),
            ("/clear", "清屏", "trash"),
            ("/compact", "压缩上下文", "arrow.down.right.and.arrow.up.left"),
            ("/commit", "提交代码", "checkmark.circle"),
            ("/review", "代码审查", "eye"),
            ("/init", "初始化项目", "folder.badge.plus"),
            ("/bug", "报告问题", "ladybug"),
            ("/config", "配置", "gearshape"),
        ]

        let alert = UIAlertController(title: "Commands", message: nil, preferredStyle: .actionSheet)

        for (cmd, desc, _) in commands {
            alert.addAction(UIAlertAction(title: "\(cmd)  —  \(desc)", style: .default) { [weak self] _ in
                self?.insertTextToInput(cmd + " ")
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 200, width: 0, height: 0)
        }

        present(alert, animated: true)
    }

    // MARK: - File Browser

    private func showFileBrowser(path: String) {
        fileBrowserPath = path

        // Request directory listing from server
        wsClient?.sendTextMessage([
            "type": "list_dir",
            "path": path,
        ])

        // Build UI if not exists
        if fileBrowserDimmer == nil {
            buildFileBrowserUI()
        }

        // Show with animation
        fileBrowserDimmer?.isHidden = false
        fileBrowserContainer?.transform = CGAffineTransform(translationX: 0, y: 400)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.fileBrowserDimmer?.alpha = 1
            self.fileBrowserContainer?.transform = .identity
        }
    }

    private func buildFileBrowserUI() {
        // Dimmer
        let dimmer = UIView()
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        dimmer.alpha = 0
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissFileBrowser))
        dimmer.addGestureRecognizer(tap)
        view.addSubview(dimmer)
        fileBrowserDimmer = dimmer

        // Container
        let container = UIView()
        container.backgroundColor = UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)
        container.layer.cornerRadius = 20
        container.layer.cornerCurve = .continuous
        container.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        fileBrowserContainer = container

        // Header
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let titleLabel = UILabel()
        titleLabel.text = "Select File"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeBtn.tintColor = .white.withAlphaComponent(0.4)
        closeBtn.addTarget(self, action: #selector(dismissFileBrowser), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(closeBtn)

        // Path label
        let pathLabel = UILabel()
        pathLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pathLabel.textColor = .white.withAlphaComponent(0.4)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(pathLabel)
        fileBrowserPathLabel = pathLabel

        // Table
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorColor = .white.withAlphaComponent(0.06)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FileCell")
        table.delegate = self
        table.dataSource = self
        table.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(table)
        fileBrowserTable = table

        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: view.topAnchor),
            dimmer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.55),

            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 60),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),

            closeBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            closeBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            pathLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            table.topAnchor.constraint(equalTo: header.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    @objc private func dismissFileBrowser() {
        UIView.animate(withDuration: 0.25, animations: {
            self.fileBrowserDimmer?.alpha = 0
            self.fileBrowserContainer?.transform = CGAffineTransform(translationX: 0, y: 400)
        }) { _ in
            self.fileBrowserDimmer?.isHidden = true
        }
    }

    /// Called when server responds with dir_listing
    private func handleDirListing(_ data: [String: Any]) {
        guard let path = data["path"] as? String,
              let entries = data["entries"] as? [[String: Any]] else { return }

        DispatchQueue.main.async {
            self.fileBrowserPath = path
            self.fileBrowserEntries = entries

            self.fileBrowserPathLabel?.text = path

            self.fileBrowserTable?.reloadData()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Keyboard
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func setupKeyboard() {
        NotificationCenter.default.addObserver(self, selector: #selector(kbWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    @objc private func kbWillChange(_ n: Notification) {
        guard let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let dur = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = n.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }

        let vis = frame.origin.y < UIScreen.main.bounds.height
        let offset: CGFloat = vis ? -(frame.height - view.safeAreaInsets.bottom) - 6 : -6

        UIView.animate(withDuration: dur, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16)) {
            self.inputBarBottom.constant = offset
            self.view.layoutIfNeeded()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Output
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func appendOutput(sessionId: String, text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: VibingFont.mono(13),
            .foregroundColor: fgPrimary
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)

        if sessionOutputs[sessionId] == nil {
            sessionOutputs[sessionId] = NSMutableAttributedString()
        }
        let buf = sessionOutputs[sessionId]!
        buf.append(attrStr)

        if buf.length > 15000 {
            buf.deleteCharacters(in: NSRange(location: 0, length: buf.length - 10000))
        }

        if sessions[safe: selectedIndex]?.id == sessionId {
            outputTextView.attributedText = buf
            if autoScroll && buf.length > 0 {
                outputTextView.scrollRangeToVisible(NSRange(location: buf.length - 1, length: 1))
            }

            // 检测交互提示
            detectPrompt(in: buf.string)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Animations
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func addPulseAnimation(to view: UIView) {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 1.5
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(pulse, forKey: "pulse")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Mock Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func injectMockSessions() {
        sessions = [
            SessionInfo(id: "sess_claude_code", isActive: true),
            SessionInfo(id: "sess_dev_server", isActive: true),
            SessionInfo(id: "sess_git_log", isActive: true),
        ]
    }

    private func injectMockOutput(for sessionId: String) {
        let outputs: [String: String] = [
            "sess_claude_code": """
            ❯ claude --model opus

            ╭─────────────────────────────────────────╮
            │  Claude Code v1.0.23                     │
            │  /Users/four/Projects/vibing              │
            ╰─────────────────────────────────────────╯

            > 添加用户登录和注册功能

            ⏳ Analyzing codebase...

            ✓ Read vibing-relay/src/main.rs (261 lines)
            ✓ Read vibing-relay/src/auth.rs (new file)
            ✓ Created vibing-relay/src/db.rs
            ✓ Modified AccountManager.swift
            ✓ Modified SettingsView.swift

            Relay Server Changes:
              • SQLite database (users + devices)
              • JWT + Argon2 password hashing
              • REST API: /auth/register, /auth/login
              • WebSocket token authentication

            $ cargo build
                Compiling vibe-relay v0.2.0
                Finished dev in 5.77s

            $ swift build
            Build complete! (9.04s)

            Do you want to apply these changes to 6 files? (y/n)
            """,
            "sess_dev_server": """
            ❯ cargo run -- --bind 127.0.0.1:8765

            🔧 Vibe Terminal Server v0.3.0
            📡 Listening on: 127.0.0.1:8765
            🐚 Default shell: /usr/local/bin/fish
            ✅ Server ready

            [16:30:12] Client connected: 192.168.1.5
            [16:30:12] Session created: sess_a1b2 (fish)
            [16:30:15] Session created: sess_e5f6 (fish)
            [16:32:01] Client subscribed to 2 sessions
            [16:35:44] Output: 847 bytes → sess_a1b2
            [16:35:44] Output: 234 bytes → sess_e5f6
            [16:38:22] Output: 1.2 KB → sess_a1b2
            """,
            "sess_git_log": """
            ❯ git log --oneline -10

            89c73d8 feat: implement PTY session integration
            963e2d4 fix: correct keyboard input with NSView
            fc15ff3 fix: correct keyboard input handling
            f2332b8 Initial commit

            ❯ git diff --stat
             vibing-relay/src/main.rs | 145 +++++++++--
             vibing-relay/src/auth.rs | 227 +++++++++++++++
             vibing-ios/Models/AccountManager.swift | 310 +++++++++++++
             4 files changed, 650 insertions(+), 32 deletions(-)

            ❯ _
            """,
        ]

        for (sid, text) in outputs {
            appendOutput(sessionId: sid, text: text)
        }
    }
}

// MARK: - UITextFieldDelegate

extension TerminalViewerController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return false
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TerminalViewerController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let v = pan.velocity(in: view)
            // Only recognize horizontal swipes
            return abs(v.x) > abs(v.y) * 1.5
        }
        return true
    }
}

// MARK: - File Browser Table View

extension TerminalViewerController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // +1 for ".." parent directory row (unless at root)
        return fileBrowserEntries.count + (fileBrowserPath == "/" ? 0 : 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath)
        cell.backgroundColor = .clear
        if cell.selectedBackgroundView == nil {
            let v = UIView()
            v.backgroundColor = UIColor.white.withAlphaComponent(0.06)
            cell.selectedBackgroundView = v
        }

        let hasParent = fileBrowserPath != "/"
        let isParentRow = hasParent && indexPath.row == 0

        if isParentRow {
            cell.imageView?.image = UIImage(systemName: "arrow.up.doc")
            cell.imageView?.tintColor = .white.withAlphaComponent(0.4)
            cell.textLabel?.text = ".."
            cell.textLabel?.textColor = .white.withAlphaComponent(0.5)
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
            cell.accessoryType = .disclosureIndicator
        } else {
            let entryIndex = hasParent ? indexPath.row - 1 : indexPath.row
            guard entryIndex < fileBrowserEntries.count else { return cell }
            let entry = fileBrowserEntries[entryIndex]

            let name = entry["name"] as? String ?? ""
            let type = entry["type"] as? String ?? "file"
            let isDir = type == "dir"

            cell.textLabel?.text = name
            cell.textLabel?.textColor = .white.withAlphaComponent(isDir ? 0.9 : 0.7)
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 14, weight: isDir ? .medium : .regular)

            if isDir {
                cell.imageView?.image = UIImage(systemName: "folder.fill")
                cell.imageView?.tintColor = VibingColor.accent
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.imageView?.image = UIImage(systemName: "doc.text")
                cell.imageView?.tintColor = .white.withAlphaComponent(0.4)
                cell.accessoryType = .none
            }
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let hasParent = fileBrowserPath != "/"
        let isParentRow = hasParent && indexPath.row == 0

        if isParentRow {
            // Go up
            let parent = (fileBrowserPath as NSString).deletingLastPathComponent
            showFileBrowser(path: parent)
            return
        }

        let entryIndex = hasParent ? indexPath.row - 1 : indexPath.row
        guard entryIndex < fileBrowserEntries.count else { return }
        let entry = fileBrowserEntries[entryIndex]
        let name = entry["name"] as? String ?? ""
        let type = entry["type"] as? String ?? "file"

        if type == "dir" {
            // Navigate into directory
            let newPath = fileBrowserPath.hasSuffix("/")
                ? fileBrowserPath + name
                : fileBrowserPath + "/" + name
            showFileBrowser(path: newPath)
        } else {
            // Select file → insert @path into input
            let filePath = fileBrowserPath.hasSuffix("/")
                ? fileBrowserPath + name
                : fileBrowserPath + "/" + name
            insertTextToInput("@" + filePath + " ")
            dismissFileBrowser()
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}

// MARK: - Safe Index

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
