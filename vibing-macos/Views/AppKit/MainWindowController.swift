//
//  MainWindowController.swift
//  VibeTerminal
//
//  主窗口控制器 — 纯 AppKit，管理 tab 栏 + 终端分屏 + 状态栏 + overlay
//

import AppKit
import SwiftUI
import Combine

class MainWindowController: NSViewController {

    // MARK: - Model 层

    let tabManager = TabManager()
    let themeManager = ThemeManager()
    let commandPalette = CommandPaletteManager()
    let searchManager = TerminalSearchManager()
    let launchConfigManager = LaunchConfigManager()

    // MARK: - 子视图

    private var titleBarView: TitleBarNSView!
    private var fileTreePanel: FileTreePanel!
    private var terminalContainer: TerminalSplitContainer!
    private var statusBarView: StatusBarNSView!
    private var overlayContainer: NSView!
    private var overlayManager: OverlayManager!

    private var fileTreeWidthConstraint: NSLayoutConstraint!
    private var terminalLeadingConstraint: NSLayoutConstraint!
    private var isPanelOpen = false  // 默认关闭，用户手动点开
    private let panelWidth: CGFloat = 240

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - 快捷键

    private var eventMonitor: Any?
    @AppStorage("terminalFontScale") private var fontScale: Double = 1.0

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        fputs("[MainWC] viewDidLoad: view.frame=\(view.frame) view.bounds=\(view.bounds)\n", stderr)

        setupSubviews()
        setupCombineSubscriptions()
        setupNotificationListeners()
        setupKeyboardMonitor()
        setupCommandPalette()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = view.window else { return }

        // 窗口样式：标题栏透明 + 内容覆盖 + 圆角
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = ""
        window.backgroundColor = NSColor(calibratedRed: 10/255, green: 10/255, blue: 15/255, alpha: 1)

        // 窗口圆角
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 10
            contentView.layer?.masksToBounds = true
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - 子视图构建

    private func setupSubviews() {
        let theme = themeManager.currentTheme
        let bgColor = NSColor(
            calibratedRed: CGFloat(theme.background.0) / 255,
            green: CGFloat(theme.background.1) / 255,
            blue: CGFloat(theme.background.2) / 255, alpha: 1
        )
        view.layer?.backgroundColor = bgColor.cgColor

        // Title Bar
        titleBarView = TitleBarNSView(tabManager: tabManager, themeManager: themeManager)
        titleBarView.translatesAutoresizingMaskIntoConstraints = false
        titleBarView.onTogglePanel = { [weak self] in self?.toggleFilePanel() }
        view.addSubview(titleBarView)

        // File Tree Panel（左侧，默认隐藏）
        fileTreePanel = FileTreePanel()
        fileTreePanel.translatesAutoresizingMaskIntoConstraints = false
        fileTreePanel.wantsLayer = true
        fileTreePanel.layer?.masksToBounds = true
        fileTreePanel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        fileTreePanel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fileTreePanel.applyTheme(themeManager.currentTheme)
        fileTreePanel.onDirectorySelected = { path in
            // TODO: cd 到选中的目录
        }
        fileTreePanel.onNeedsFocusReturn = { [weak self] in
            self?.terminalContainer.focusActivePane()
        }
        view.addSubview(fileTreePanel)

        // Terminal Container
        terminalContainer = TerminalSplitContainer(tabManager: tabManager, themeManager: themeManager)
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalContainer)

        // Status Bar
        statusBarView = StatusBarNSView(tabManager: tabManager, themeManager: themeManager)
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBarView)

        // Overlay Container（最上层）
        overlayContainer = NSView()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayContainer.wantsLayer = true
        view.addSubview(overlayContainer)

        overlayManager = OverlayManager(
            container: overlayContainer,
            commandPalette: commandPalette,
            searchManager: searchManager,
            themeManager: themeManager,
            tabManager: tabManager,
            launchConfigManager: launchConfigManager
        )

        // File tree panel 宽度约束（默认 0，展开时 220）
        fileTreeWidthConstraint = fileTreePanel.widthAnchor.constraint(equalToConstant: isPanelOpen ? panelWidth : 0)
        fileTreeWidthConstraint.priority = .required
        terminalLeadingConstraint = terminalContainer.leadingAnchor.constraint(equalTo: fileTreePanel.trailingAnchor)

        // Auto Layout
        NSLayoutConstraint.activate([
            // Title Bar: top
            titleBarView.topAnchor.constraint(equalTo: view.topAnchor),
            titleBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleBarView.heightAnchor.constraint(equalToConstant: TitleBarNSView.barHeight),

            // File Tree Panel: left side, below title bar
            fileTreePanel.topAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            fileTreePanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fileTreePanel.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),
            fileTreeWidthConstraint,

            // Terminal: middle, right of file tree
            terminalContainer.topAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            terminalLeadingConstraint,
            terminalContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminalContainer.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),

            // Status Bar: bottom
            statusBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: 28),

            // Overlay: fills entire view
            overlayContainer.topAnchor.constraint(equalTo: view.topAnchor),
            overlayContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Combine 订阅

    private func setupCombineSubscriptions() {
        // Tab 变化 → 刷新 tab 栏 + 重建终端（分屏操作改的是 tabs 数组内容）
        tabManager.$tabs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.titleBarView.reload()
                self?.terminalContainer.rebuildIfNeeded()
                self?.statusBarView.refresh()
            }
            .store(in: &cancellables)

        // 活跃 Tab 变化 → 切换终端内容
        tabManager.$activeTabId
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.terminalContainer.rebuildIfNeeded() }
            .store(in: &cancellables)

        // 活跃 Pane 变化 → 更新焦点和边框
        tabManager.$activePaneId
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.terminalContainer.updateActivePane()
                self?.statusBarView.refresh()
            }
            .store(in: &cancellables)

        // 主题变化 → 全局刷新
        themeManager.$currentTheme
            .receive(on: RunLoop.main)
            .sink { [weak self] theme in self?.applyTheme(theme) }
            .store(in: &cancellables)
    }

    // MARK: - NotificationCenter 监听

    private func setupNotificationListeners() {
        let nc = NotificationCenter.default

        nc.publisher(for: .init("OpenSettings")).sink { [weak self] _ in
            self?.overlayManager.showSettings()
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.NewTab")).sink { [weak self] _ in
            self?.tabManager.createTab()
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.ClosePane")).sink { [weak self] _ in
            self?.tabManager.closeActivePane()
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.Find")).sink { [weak self] _ in
            self?.overlayManager.toggleSearch()
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.CommandPalette")).sink { [weak self] _ in
            self?.overlayManager.toggleCommandPalette()
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.SplitHorizontal")).sink { [weak self] _ in
            self?.tabManager.splitActivePane(.horizontal)
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.SplitVertical")).sink { [weak self] _ in
            self?.tabManager.splitActivePane(.vertical)
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.NextPane")).sink { [weak self] _ in
            self?.tabManager.selectNextPane()
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.PreviousPane")).sink { [weak self] _ in
            self?.tabManager.selectPreviousPane()
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.MaximizePane")).sink { [weak self] _ in
            self?.tabManager.toggleMaximizeActivePane()
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.NextTheme")).sink { [weak self] _ in
            self?.themeManager.nextTheme()
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.SaveLaunchConfig")).sink { [weak self] _ in
            guard let self = self else { return }
            let name = "Layout \(self.launchConfigManager.configurations.count + 1)"
            self.launchConfigManager.saveCurrentLayout(name: name, tabManager: self.tabManager)
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.ZoomIn")).sink { [weak self] _ in
            self?.adjustFontScale(0.1)
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.ZoomOut")).sink { [weak self] _ in
            self?.adjustFontScale(-0.1)
        }.store(in: &cancellables)

        nc.publisher(for: .init("MenuAction.ZoomReset")).sink { [weak self] _ in
            self?.resetFontScale()
        }.store(in: &cancellables)
    }

    // MARK: - 键盘补充（菜单未覆盖的快捷键）

    private func setupKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handleKeyEvent(event) { return nil }
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let chars = event.charactersIgnoringModifiers else { return false }

        // Cmd+1-9: 切换 Tab
        if flags == [.command], let digit = chars.first?.wholeNumberValue, digit >= 1 && digit <= 9 {
            if digit <= tabManager.tabs.count {
                tabManager.selectTab(id: tabManager.tabs[digit - 1].id)
            }
            return true
        }

        // Alt+Cmd+Arrow: 窗格方向导航
        if flags == [.option, .command] {
            switch event.keyCode {
            case 126: tabManager.navigatePane(.up); return true
            case 125: tabManager.navigatePane(.down); return true
            case 123: tabManager.navigatePane(.left); return true
            case 124: tabManager.navigatePane(.right); return true
            default: break
            }
        }

        // Ctrl+Cmd+Arrow: 窗格大小调整
        if flags == [.control, .command] {
            switch event.keyCode {
            case 126: tabManager.resizeActivePane(.up); return true
            case 125: tabManager.resizeActivePane(.down); return true
            case 123: tabManager.resizeActivePane(.left); return true
            case 124: tabManager.resizeActivePane(.right); return true
            default: break
            }
        }

        return false
    }

    // MARK: - 命令面板初始化

    private func setupCommandPalette() {
        commandPalette.setup { [weak self] action in
            guard let self = self else { return }
            switch action {
            case "newTab": self.tabManager.createTab()
            case "closeTab": if let id = self.tabManager.activeTabId { self.tabManager.closeTab(id: id) }
            case "find": self.overlayManager.toggleSearch()
            case "toggleTheme": self.themeManager.nextTheme()
            case "splitHorizontal": self.tabManager.splitActivePane(.horizontal)
            case "splitVertical": self.tabManager.splitActivePane(.vertical)
            case "nextPane": self.tabManager.selectNextPane()
            case "previousPane": self.tabManager.selectPreviousPane()
            case "maximizePane": self.tabManager.toggleMaximizeActivePane()
            case "settings": self.overlayManager.showSettings()
            case "saveLaunchConfig":
                let name = "Layout \(self.launchConfigManager.configurations.count + 1)"
                self.launchConfigManager.saveCurrentLayout(name: name, tabManager: self.tabManager)
            default: break
            }
        }
    }

    // MARK: - 主题

    private func applyTheme(_ theme: TerminalTheme) {
        let bgColor = NSColor(
            calibratedRed: CGFloat(theme.background.0) / 255,
            green: CGFloat(theme.background.1) / 255,
            blue: CGFloat(theme.background.2) / 255, alpha: 1
        )
        view.layer?.backgroundColor = bgColor.cgColor
        titleBarView.applyTheme(theme)
        statusBarView.applyTheme(theme)
        terminalContainer.applyTheme(theme)
        fileTreePanel.applyTheme(theme)
    }

    // MARK: - 文件面板

    private func toggleFilePanel() {
        isPanelOpen.toggle()

        // 展开时加载当前 session 的工作目录
        if isPanelOpen {
            var cwd = FileManager.default.homeDirectoryForCurrentUser.path

            // 尝试从活跃 pane 的 sessionManager 获取 cwd
            if let activePaneId = tabManager.activePaneId,
               let pane = terminalContainer.getPaneController(activePaneId) {
                cwd = pane.sessionManager.lastKnownCwd ?? cwd
            }

            fileTreePanel.loadDirectory(cwd)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            fileTreeWidthConstraint.animator().constant = isPanelOpen ? panelWidth : 0
            view.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - 字体缩放

    private func adjustFontScale(_ delta: Double) {
        fontScale = min(2.5, max(0.5, fontScale + delta))
        terminalContainer.setFontScale(CGFloat(fontScale))
    }

    private func resetFontScale() {
        fontScale = 1.0
        terminalContainer.setFontScale(1.0)
    }
}
