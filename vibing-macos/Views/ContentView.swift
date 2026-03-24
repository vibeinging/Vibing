//
//  ContentView.swift
//  VibeTerminal
//
//  主界面 - 现代化终端 UI
//  多 Tab + 分屏 + 半透明标题栏 + 状态栏
//

import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var tabManager = TabManager()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var commandPalette = CommandPaletteManager()
    @StateObject private var searchManager = TerminalSearchManager()
    @StateObject private var launchConfigManager = LaunchConfigManager()
    @AppStorage("terminalFontScale") private var fontScale: Double = 1.0
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // 主布局
            VStack(spacing: 0) {
                // 自定义标题栏 + Tab 栏
                TitleBarView(tabManager: tabManager, themeManager: themeManager)

                // 终端内容区域
                TerminalContentArea(
                    tabManager: tabManager,
                    themeManager: themeManager,
                    searchManager: searchManager
                )

                // 状态栏
                StatusBarView(tabManager: tabManager, themeManager: themeManager)
            }
            .background(themeManager.currentTheme.backgroundSwiftUI)

            // 搜索栏覆盖层
            if searchManager.isActive {
                VStack {
                    HStack {
                        Spacer()
                        SearchBarView(searchManager: searchManager)
                            .padding(.trailing, 16)
                            .padding(.top, 48)
                    }
                    Spacer()
                }
            }

            // 命令面板覆盖层
            if commandPalette.isVisible {
                CommandPaletteView(manager: commandPalette)
            }

            // 设置页面覆盖层
            if showSettings {
                SwiftUI.Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { showSettings = false }

                SettingsView(themeManager: themeManager, tabManager: tabManager, launchConfigManager: launchConfigManager, isVisible: $showSettings)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSettings)
        .onAppear {
            // 初始化命令面板命令
            commandPalette.setup { action in
                switch action {
                case "newTab": tabManager.createTab()
                case "closeTab": if let id = tabManager.activeTabId { tabManager.closeTab(id: id) }
                case "find": searchManager.toggle()
                case "toggleTheme": themeManager.nextTheme()
                case "splitHorizontal": tabManager.splitActivePane(.horizontal)
                case "splitVertical": tabManager.splitActivePane(.vertical)
                case "nextPane": tabManager.selectNextPane()
                case "previousPane": tabManager.selectPreviousPane()
                case "maximizePane": tabManager.toggleMaximizeActivePane()
                case "settings": showSettings.toggle()
                case "saveLaunchConfig":
                    let name = "Layout \(launchConfigManager.configurations.count + 1)"
                    launchConfigManager.saveCurrentLayout(name: name, tabManager: tabManager)
                default: break
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenSettings"))) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.NewTab"))) { _ in
            tabManager.createTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.ClosePane"))) { _ in
            tabManager.closeActivePane()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.Find"))) { _ in
            searchManager.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.CommandPalette"))) { _ in
            commandPalette.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.SplitHorizontal"))) { _ in
            tabManager.splitActivePane(.horizontal)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.SplitVertical"))) { _ in
            tabManager.splitActivePane(.vertical)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.NextPane"))) { _ in
            tabManager.selectNextPane()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.PreviousPane"))) { _ in
            tabManager.selectPreviousPane()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.MaximizePane"))) { _ in
            tabManager.toggleMaximizeActivePane()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.NextTheme"))) { _ in
            themeManager.nextTheme()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.SaveLaunchConfig"))) { _ in
            let name = "Layout \(launchConfigManager.configurations.count + 1)"
            launchConfigManager.saveCurrentLayout(name: name, tabManager: tabManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.ZoomIn"))) { _ in
            fontScale = min(2.5, fontScale + 0.1)
            NotificationCenter.default.post(name: .init("TerminalFontScaleChanged"), object: nil, userInfo: ["scale": CGFloat(fontScale)])
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.ZoomOut"))) { _ in
            fontScale = max(0.5, fontScale - 0.1)
            NotificationCenter.default.post(name: .init("TerminalFontScaleChanged"), object: nil, userInfo: ["scale": CGFloat(fontScale)])
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MenuAction.ZoomReset"))) { _ in
            fontScale = 1.0
            NotificationCenter.default.post(name: .init("TerminalFontScaleChanged"), object: nil, userInfo: ["scale": CGFloat(1.0)])
        }
        .background(KeyboardShortcutHandler(
            tabManager: tabManager,
            commandPalette: commandPalette,
            searchManager: searchManager,
            showSettings: $showSettings
        ))
    }
}

// MARK: - Warm Accent Color

private let warmAccent = SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255)
private let warmAccentSubtle = SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255).opacity(0.15)

// MARK: - Title Bar

struct TitleBarView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 0) {
            // Tab 栏 — 始终显示
            HStack(spacing: 0) {
                // 窗口控制按钮占位
                SwiftUI.Color.clear
                    .frame(width: 72, height: 1)

                // Tab 列表
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(tabManager.tabs) { tab in
                            TabItemView(
                                tab: tab,
                                isActive: tab.id == tabManager.activeTabId,
                                themeManager: themeManager,
                                onSelect: { tabManager.selectTab(id: tab.id) },
                                onClose: { tabManager.closeTab(id: tab.id) }
                            )
                        }
                    }
                    .padding(.leading, 2)
                }

                Spacer(minLength: 4)

                // 新建 Tab
                Button(action: { tabManager.createTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .padding(.trailing, 10)
            }
            .frame(height: 36)
            .background(themeManager.currentTheme.backgroundSwiftUI.opacity(0.95))

            // 细分隔线
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Tab Item

struct TabItemView: View {
    let tab: TerminalTab
    let isActive: Bool
    @ObservedObject var themeManager: ThemeManager
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(tab.title)
                    .font(.system(size: 12, weight: isActive ? .medium : .regular))
                    .foregroundColor(isActive ? .white.opacity(0.9) : .white.opacity(0.45))
                    .lineLimit(1)
                    .padding(.leading, 14)

                // 关闭按钮 — 仅 hover 时显示
                if isHovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16, height: 16)
                    .padding(.leading, 6)
                    .padding(.trailing, 10)
                } else {
                    Spacer()
                        .frame(width: 14)
                        .padding(.trailing, 10)
                }
            }
            .frame(height: 34)
            .background(
                isActive
                    ? SwiftUI.Color.white.opacity(0.06)
                    : (isHovered ? SwiftUI.Color.white.opacity(0.03) : .clear)
            )

            // 活跃标签底部暖色指示线
            Rectangle()
                .fill(isActive ? warmAccent : .clear)
                .frame(height: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Terminal Content Area

struct TerminalContentArea: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var searchManager: TerminalSearchManager


    var body: some View {
        ZStack {
            if let tab = tabManager.activeTab {
                SplitPaneView(
                    layout: tab.splitLayout,
                    tabManager: tabManager,
                    themeManager: themeManager,
                    searchManager: searchManager
                )
            } else {
                EmptyStateView(onCreate: { tabManager.createTab() })
            }
        }
    }
}

// MARK: - Split Pane View

struct SplitPaneView: View {
    let layout: SplitPane
    @ObservedObject var tabManager: TabManager
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var searchManager: TerminalSearchManager

    @AppStorage("dimInactivePanes") private var dimInactivePanes = true
    @AppStorage("focusFollowsMouse") private var focusFollowsMouse = false

    /// Whether there are multiple panes in the current tab.
    private var hasMultiplePanes: Bool {
        layout.paneIds.count > 1
    }

    var body: some View {
        switch layout {
        case .single(let paneId):
            let isActive = paneId == tabManager.activePaneId
            WorkingTerminalView(paneId: paneId, cwd: tabManager.panes[paneId]?.cwd, theme: themeManager.currentTheme, isActivePane: hasMultiplePanes && isActive)
                .id(paneId)
                .overlay(alignment: .topLeading) {
                    // 活跃窗格左上角琥珀色圆点
                    if hasMultiplePanes && isActive {
                        PaneActiveIndicator()
                    }
                }
                .overlay(
                    // 非活跃窗格变暗
                    SwiftUI.Color(red: 0.04, green: 0.03, blue: 0.02)
                        .opacity(hasMultiplePanes && !isActive && dimInactivePanes ? 0.35 : 0)
                        .allowsHitTesting(false)
                )
                .contentShape(Rectangle())
                .onTapGesture { tabManager.selectPane(id: paneId) }
                .onHover { hovering in
                    if hovering && focusFollowsMouse {
                        tabManager.selectPane(id: paneId)
                    }
                }
                .contextMenu {
                    paneContextMenu(paneId: paneId)
                }

        case .horizontal(let left, let right, _):
            HSplitView {
                SplitPaneView(layout: left, tabManager: tabManager, themeManager: themeManager, searchManager: searchManager)
                    .frame(minWidth: 200)
                SplitPaneView(layout: right, tabManager: tabManager, themeManager: themeManager, searchManager: searchManager)
                    .frame(minWidth: 200)
            }

        case .vertical(let top, let bottom, _):
            VSplitView {
                SplitPaneView(layout: top, tabManager: tabManager, themeManager: themeManager, searchManager: searchManager)
                    .frame(minHeight: 100)
                SplitPaneView(layout: bottom, tabManager: tabManager, themeManager: themeManager, searchManager: searchManager)
                    .frame(minHeight: 100)
            }
        }
    }

    @ViewBuilder
    private func paneContextMenu(paneId: UUID) -> some View {
        Button("Split Right") {
            tabManager.selectPane(id: paneId)
            tabManager.splitActivePane(.horizontal)
        }
        Button("Split Down") {
            tabManager.selectPane(id: paneId)
            tabManager.splitActivePane(.vertical)
        }

        Divider()

        if hasMultiplePanes {
            Button("Move to New Tab") {
                tabManager.movePaneToNewTab(paneId: paneId)
            }
            Button("Close Pane") {
                tabManager.selectPane(id: paneId)
                tabManager.closeActivePane()
            }
        }
    }
}

// MARK: - Pane Active Indicator

struct PaneActiveIndicator: View {
    var body: some View {
        Circle()
            .fill(warmAccent)
            .frame(width: 6, height: 6)
            .shadow(color: warmAccent.opacity(0.5), radius: 3, x: 0, y: 0)
            .padding(5)
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var themeManager: ThemeManager
    @AppStorage("terminalFontScale") private var fontScale: Double = 1.0

    var body: some View {
        HStack(spacing: 0) {
            // 连接状态 + Shell
            if let tab = tabManager.activeTab {
                HStack(spacing: 6) {
                    Circle()
                        .fill(SwiftUI.Color(red: 130/255, green: 190/255, blue: 120/255))
                        .frame(width: 5, height: 5)
                    Text(tab.title)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()

            // 字体缩放（非 100% 时显示）
            if abs(fontScale - 1.0) > 0.01 {
                Text("\(Int(fontScale * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(warmAccent.opacity(0.5))
                    .padding(.trailing, 12)
            }

            // 窗格数量（仅多窗格时显示）
            if let tab = tabManager.activeTab, tab.splitLayout.paneIds.count > 1 {
                Text("\(tab.splitLayout.paneIds.count) panes")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))
                    .padding(.trailing, 12)
            }

            // 终端尺寸
            Text("120\u{00D7}36")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
                .padding(.trailing, 12)

            // 主题
            Text(themeManager.currentTheme.name)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(themeManager.currentTheme.backgroundSwiftUI)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let onCreate: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("~")
                .font(.system(size: 56, weight: .ultraLight, design: .monospaced))
                .foregroundColor(warmAccent.opacity(0.3))

            VStack(spacing: 6) {
                Text("Ready when you are")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                Text("Cmd+T to open a terminal")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.25))
            }

            Button(action: onCreate) {
                Text("Open Terminal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHovered ? .white.opacity(0.9) : .white.opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered ? warmAccent.opacity(0.2) : SwiftUI.Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovered ? warmAccent.opacity(0.4) : SwiftUI.Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Keyboard Shortcut Handler

struct KeyboardShortcutHandler: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var commandPalette: CommandPaletteManager
    @ObservedObject var searchManager: TerminalSearchManager
    @Binding var showSettings: Bool
    @AppStorage("terminalFontScale") private var fontScale: Double = 1.0

    private let minScale: Double = 0.5
    private let maxScale: Double = 2.5
    private let scaleStep: Double = 0.1

    private func adjustFontScale(_ delta: Double) {
        fontScale = min(maxScale, max(minScale, fontScale + delta))
        NotificationCenter.default.post(
            name: .init("TerminalFontScaleChanged"),
            object: nil,
            userInfo: ["scale": CGFloat(fontScale)]
        )
    }

    private func resetFontScale() {
        fontScale = 1.0
        NotificationCenter.default.post(
            name: .init("TerminalFontScaleChanged"),
            object: nil,
            userInfo: ["scale": CGFloat(1.0)]
        )
    }

    var body: some View {
        SwiftUI.Color.clear
            .frame(width: 0, height: 0)
            .background(
                Group {
                    // Cmd+T: 新建 Tab
                    Button("") { tabManager.createTab() }
                        .keyboardShortcut("t", modifiers: [.command])
                        .opacity(0)

                    // Cmd+W: 关闭当前窗格（最后一个窗格时关闭 Tab）
                    Button("") { tabManager.closeActivePane() }
                        .keyboardShortcut("w", modifiers: [.command])
                        .opacity(0)

                    // Cmd+K: 命令面板
                    Button("") { commandPalette.toggle() }
                        .keyboardShortcut("k", modifiers: [.command])
                        .opacity(0)

                    // Cmd+F: 搜索
                    Button("") { searchManager.toggle() }
                        .keyboardShortcut("f", modifiers: [.command])
                        .opacity(0)

                    // Cmd+D: 水平分屏
                    Button("") { tabManager.splitActivePane(.horizontal) }
                        .keyboardShortcut("d", modifiers: [.command])
                        .opacity(0)

                    // Cmd+Shift+D: 垂直分屏
                    Button("") { tabManager.splitActivePane(.vertical) }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                        .opacity(0)

                    // Cmd+1-9: 切换 Tab
                    ForEach(1..<10, id: \.self) { i in
                        let index = i
                        Button("") {
                            if index <= tabManager.tabs.count {
                                tabManager.selectTab(id: tabManager.tabs[index - 1].id)
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: [.command])
                        .opacity(0)
                    }

                    // Cmd+]: 下一个窗格
                    Button("") { tabManager.selectNextPane() }
                        .keyboardShortcut("]", modifiers: [.command])
                        .opacity(0)

                    // Cmd+[: 上一个窗格
                    Button("") { tabManager.selectPreviousPane() }
                        .keyboardShortcut("[", modifiers: [.command])
                        .opacity(0)

                    // Alt+Cmd+方向键: 切换窗格方向
                    Button("") { tabManager.navigatePane(.up) }
                        .keyboardShortcut(.upArrow, modifiers: [.option, .command])
                        .opacity(0)
                    Button("") { tabManager.navigatePane(.down) }
                        .keyboardShortcut(.downArrow, modifiers: [.option, .command])
                        .opacity(0)
                    Button("") { tabManager.navigatePane(.left) }
                        .keyboardShortcut(.leftArrow, modifiers: [.option, .command])
                        .opacity(0)
                    Button("") { tabManager.navigatePane(.right) }
                        .keyboardShortcut(.rightArrow, modifiers: [.option, .command])
                        .opacity(0)

                    // Ctrl+Cmd+方向键: 调整窗格大小
                    Button("") { tabManager.resizeActivePane(.up) }
                        .keyboardShortcut(.upArrow, modifiers: [.control, .command])
                        .opacity(0)
                    Button("") { tabManager.resizeActivePane(.down) }
                        .keyboardShortcut(.downArrow, modifiers: [.control, .command])
                        .opacity(0)
                    Button("") { tabManager.resizeActivePane(.left) }
                        .keyboardShortcut(.leftArrow, modifiers: [.control, .command])
                        .opacity(0)
                    Button("") { tabManager.resizeActivePane(.right) }
                        .keyboardShortcut(.rightArrow, modifiers: [.control, .command])
                        .opacity(0)

                    // Shift+Cmd+Enter: 切换窗格最大化
                    Button("") { tabManager.toggleMaximizeActivePane() }
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .opacity(0)

                    // Cmd+=: 放大字体
                    Button("") { adjustFontScale(scaleStep) }
                        .keyboardShortcut("=", modifiers: [.command])
                        .opacity(0)

                    // Cmd+-: 缩小字体
                    Button("") { adjustFontScale(-scaleStep) }
                        .keyboardShortcut("-", modifiers: [.command])
                        .opacity(0)

                    // Cmd+0: 重置字体
                    Button("") { resetFontScale() }
                        .keyboardShortcut("0", modifiers: [.command])
                        .opacity(0)
                }
            )
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 900, height: 600)
    }
}
