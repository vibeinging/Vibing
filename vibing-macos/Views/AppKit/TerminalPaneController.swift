//
//  TerminalPaneController.swift
//  VibeTerminal
//
//  单个终端窗格控制器
//

import AppKit
import Combine
import SwiftTerm

class TerminalPaneController: NSViewController {

    let paneId: UUID
    let sessionManager = TerminalSessionManager()
    var terminalView: RemoteTerminalView!

    private var initialCwd: String?
    private var initialTheme: TerminalTheme?
    // 间距系统：左侧多留空间（靠近侧边栏），右侧适度，上下紧凑
    private let insetLeft: CGFloat = 16
    private let insetRight: CGFloat = 8
    private let insetTop: CGFloat = 6
    private let insetBottom: CGFloat = 4
    var onPaneClicked: (() -> Void)?
    private var clickMonitor: Any?

    init(paneId: UUID, cwd: String?, theme: TerminalTheme?) {
        self.paneId = paneId
        self.initialCwd = cwd
        self.initialTheme = theme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        fputs("[PaneCtrl] viewDidLoad: view.bounds=\(view.bounds) view.frame=\(view.frame)\n", stderr)

        terminalView = RemoteTerminalView(frame: view.bounds, theme: initialTheme)

        // 按 SwiftTerm 官方示例的顺序：先创建 view，再设颜色
        if let theme = initialTheme {
            let bg = NSColor(
                calibratedRed: CGFloat(theme.background.0) / 255,
                green: CGFloat(theme.background.1) / 255,
                blue: CGFloat(theme.background.2) / 255, alpha: 1
            )
            let fg = NSColor(
                calibratedRed: CGFloat(theme.foreground.0) / 255,
                green: CGFloat(theme.foreground.1) / 255,
                blue: CGFloat(theme.foreground.2) / 255, alpha: 1
            )
            terminalView.nativeForegroundColor = fg
            terminalView.nativeBackgroundColor = bg
            terminalView.layer?.backgroundColor = bg.cgColor
            terminalView.caretColor = NSColor(
                calibratedRed: CGFloat(theme.cursor.0) / 255,
                green: CGFloat(theme.cursor.1) / 255,
                blue: CGFloat(theme.cursor.2) / 255, alpha: 1
            )

            // ANSI 调色板
            let ansi: [SwiftTerm.Color] = theme.ansiColors.map { (r, g, b) in
                SwiftTerm.Color(red: UInt16(r) << 8, green: UInt16(g) << 8, blue: UInt16(b) << 8)
            }
            if ansi.count >= 16 {
                terminalView.installColors(ansi)
            }

            // 容器背景色
            view.wantsLayer = true
            view.layer?.backgroundColor = bg.cgColor
        }

        let savedScale = UserDefaults.standard.double(forKey: "terminalFontScale")
        if savedScale > 0 && savedScale != 1.0 {
            terminalView.setFontSize(15 * CGFloat(savedScale))
        }

        view.addSubview(terminalView)

        // 点击终端时切换焦点到此 pane
        let clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let tv = self.terminalView else { return event }
            let pointInView = tv.convert(event.locationInWindow, from: nil)
            if tv.bounds.contains(pointInView) {
                self.onPaneClicked?()
            }
            return event
        }
        self.clickMonitor = clickMonitor
        sessionManager.startSession(terminalView: terminalView, cwd: initialCwd)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let tv = terminalView else { return }
        let s = view.bounds.size
        let minW = insetLeft + insetRight + 100
        let minH = insetTop + insetBottom + 100
        guard s.width > minW && s.height > minH else { return }

        // 非对称 padding：左侧宽（远离侧边栏），右侧窄，上下紧凑
        let origin = CGPoint(x: insetLeft, y: insetBottom)
        let size = NSSize(
            width: s.width - insetLeft - insetRight,
            height: s.height - insetTop - insetBottom
        )

        if tv.frame.origin != origin || tv.frame.size != size {
            tv.setFrameOrigin(origin)
            tv.setFrameSize(size)
        }
    }

    func applyTheme(_ theme: TerminalTheme) {
        terminalView?.applyTheme(theme)
    }

    func setFontScale(_ scale: CGFloat) {
        terminalView?.setFontSize(15 * scale)
    }

    func setActive(_ active: Bool) {
        terminalView?.isActivePane = active
        if active {
            DispatchQueue.main.async { [weak self] in
                guard let tv = self?.terminalView else { return }
                tv.window?.makeFirstResponder(tv)
            }
        }
    }

    func disconnect() {
        sessionManager.disconnect()
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
