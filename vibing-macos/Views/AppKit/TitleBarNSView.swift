//
//  TitleBarNSView.swift
//  VibeTerminal
//
//  Tab bar — MemMe 风格深色设计，春绿色强调
//

import AppKit
import Combine

// MARK: - 设计色板（参考 MemMe，强调色改为春绿）

enum VibingColors {
    // 品牌色 — 春天浅绿
    static let accent = NSColor(calibratedRed: 106/255, green: 194/255, blue: 120/255, alpha: 1)
    static let accentLight = NSColor(calibratedRed: 140/255, green: 210/255, blue: 150/255, alpha: 1)

    // 背景层级（从深到浅）
    static let bg0 = NSColor(calibratedRed: 10/255, green: 10/255, blue: 15/255, alpha: 1)     // 最深
    static let bg1 = NSColor(calibratedRed: 18/255, green: 18/255, blue: 26/255, alpha: 1)     // 卡片/面板
    static let bg2 = NSColor(calibratedRed: 26/255, green: 26/255, blue: 46/255, alpha: 1)     // 嵌套容器
    static let bg3 = NSColor(calibratedRed: 22/255, green: 22/255, blue: 42/255, alpha: 1)     // 输入框

    // 文本层级
    static let textPrimary = NSColor.white.withAlphaComponent(0.90)
    static let textSecondary = NSColor.white.withAlphaComponent(0.55)
    static let textMuted = NSColor.white.withAlphaComponent(0.35)
    static let textGhost = NSColor(calibratedRed: 136/255, green: 136/255, blue: 136/255, alpha: 1)

    // 边框
    static let border = NSColor.white.withAlphaComponent(0.06)
}

// MARK: - Title Bar

class TitleBarNSView: NSView {

    private let tabManager: TabManager
    private let themeManager: ThemeManager

    private var panelBtn: NSButton!
    private var tabStack: NSStackView!
    private var scroll: NSScrollView!
    private var addBtn: NSButton!

    var onTogglePanel: (() -> Void)?

    static let barHeight: CGFloat = 44  // 和 MemMe 一致的高度

    init(tabManager: TabManager, themeManager: ThemeManager) {
        self.tabManager = tabManager
        self.themeManager = themeManager
        super.init(frame: .zero)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTheme(themeManager.currentTheme)
    }

    private func setup() {
        // Panel toggle（sidebar.left 图标）
        let panelCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        panelBtn = NSButton(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Panel")!.withSymbolConfiguration(panelCfg)!, target: self, action: #selector(togglePanel))
        panelBtn.isBordered = false
        panelBtn.contentTintColor = VibingColors.textMuted
        panelBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panelBtn)

        // Tab 列表
        tabStack = NSStackView()
        tabStack.orientation = .horizontal
        tabStack.spacing = 4
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        scroll = NSScrollView()
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tabStack
        addSubview(scroll)

        // + 按钮
        let addCfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        addBtn = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")!.withSymbolConfiguration(addCfg)!, target: self, action: #selector(addTab))
        addBtn.isBordered = false
        addBtn.contentTintColor = VibingColors.textMuted
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addBtn)

        // 底部边框
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = VibingColors.border.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        NSLayoutConstraint.activate([
            panelBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            panelBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            panelBtn.widthAnchor.constraint(equalToConstant: 30),
            panelBtn.heightAnchor.constraint(equalToConstant: 30),

            scroll.leadingAnchor.constraint(equalTo: panelBtn.trailingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: border.topAnchor, constant: -6),
            scroll.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -8),

            addBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            addBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 30),
            addBtn.heightAnchor.constraint(equalToConstant: 30),

            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
        ])

        reload()
    }

    func reload() {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let multi = tabManager.tabs.count > 1

        for tab in tabManager.tabs {
            let active = tab.id == tabManager.activeTabId
            let chip = TabChip(
                tab: tab, isActive: active, multi: multi,
                onSelect: { [weak self] in self?.tabManager.selectTab(id: tab.id) },
                onClose: { [weak self] in self?.tabManager.closeTab(id: tab.id) }
            )
            tabStack.addArrangedSubview(chip)
        }
    }

    func applyTheme(_ theme: TerminalTheme) {
        wantsLayer = true
        layer?.backgroundColor = VibingColors.bg1.cgColor
    }

    @objc private func addTab() { tabManager.createTab() }
    @objc private func togglePanel() { onTogglePanel?() }
}

// MARK: - Tab Chip（MemMe 按钮风格：圆角 10pt，填充背景）

class TabChip: NSView {

    private let tab: TerminalTab
    private let isActive: Bool
    private let multi: Bool
    private let onSelect: () -> Void
    private let onClose: () -> Void

    private var titleLabel: NSTextField!
    private var relayDot: NSView!
    private var closeBtn: NSButton!
    private var tracking: NSTrackingArea?
    private var hovered = false

    /// Relay sharing status for this tab
    enum RelayStatus {
        case none        // Not sharing
        case waiting     // Sharing, no peer connected
        case connected   // Peer (mobile) connected
    }

    private let relayStatus: RelayStatus

    init(tab: TerminalTab, isActive: Bool, multi: Bool,
         onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.tab = tab
        self.isActive = isActive
        self.multi = multi
        self.onSelect = onSelect
        self.onClose = onClose
        self.relayStatus = Self.detectRelayStatus(for: tab)
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 32))
        wantsLayer = true
        layer?.cornerRadius = 8
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Check relay status for this tab's panes
    private static func detectRelayStatus(for tab: TerminalTab) -> RelayStatus {
        let manager = RelaySessionManager.shared
        // Check all pane IDs — any active relay session means sharing
        for (_, state) in manager.sessions {
            if state.isSharing {
                return state.peerConnected ? .connected : .waiting
            }
        }
        return .none
    }

    override var intrinsicContentSize: NSSize {
        let w = (titleLabel?.intrinsicContentSize.width ?? 50)
        let dotWidth: CGFloat = relayStatus != .none ? 14 : 0
        return NSSize(width: min(220, w + 54 + dotWidth), height: 32)
    }

    private func build() {
        // Relay status dot
        relayDot = NSView()
        relayDot.wantsLayer = true
        relayDot.layer?.cornerRadius = 3.5
        relayDot.translatesAutoresizingMaskIntoConstraints = false
        switch relayStatus {
        case .connected:
            relayDot.layer?.backgroundColor = VibingColors.accent.cgColor
            relayDot.toolTip = "Mobile connected"
        case .waiting:
            relayDot.layer?.backgroundColor = NSColor.systemYellow.cgColor
            relayDot.toolTip = "Sharing, waiting for device"
        case .none:
            relayDot.isHidden = true
        }
        addSubview(relayDot)

        titleLabel = NSTextField(labelWithString: tab.title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: isActive ? .semibold : .regular)
        titleLabel.textColor = isActive ? VibingColors.textPrimary : VibingColors.textSecondary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // 关闭按钮
        let sym = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        closeBtn = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!.withSymbolConfiguration(sym)!, target: self, action: #selector(closeTapped))
        closeBtn.isBordered = false
        closeBtn.contentTintColor = VibingColors.textGhost
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.isHidden = !multi
        addSubview(closeBtn)

        let dotLeading: CGFloat = relayStatus != .none ? 20 : 12

        NSLayoutConstraint.activate([
            relayDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            relayDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            relayDot.widthAnchor.constraint(equalToConstant: 7),
            relayDot.heightAnchor.constraint(equalToConstant: 7),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: dotLeading),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeBtn.leadingAnchor, constant: -4),

            closeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 16),
            closeBtn.heightAnchor.constraint(equalToConstant: 16),
        ])

        refreshSurface()
    }

    private func refreshSurface() {
        if isActive {
            layer?.backgroundColor = VibingColors.bg2.cgColor
            layer?.borderColor = VibingColors.border.cgColor
            layer?.borderWidth = 1
        } else if hovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
            layer?.borderWidth = 0
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(tracking!)
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true; refreshSurface()
        closeBtn.contentTintColor = VibingColors.textSecondary
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false; refreshSurface()
        closeBtn.contentTintColor = VibingColors.textGhost
    }

    override func mouseDown(with event: NSEvent) { onSelect() }
    @objc private func closeTapped() { onClose() }
}
