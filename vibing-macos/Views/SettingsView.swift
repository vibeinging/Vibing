//
//  SettingsView.swift
//  VibeTerminal
//
//  自定义设置页面 - Warp 风格
//  左侧 sidebar 导航 + 右侧内容区域
//

import SwiftUI

// MARK: - Settings Category

// MARK: - Language

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    static var current: AppLanguage {
        get {
            let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
            return AppLanguage(rawValue: saved) ?? .english
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage")
        }
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case account = "Account"
    case appearance = "Appearance"
    case terminal = "Terminal"
    case keybindings = "Keybindings"
    case sessions = "Sessions"
    case features = "Features"
    case advanced = "Advanced"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .account: return "person.crop.circle.fill"
        case .appearance: return "paintbrush.fill"
        case .terminal: return "terminal.fill"
        case .keybindings: return "keyboard"
        case .sessions: return "rectangle.stack.fill"
        case .features: return "sparkles"
        case .advanced: return "gearshape.2.fill"
        case .about: return "info.circle.fill"
        }
    }

    var localizedName: String {
        let zh = AppLanguage.current == .chinese
        switch self {
        case .account: return zh ? "账号" : "Account"
        case .appearance: return zh ? "外观" : "Appearance"
        case .terminal: return zh ? "终端" : "Terminal"
        case .keybindings: return zh ? "快捷键" : "Keybindings"
        case .sessions: return zh ? "会话" : "Sessions"
        case .features: return zh ? "功能" : "Features"
        case .advanced: return zh ? "高级" : "Advanced"
        case .about: return zh ? "关于" : "About"
        }
    }

    var subtitle: String {
        let zh = AppLanguage.current == .chinese
        switch self {
        case .account: return zh ? "登录、设备、网络" : "Login, devices, network"
        case .appearance: return zh ? "主题、字体、面板" : "Theme, font, panes"
        case .terminal: return zh ? "Shell、光标、回滚" : "Shell, cursor, scrollback"
        case .keybindings: return zh ? "键盘快捷方式" : "Keyboard shortcuts"
        case .sessions: return zh ? "启动配置" : "Launch configurations"
        case .features: return zh ? "Hook API、自动化、安全" : "Hook API, automation, security"
        case .advanced: return zh ? "性能、诊断" : "Performance, diagnostics"
        case .about: return zh ? "版本、许可" : "Version, licenses"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var tabManager: TabManager
    @ObservedObject var launchConfigManager: LaunchConfigManager
    @Binding var isVisible: Bool
    @State private var selectedCategory: SettingsCategory = .appearance
    @State private var hoveredCategory: SettingsCategory?
    @State private var currentLanguage: AppLanguage = AppLanguage.current

    private let sidebarWidth: CGFloat = 210
    private let bgColor = SwiftUI.Color(red: 28/255, green: 27/255, blue: 25/255)
    private let sidebarBg = SwiftUI.Color(red: 22/255, green: 21/255, blue: 20/255)
    private let cardBg = SwiftUI.Color(red: 36/255, green: 34/255, blue: 32/255)
    private let borderColor = SwiftUI.Color.white.opacity(0.05)
    private let accentBlue = SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255)

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Left Sidebar
            sidebar

            // 分隔线
            Rectangle()
                .fill(borderColor)
                .frame(width: 1)

            // MARK: Right Content
            contentArea
        }
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SwiftUI.Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
        .frame(width: 860, height: 620)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(currentLanguage == .chinese ? "设置" : "Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Button(action: { isVisible = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .background(SwiftUI.Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Category List
            VStack(spacing: 2) {
                ForEach(SettingsCategory.allCases) { category in
                    sidebarItem(category)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Language toggle
            HStack(spacing: 4) {
                ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                    Button(action: {
                        currentLanguage = lang
                        AppLanguage.current = lang
                    }) {
                        Text(lang.displayName)
                            .font(.system(size: 10, weight: currentLanguage == lang ? .semibold : .regular))
                            .foregroundColor(currentLanguage == lang ? accentBlue : .white.opacity(0.35))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(currentLanguage == lang ? accentBlue.opacity(0.12) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Version info at bottom
            Text("Vibing v0.0.1")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: sidebarWidth)
        .background(sidebarBg)
    }

    private func sidebarItem(_ category: SettingsCategory) -> some View {
        let isSelected = selectedCategory == category
        let isHovered = hoveredCategory == category

        return Button(action: { selectedCategory = category }) {
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? accentBlue : .white.opacity(0.45))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.localizedName)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? .white.opacity(0.95) : .white.opacity(0.7))
                    Text(category.subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accentBlue.opacity(0.15) : (isHovered ? SwiftUI.Color.white.opacity(0.04) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? accentBlue.opacity(0.3) : .clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredCategory = $0 ? category : nil }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Section title
                Text(selectedCategory.localizedName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.bottom, 20)

                // Content based on category
                switch selectedCategory {
                case .account:
                    AccountSettings(cardBg: cardBg, borderColor: borderColor, accentBlue: accentBlue)
                case .appearance:
                    AppearanceSettings(themeManager: themeManager, cardBg: cardBg, borderColor: borderColor, accentBlue: accentBlue)
                case .terminal:
                    TerminalSettings(cardBg: cardBg, borderColor: borderColor)
                case .keybindings:
                    KeybindingsSettings(cardBg: cardBg, borderColor: borderColor)
                case .sessions:
                    SessionsSettings(
                        tabManager: tabManager,
                        launchConfigManager: launchConfigManager,
                        cardBg: cardBg,
                        borderColor: borderColor,
                        accentBlue: accentBlue
                    )
                case .features:
                    FeaturesSettings(cardBg: cardBg, borderColor: borderColor)
                case .advanced:
                    AdvancedSettings(cardBg: cardBg, borderColor: borderColor)
                case .about:
                    AboutSettings(cardBg: cardBg, borderColor: borderColor, accentBlue: accentBlue)
                }

                Spacer(minLength: 20)
            }
            .padding(28)
        }
    }
}

// MARK: - Settings Card

struct SettingsCard<Content: View>: View {
    let title: String
    let cardBg: SwiftUI.Color
    let borderColor: SwiftUI.Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 0.5)
            )
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Settings Row

struct SettingsRow<Trailing: View>: View {
    let label: String
    let description: String?
    let showDivider: Bool
    @ViewBuilder let trailing: () -> Trailing

    init(label: String, description: String? = nil, showDivider: Bool = true, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.description = description
        self.showDivider = showDivider
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    if let desc = description {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
                Spacer()
                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if showDivider {
                Rectangle()
                    .fill(SwiftUI.Color.white.opacity(0.04))
                    .frame(height: 0.5)
                    .padding(.leading, 14)
            }
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettings: View {
    @ObservedObject var themeManager: ThemeManager
    let cardBg: SwiftUI.Color
    let borderColor: SwiftUI.Color
    let accentBlue: SwiftUI.Color

    @AppStorage("terminalFontSize") private var fontSize: Double = 13
    @AppStorage("terminalFont") private var selectedFont = "Menlo"
    @AppStorage("dimInactivePanes") private var dimInactivePanes = true
    @AppStorage("focusFollowsMouse") private var focusFollowsMouse = false

    private let fonts = ["Menlo", "SF Mono", "Monaco", "Fira Code", "JetBrains Mono", "Cascadia Code"]
    private var zh: Bool { AppLanguage.current == .chinese }

    var body: some View {
        // Theme
        SettingsCard(title: zh ? "主题" : "Theme", cardBg: cardBg, borderColor: borderColor) {
            themeGrid
        }

        // Font
        SettingsCard(title: zh ? "字体" : "Font", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "字体" : "Font Family", description: zh ? "终端等宽字体" : "Monospace font for terminal") {
                Picker("", selection: $selectedFont) {
                    ForEach(fonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            SettingsRow(label: zh ? "字号" : "Font Size", description: "\(Int(fontSize))pt", showDivider: false) {
                HStack(spacing: 8) {
                    Button(action: { if fontSize > 8 { fontSize -= 1 } }) {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 24, height: 24)
                            .background(SwiftUI.Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(fontSize))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 28)

                    Button(action: { if fontSize < 24 { fontSize += 1 } }) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 24, height: 24)
                            .background(SwiftUI.Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(.white.opacity(0.6))
            }
        }

        // Preview
        SettingsCard(title: zh ? "预览" : "Preview", cardBg: cardBg, borderColor: borderColor) {
            VStack(alignment: .leading, spacing: 0) {
                Text("$ echo \"Hello, Vibing\"")
                    .font(.system(size: CGFloat(fontSize), design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.foregroundSwiftUI)
                Text("Hello, Vibing")
                    .font(.system(size: CGFloat(fontSize), design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.foregroundSwiftUI.opacity(0.7))
                Text("$ _")
                    .font(.system(size: CGFloat(fontSize), design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.foregroundSwiftUI)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(themeManager.currentTheme.backgroundSwiftUI)
        }

        // Panes
        SettingsCard(title: zh ? "面板" : "Panes", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "暗化非活动面板" : "Dim Inactive Panes", description: zh ? "分屏时暗化非聚焦面板" : "Darken non-focused panes in split view") {
                Toggle("", isOn: $dimInactivePanes)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentBlue)
            }

            SettingsRow(label: zh ? "鼠标跟随聚焦" : "Focus Follows Mouse", description: zh ? "鼠标悬停激活面板" : "Activate pane on mouse hover", showDivider: false) {
                Toggle("", isOn: $focusFollowsMouse)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentBlue)
            }
        }

        // Window
        SettingsCard(title: zh ? "窗口" : "Window", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "背景透明度" : "Background Opacity", description: "\(Int(themeManager.currentTheme.backgroundOpacity * 100))%", showDivider: false) {
                Slider(value: .constant(themeManager.currentTheme.backgroundOpacity), in: 0.5...1.0, step: 0.05)
                    .frame(width: 140)
                    .tint(accentBlue)
            }
        }
    }

    private var themeGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)]

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(themeManager.allThemes) { theme in
                themeCard(theme)
            }
        }
        .padding(14)
    }

    private func themeCard(_ theme: TerminalTheme) -> some View {
        let isSelected = themeManager.currentTheme.name == theme.name

        return Button(action: { themeManager.applyTheme(theme) }) {
            VStack(spacing: 6) {
                // Color preview
                RoundedRectangle(cornerRadius: 6)
                    .fill(SwiftUI.Color(
                        red: Double(theme.background.0) / 255,
                        green: Double(theme.background.1) / 255,
                        blue: Double(theme.background.2) / 255
                    ))
                    .frame(height: 48)
                    .overlay(
                        VStack(alignment: .leading, spacing: 2) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(SwiftUI.Color(
                                    red: Double(theme.foreground.0) / 255,
                                    green: Double(theme.foreground.1) / 255,
                                    blue: Double(theme.foreground.2) / 255
                                ).opacity(0.6))
                                .frame(width: 40, height: 3)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(SwiftUI.Color(
                                    red: Double(theme.ansiColors[4].0) / 255,
                                    green: Double(theme.ansiColors[4].1) / 255,
                                    blue: Double(theme.ansiColors[4].2) / 255
                                ).opacity(0.8))
                                .frame(width: 28, height: 3)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(SwiftUI.Color(
                                    red: Double(theme.ansiColors[2].0) / 255,
                                    green: Double(theme.ansiColors[2].1) / 255,
                                    blue: Double(theme.ansiColors[2].2) / 255
                                ).opacity(0.8))
                                .frame(width: 34, height: 3)
                        }
                        .padding(8),
                        alignment: .topLeading
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? accentBlue : SwiftUI.Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
                    )

                Text(theme.name)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Settings

struct TerminalSettings: View {
    let cardBg: SwiftUI.Color
    let borderColor: SwiftUI.Color

    @ObservedObject private var shellDetector = ShellDetector.shared
    @AppStorage("scrollbackSize") private var scrollback: Double = 10000
    @AppStorage("cursorBlink") private var cursorBlink = true
    @AppStorage("cursorStyle") private var cursorStyle = "block"
    @AppStorage("terminalCols") private var cols: Double = 120
    @AppStorage("terminalRows") private var rows: Double = 36

    private let accentBlue = SwiftUI.Color(red: 82/255, green: 139/255, blue: 255/255)
    private var zh: Bool { AppLanguage.current == .chinese }

    var body: some View {
        SettingsCard(title: "Shell", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "默认 Shell" : "Default Shell") {
                Picker("", selection: $shellDetector.selectedShellPath) {
                    ForEach(shellDetector.availableShells) { shell in
                        HStack(spacing: 6) {
                            Text(shell.name)
                                .font(.system(size: 13))
                            if shell.isDefault {
                                Text(zh ? "系统" : "system")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(SwiftUI.Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        .tag(shell.path)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            // 当前选中 shell 的详情
            if let selected = shellDetector.availableShells.first(where: { $0.path == shellDetector.selectedShellPath }) {
                SettingsRow(label: zh ? "路径" : "Path", description: selected.path) {
                    EmptyView()
                }

                if !selected.version.isEmpty {
                    SettingsRow(label: zh ? "版本" : "Version", description: selected.version) {
                        EmptyView()
                    }
                }
            }

            SettingsRow(label: zh ? "工作目录" : "Working Directory", showDivider: false) {
                Text("~")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }

        // 检测到的所有 Shell 列表
        SettingsCard(title: zh ? "可用 Shell (\(shellDetector.availableShells.count))" : "Available Shells (\(shellDetector.availableShells.count))", cardBg: cardBg, borderColor: borderColor) {
            ForEach(Array(shellDetector.availableShells.enumerated()), id: \.element.id) { index, shell in
                let isLast = index == shellDetector.availableShells.count - 1
                SettingsRow(
                    label: shell.name,
                    description: shell.path,
                    showDivider: !isLast
                ) {
                    HStack(spacing: 8) {
                        if shell.isDefault {
                            Text(zh ? "默认" : "Default")
                                .font(.system(size: 10))
                                .foregroundColor(accentBlue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentBlue.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        if shell.path == shellDetector.selectedShellPath {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(accentBlue)
                        } else {
                            Button(zh ? "使用" : "Use") {
                                shellDetector.selectedShellPath = shell.path
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            if shellDetector.availableShells.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(zh ? "正在检测 Shell..." : "Detecting shells...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }

        SettingsCard(title: zh ? "光标" : "Cursor", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "光标样式" : "Cursor Style") {
                Picker("", selection: $cursorStyle) {
                    Text(zh ? "方块" : "Block").tag("block")
                    Text(zh ? "下划线" : "Underline").tag("underline")
                    Text(zh ? "竖线" : "Bar").tag("bar")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            SettingsRow(label: zh ? "光标闪烁" : "Blinking Cursor", showDivider: false) {
                Toggle("", isOn: $cursorBlink)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentBlue)
            }
        }

        SettingsCard(title: zh ? "显示" : "Display", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "默认列数" : "Default Columns", description: "\(Int(cols))") {
                Slider(value: $cols, in: 40...200, step: 1)
                    .frame(width: 140)
            }

            SettingsRow(label: zh ? "默认行数" : "Default Rows", description: "\(Int(rows))") {
                Slider(value: $rows, in: 10...80, step: 1)
                    .frame(width: 140)
            }

            SettingsRow(label: zh ? "回滚行数" : "Scrollback Lines", description: scrollback == 0 ? (zh ? "已禁用" : "Disabled") : "\(Int(scrollback))", showDivider: false) {
                Slider(value: $scrollback, in: 0...50000, step: 1000)
                    .frame(width: 140)
            }
        }
    }
}

// MARK: - Keybindings Settings

struct KeybindingsSettings: View {
    let cardBg: SwiftUI.Color
    let borderColor: SwiftUI.Color
    private var zh: Bool { AppLanguage.current == .chinese }

    var body: some View {
        SettingsCard(title: zh ? "通用" : "General", cardBg: cardBg, borderColor: borderColor) {
            keybindingRow(zh ? "新建标签页" : "New Tab", shortcut: "Cmd + T")
            keybindingRow(zh ? "关闭标签页" : "Close Tab", shortcut: "Cmd + W")
            keybindingRow(zh ? "设置" : "Settings", shortcut: "Cmd + ,")
            keybindingRow(zh ? "命令面板" : "Command Palette", shortcut: "Cmd + K")
            keybindingRow(zh ? "查找" : "Find", shortcut: "Cmd + F", showDivider: false)
        }

        SettingsCard(title: zh ? "分屏" : "Split Panes", cardBg: cardBg, borderColor: borderColor) {
            keybindingRow(zh ? "水平分屏" : "Split Horizontal", shortcut: "Cmd + D")
            keybindingRow(zh ? "垂直分屏" : "Split Vertical", shortcut: "Cmd + Shift + D")
            keybindingRow(zh ? "下一面板" : "Next Pane", shortcut: "Cmd + ]")
            keybindingRow(zh ? "上一面板" : "Previous Pane", shortcut: "Cmd + [")
            keybindingRow(zh ? "最大化面板" : "Maximize Pane", shortcut: "Shift + Cmd + Enter", showDivider: false)
        }

        SettingsCard(title: zh ? "导航" : "Navigation", cardBg: cardBg, borderColor: borderColor) {
            keybindingRow(zh ? "向上导航" : "Navigate Up", shortcut: "Alt + Cmd + Up")
            keybindingRow(zh ? "向下导航" : "Navigate Down", shortcut: "Alt + Cmd + Down")
            keybindingRow(zh ? "向左导航" : "Navigate Left", shortcut: "Alt + Cmd + Left")
            keybindingRow(zh ? "向右导航" : "Navigate Right", shortcut: "Alt + Cmd + Right", showDivider: false)
        }

        SettingsCard(title: zh ? "调整大小" : "Resize", cardBg: cardBg, borderColor: borderColor) {
            keybindingRow(zh ? "向上调整" : "Resize Up", shortcut: "Ctrl + Cmd + Up")
            keybindingRow(zh ? "向下调整" : "Resize Down", shortcut: "Ctrl + Cmd + Down")
            keybindingRow(zh ? "向左调整" : "Resize Left", shortcut: "Ctrl + Cmd + Left")
            keybindingRow(zh ? "向右调整" : "Resize Right", shortcut: "Ctrl + Cmd + Right", showDivider: false)
        }
    }

    private func keybindingRow(_ label: String, shortcut: String, showDivider: Bool = true) -> some View {
        SettingsRow(label: label, showDivider: showDivider) {
            Text(shortcut)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SwiftUI.Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Network Settings

struct NetworkSettings: View {
    let cardBg: SwiftUI.Color
    let borderColor: SwiftUI.Color

    @AppStorage("relayServerURL") private var relayURL = ""
    private var zh: Bool { AppLanguage.current == .chinese }

    var body: some View {
        SettingsCard(title: zh ? "后端服务器" : "Backend Server", cardBg: cardBg, borderColor: borderColor) {

            SettingsRow(label: zh ? "状态" : "Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(SwiftUI.Color.green)
                        .frame(width: 6, height: 6)
                    Text(zh ? "运行中" : "Running")
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                }
            }

            SettingsRow(label: zh ? "重启服务器" : "Restart Server", showDivider: false) {
                Button(zh ? "重启" : "Restart") {
                    // TODO: restart backend
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

        SettingsCard(title: zh ? "中继" : "Relay", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "中继服务器" : "Relay Server", description: zh ? "端到端加密中继" : "End-to-end encrypted relay") {
                TextField("", text: $relayURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .font(.system(size: 12, design: .monospaced))
            }

            SettingsRow(label: zh ? "加密方式" : "Encryption", showDivider: false) {
                Text("AES-256-GCM")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - Features Settings

struct FeaturesSettings: View {
    let cardBg: SwiftUI.Color
    let borderColor: SwiftUI.Color

    private let accentGreen = SwiftUI.Color(red: 106/255, green: 194/255, blue: 120/255)
    private var zh: Bool { AppLanguage.current == .chinese }

    // Hook API
    @AppStorage("hookApiEnabled") private var hookApiEnabled = false
    @State private var hookApiToken: String = ""
    @State private var showToken = false
    @State private var showRestartAlert = false
    @State private var copied = false

    // Automation
    @AppStorage("featureAutoApprove") private var autoApprove = false
    @AppStorage("featureCircuitBreaker") private var circuitBreaker = false
    @AppStorage("featureSecretDetector") private var secretDetector = false
    @AppStorage("featureSessionAudit") private var sessionAudit = false
    @AppStorage("featureIdleNotify") private var idleNotify = false

    // Auto-approve config
    @AppStorage("autoApproveReadOnly") private var autoApproveReadOnly = true
    @AppStorage("autoApproveBlockDangerous") private var autoApproveBlockDangerous = true

    // Circuit breaker config
    @AppStorage("circuitBreakerLoopCount") private var circuitBreakerLoopCount = 5

    @ViewBuilder
    private func desc(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.45))
            .lineSpacing(3)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
    }

    var body: some View {
        // MARK: Hook API
        desc(zh
            ? "Vibing 工作在 PTY 层 — 每一次按键、每一行输出都经过这里。Hook API 将这条数据流暴露为可编程的 HTTP 接口，让外部脚本、Webhook 以及下方的自动化功能成为可能。"
            : "Vibing sits at the PTY layer — every keystroke and every output passes through it. The Hook API exposes this data stream as a programmable HTTP interface, enabling external scripts, webhooks, and the automation features below."
        )

        SettingsCard(title: "Hook API", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(
                label: zh ? "启用 Hook API" : "Enable Hook API",
                description: zh ? "通过 HTTP 暴露 PTY 事件，供外部工具和下方功能使用" : "Expose PTY events via HTTP for external tools and the features below"
            ) {
                Toggle("", isOn: $hookApiEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(accentGreen)
                    .onChange(of: hookApiEnabled) { _ in showRestartAlert = true }
            }

            if hookApiEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 12))
                    Text(zh
                        ? "开启后将授予 PTY 读写权限（仅本机访问）。请妥善保管 Token。"
                        : "Grants PTY read/write access via localhost. Keep your token secret.")
                        .font(.system(size: 11))
                        .foregroundColor(.orange.opacity(0.9))
                }
                .padding(.horizontal, 16).padding(.vertical, 8)

                Divider().padding(.horizontal, 16)

                SettingsRow(
                    label: zh ? "认证 Token" : "Auth Token",
                    description: zh ? "所有 API 请求必须携带此 Token" : "Required for all API requests"
                ) {
                    HStack(spacing: 8) {
                        Text(showToken ? hookApiToken : "••••••••••••••••")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(showToken ? 0.7 : 0.3))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 200, alignment: .trailing)

                        Button(showToken ? (zh ? "隐藏" : "Hide") : (zh ? "显示" : "Show")) {
                            showToken.toggle()
                        }
                        .buttonStyle(.bordered).controlSize(.mini)

                        Button(copied ? (zh ? "已复制" : "Copied") : (zh ? "复制" : "Copy")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(hookApiToken, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                        }
                        .buttonStyle(.bordered).controlSize(.mini)
                    }
                }

                SettingsRow(
                    label: zh ? "重新生成 Token" : "Regenerate Token",
                    description: zh ? "将使所有现有连接失效" : "Invalidates all existing connections",
                    showDivider: false
                ) {
                    Button(zh ? "重新生成" : "Regenerate") {
                        hookApiToken = AppDelegate.regenerateHookApiToken()
                        showRestartAlert = true
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(.orange)
                }

                Divider().padding(.horizontal, 16)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(zh ? "接口地址" : "Endpoint")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        Text("http://127.0.0.1:8767/api/v1/")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .alert(zh ? "需要重启" : "Restart Required", isPresented: $showRestartAlert) {
            Button(zh ? "立即重启" : "Restart Now") { AppDelegate.shared?.restartBackend() }
            Button(zh ? "稍后" : "Later", role: .cancel) {}
        } message: {
            Text(zh ? "更改需要重启服务端才能生效。" : "Changes require a server restart to take effect.")
        }
        .onAppear { hookApiToken = AppDelegate.getOrCreateHookApiToken() }

        // MARK: Automation
        desc(zh
            ? "让 Vibing 处理 Vibe Coding 中的重复操作。自动批准安全操作，不用反复输入 'y'；捕获失控的 Agent，避免浪费 API 额度；任务完成时立即收到通知。"
            : "Let Vibing handle the repetitive parts of Vibe Coding. Auto-approve safe operations so you don't have to type 'y' a hundred times, catch runaway agents before they waste your API credits, and get notified the moment a task finishes."
        )

        SettingsCard(title: zh ? "自动化" : "Automation", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(
                label: zh ? "智能自动批准" : "Smart Auto-Approve",
                description: zh ? "自动批准安全操作（读取文件、列目录），拦截危险操作" : "Auto-approve safe prompts (file reads, directory listings). Block dangerous operations."
            ) {
                Toggle("", isOn: $autoApprove)
                    .labelsHidden().toggleStyle(.switch).tint(accentGreen)
                    .disabled(!hookApiEnabled)
            }

            if autoApprove && hookApiEnabled {
                SettingsRow(
                    label: zh ? "  允许只读操作" : "  Allow read-only operations",
                    description: zh ? "读取文件、列出目录、搜索" : "File reads, directory listings, search"
                ) {
                    Toggle("", isOn: $autoApproveReadOnly)
                        .labelsHidden().toggleStyle(.switch).tint(accentGreen)
                }
                SettingsRow(
                    label: zh ? "  拦截危险操作" : "  Block dangerous operations",
                    description: zh ? "delete、rm -rf、force push、drop table" : "delete, rm -rf, force push, drop table"
                ) {
                    Toggle("", isOn: $autoApproveBlockDangerous)
                        .labelsHidden().toggleStyle(.switch).tint(accentGreen)
                }
            }

            Divider().padding(.horizontal, 16)

            SettingsRow(
                label: zh ? "失控 Agent 断路器" : "Runaway Agent Circuit Breaker",
                description: zh ? "检测到死循环时自动发送 Ctrl+C 终止 Agent" : "Auto-detect infinite loops and send Ctrl+C to stop the agent"
            ) {
                Toggle("", isOn: $circuitBreaker)
                    .labelsHidden().toggleStyle(.switch).tint(accentGreen)
                    .disabled(!hookApiEnabled)
            }

            if circuitBreaker && hookApiEnabled {
                SettingsRow(
                    label: zh ? "  循环检测阈值" : "  Loop detection threshold",
                    description: zh ? "检测到 N 次重复模式后发送 Ctrl+C" : "Send Ctrl+C after N repeated patterns"
                ) {
                    Picker("", selection: $circuitBreakerLoopCount) {
                        Text("3").tag(3)
                        Text("5").tag(5)
                        Text("10").tag(10)
                    }
                    .pickerStyle(.segmented).frame(width: 120)
                }
            }

            Divider().padding(.horizontal, 16)

            SettingsRow(
                label: zh ? "空闲通知" : "Idle Notifications",
                description: zh ? "Agent 进入空闲时发送通知（任务可能已完成）" : "Notify when an agent goes idle (task may be complete)",
                showDivider: false
            ) {
                Toggle("", isOn: $idleNotify)
                    .labelsHidden().toggleStyle(.switch).tint(accentGreen)
                    .disabled(!hookApiEnabled)
            }

            if !hookApiEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle").font(.system(size: 10))
                    Text(zh ? "请先开启上方的 Hook API 以使用自动化功能" : "Enable Hook API above to use automation features")
                        .font(.system(size: 11))
                }
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }

        // MARK: Security
        desc(zh
            ? "AI Agent 可能意外泄露密钥或产生异常输出。以下功能实时监控 PTY 数据流，在问题升级为事故之前及时捕获。"
            : "AI agents can accidentally leak secrets or produce unexpected output. These features monitor the PTY stream in real-time to catch issues before they become incidents."
        )

        SettingsCard(title: zh ? "安全" : "Security", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(
                label: zh ? "密钥泄露检测" : "Secret Leak Detector",
                description: zh ? "扫描终端输出中意外打印的 API Key、Token 和密码" : "Scan terminal output for accidentally printed API keys, tokens, and passwords"
            ) {
                Toggle("", isOn: $secretDetector)
                    .labelsHidden().toggleStyle(.switch).tint(accentGreen)
                    .disabled(!hookApiEnabled)
            }

            SettingsRow(
                label: zh ? "会话审计追踪" : "Session Audit Trail",
                description: zh ? "记录所有命令、输出和审批操作，带时间戳" : "Log all commands, outputs, and approvals with timestamps",
                showDivider: false
            ) {
                Toggle("", isOn: $sessionAudit)
                    .labelsHidden().toggleStyle(.switch).tint(accentGreen)
                    .disabled(!hookApiEnabled)
            }

            if !hookApiEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle").font(.system(size: 10))
                    Text(zh ? "请先开启上方的 Hook API 以使用安全功能" : "Enable Hook API above to use security features")
                        .font(.system(size: 11))
                }
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Advanced Settings

struct AdvancedSettings: View {
    let cardBg: SwiftUI.Color
    let borderColor: SwiftUI.Color

    @AppStorage("enableShellIntegration") private var shellIntegration = true
    @AppStorage("enableBellSound") private var bellSound = false
    @AppStorage("gpuRendering") private var gpuRendering = true
    @AppStorage("fps60Mode") private var fps60 = true
    private var zh: Bool { AppLanguage.current == .chinese }

    var body: some View {
        SettingsCard(title: zh ? "功能" : "Features", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "Shell 集成" : "Shell Integration", description: zh ? "启用 Shell 集成功能" : "Enable shell integration features") {
                Toggle("", isOn: $shellIntegration)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255))
            }

            SettingsRow(label: zh ? "响铃" : "Bell Sound", description: zh ? "终端响铃时播放声音" : "Play sound on terminal bell", showDivider: false) {
                Toggle("", isOn: $bellSound)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255))
            }
        }

        SettingsCard(title: zh ? "性能" : "Performance", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "GPU 渲染" : "GPU Rendering", description: zh ? "使用 Metal 渲染终端" : "Use Metal for terminal rendering") {
                Toggle("", isOn: $gpuRendering)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255))
            }

            SettingsRow(label: zh ? "60 帧模式" : "60 FPS Mode", description: zh ? "更高刷新率渲染" : "Higher refresh rate rendering", showDivider: false) {
                Toggle("", isOn: $fps60)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255))
            }
        }

        SettingsCard(title: zh ? "诊断" : "Diagnostics", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "查看日志" : "View Logs") {
                Button(zh ? "打开" : "Open") {
                    // TODO: open logs
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            SettingsRow(label: zh ? "导出配置" : "Export Configuration") {
                Button(zh ? "导出" : "Export") {
                    // TODO: export config
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            SettingsRow(label: zh ? "恢复默认" : "Reset to Defaults", description: zh ? "将所有设置恢复为默认值" : "Restore all settings to default values", showDivider: false) {
                Button(zh ? "重置" : "Reset") {
                    // TODO: reset settings
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
        }
    }
}

// MARK: - Sessions Settings

struct SessionsSettings: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var launchConfigManager: LaunchConfigManager
    let cardBg: SwiftUI.Color
    let borderColor: SwiftUI.Color
    let accentBlue: SwiftUI.Color

    @State private var newConfigName = ""
    @State private var showSaveField = false
    private var zh: Bool { AppLanguage.current == .chinese }

    var body: some View {
        SettingsCard(title: zh ? "保存当前布局" : "Save Current Layout", cardBg: cardBg, borderColor: borderColor) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(zh ? "保存当前窗口布局" : "Save your current window layout")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                        let paneCount = tabManager.tabs.reduce(0) { $0 + $1.splitLayout.paneIds.count }
                        Text(zh ? "\(tabManager.tabs.count) 个标签页, \(paneCount) 个面板" : "\(tabManager.tabs.count) tab(s), \(paneCount) pane(s)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Spacer()
                    if showSaveField {
                        HStack(spacing: 6) {
                            TextField(zh ? "配置名称" : "Config name", text: $newConfigName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .onSubmit { saveConfig() }
                            Button(zh ? "保存" : "Save") { saveConfig() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(accentBlue)
                                .disabled(newConfigName.isEmpty)
                        }
                    } else {
                        Button(zh ? "保存" : "Save") { showSaveField = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }

        SettingsCard(title: zh ? "已保存的配置" : "Saved Configurations", cardBg: cardBg, borderColor: borderColor) {
            if launchConfigManager.configurations.isEmpty {
                HStack {
                    Text(zh ? "没有已保存的配置" : "No saved configurations")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            } else {
                ForEach(Array(launchConfigManager.configurations.enumerated()), id: \.element.id) { index, config in
                    let isLast = index == launchConfigManager.configurations.count - 1
                    SettingsRow(label: config.name, description: zh ? "\(config.tabs.count) 个标签页" : "\(config.tabs.count) tab(s)", showDivider: !isLast) {
                        HStack(spacing: 8) {
                            Button(zh ? "恢复" : "Restore") {
                                launchConfigManager.restore(config, tabManager: tabManager)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(accentBlue)

                            Button(action: { launchConfigManager.delete(config.id) }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func saveConfig() {
        guard !newConfigName.isEmpty else { return }
        launchConfigManager.saveCurrentLayout(name: newConfigName, tabManager: tabManager)
        newConfigName = ""
        showSaveField = false
    }
}

// MARK: - About Settings

struct AboutSettings: View {
    let cardBg: SwiftUI.Color
    let borderColor: SwiftUI.Color
    let accentBlue: SwiftUI.Color

    private var zh: Bool { AppLanguage.current == .chinese }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 40))
                .foregroundColor(accentBlue)

            Text("Vibing")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Text(zh ? "跨平台终端共享" : "Cross-platform terminal sharing")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)

        SettingsCard(title: zh ? "信息" : "Info", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "版本" : "Version") {
                Text("0.0.1")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            SettingsRow(label: zh ? "构建日期" : "Build") {
                Text("2026.03.23")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            SettingsRow(label: zh ? "平台" : "Platform") {
                Text("macOS 13.0+")
                    .foregroundColor(.white.opacity(0.5))
            }

            SettingsRow(label: zh ? "渲染引擎" : "Renderer", showDivider: false) {
                Text("Metal GPU")
                    .foregroundColor(.white.opacity(0.5))
            }
        }

        SettingsCard(title: zh ? "组件" : "Components", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "客户端" : "Client", description: "Swift / SwiftUI + Metal") {
                Text("macOS")
                    .foregroundColor(.white.opacity(0.5))
            }

            SettingsRow(label: zh ? "服务器" : "Server", description: "Rust / Tokio + tungstenite") {
                Text("vibing-server")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            SettingsRow(label: zh ? "中继" : "Relay", description: zh ? "端到端加密中继" : "End-to-end encrypted relay", showDivider: false) {
                Text("vibing-relay")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - Account Settings

struct AccountSettings: View {
    let cardBg: SwiftUI.Color
    let borderColor: SwiftUI.Color
    let accentBlue: SwiftUI.Color

    @ObservedObject private var accountManager = AccountManager.shared

    @State private var usernameField = ""
    @State private var passwordField = ""
    @State private var isRegistering = false
    @State private var showError = false
    @State private var errorText = ""
    @State private var qrCodeField = ""
    @State private var relayURL: String = UserDefaults.standard.string(forKey: "relayServerURL") ?? ""

    private var zh: Bool { AppLanguage.current == .chinese }

    var body: some View {
        if accountManager.isSignedIn {
            signedInView
        } else {
            signedOutView
        }
    }

    // MARK: - Signed In

    private var signedInView: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(title: zh ? "个人资料" : "Profile", cardBg: cardBg, borderColor: borderColor) {
                SettingsRow(label: zh ? "用户名" : "Username") {
                    Text(accountManager.username ?? "—")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }

                SettingsRow(label: zh ? "账号 ID" : "Account ID") {
                    Text(accountManager.accountId ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                SettingsRow(label: zh ? "退出登录" : "Sign Out", showDivider: false) {
                    Button(zh ? "退出登录" : "Sign Out") {
                        accountManager.signOut()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }

            SettingsCard(title: zh ? "QR 登录" : "QR Login", cardBg: cardBg, borderColor: borderColor) {
                VStack(spacing: 12) {
                    if let qrImage = accountManager.qrCodeImage {
                        HStack {
                            Spacer()
                            Image(nsImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 160, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Spacer()
                        }

                        Text(zh ? "用另一台设备扫码登录" : "Scan with another device to login")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(zh ? "扫码让其他设备登录" : "Let other devices login by scanning")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.7))
                                Text(zh ? "二维码 5 分钟后过期" : "QR code expires in 5 minutes")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                            Spacer()
                            Button(zh ? "生成二维码" : "Generate QR") {
                                Task {
                                    try? await accountManager.generateLoginQR()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(accentBlue)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            SettingsCard(title: zh ? "设备" : "Devices", cardBg: cardBg, borderColor: borderColor) {
                if accountManager.devices.isEmpty {
                    HStack {
                        Text(zh ? "暂无已注册设备" : "No devices registered")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Button(zh ? "刷新" : "Refresh") {
                            Task {
                                try? await accountManager.fetchDevices()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                } else {
                    ForEach(Array(accountManager.devices.enumerated()), id: \.element.id) { index, device in
                        let isLast = index == accountManager.devices.count - 1
                        deviceRow(device, showDivider: !isLast)
                    }
                }
            }

            // Refresh button
            HStack {
                Spacer()
                Button(action: {
                    Task {
                        try? await accountManager.fetchDevices()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text(AppLanguage.current == .chinese ? "刷新设备" : "Refresh Devices")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Network / Relay
            networkSettingsCard
        }
    }

    // MARK: - Network Settings (inside Account)

    private var networkSettingsCard: some View {
        let zh = AppLanguage.current == .chinese
        return SettingsCard(title: zh ? "网络" : "Network", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: zh ? "中继服务器" : "Relay Server", description: zh ? "用于多设备终端共享" : "For multi-device terminal sharing") {
                TextField("", text: $relayURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit {
                        UserDefaults.standard.set(relayURL, forKey: "relayServerURL")
                    }
            }

            // 本地服务器信息不展示给用户
        }
    }

    private func deviceRow(_ device: DeviceInfo, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Device icon
                Image(systemName: device.typeIcon)
                    .font(.system(size: 16))
                    .foregroundColor(device.is_online ? accentBlue : .white.opacity(0.3))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))

                        // Online indicator
                        Circle()
                            .fill(device.is_online ? SwiftUI.Color.green : SwiftUI.Color.gray.opacity(0.4))
                            .frame(width: 6, height: 6)

                        Text(device.is_online ? "Online" : "Offline")
                            .font(.system(size: 10))
                            .foregroundColor(device.is_online ? .green : .white.opacity(0.3))
                    }

                    Text(device.displayType)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                // Remove button
                Button(action: {
                    Task {
                        try? await accountManager.removeDevice(device.id)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showDivider {
                Rectangle()
                    .fill(SwiftUI.Color.white.opacity(0.04))
                    .frame(height: 0.5)
                    .padding(.leading, 50)
            }
        }
    }

    // MARK: - Signed Out (Login / Register)

    private var signedOutView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Step 1: Network settings (must configure first)
            networkSettingsCard

            // Step 2: Login / Register
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(accentBlue)

                Text(isRegistering ? (zh ? "创建账号" : "Create Account") : (zh ? "登录" : "Sign In"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                Text(zh ? "连接设备，共享终端会话" : "Connect your devices for terminal sharing")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            SettingsCard(title: isRegistering ? (zh ? "注册" : "Register") : (zh ? "登录" : "Login"), cardBg: cardBg, borderColor: borderColor) {
                VStack(spacing: 0) {
                    HStack {
                        Text(zh ? "用户名" : "Username")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 80, alignment: .leading)
                        TextField("", text: $usernameField)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Rectangle()
                        .fill(SwiftUI.Color.white.opacity(0.04))
                        .frame(height: 0.5)
                        .padding(.leading, 14)

                    HStack {
                        Text(zh ? "密码" : "Password")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 80, alignment: .leading)
                        SecureField("", text: $passwordField)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Rectangle()
                        .fill(SwiftUI.Color.white.opacity(0.04))
                        .frame(height: 0.5)
                        .padding(.leading, 14)

                    // Error message
                    if showError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                            Text(errorText)
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.9))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }

                    // Submit button
                    HStack {
                        Spacer()

                        if accountManager.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .padding(.trailing, 8)
                        }

                        Button(action: submitForm) {
                            Text(isRegistering ? (zh ? "创建账号" : "Create Account") : (zh ? "登录" : "Sign In"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .tint(accentBlue)
                        .disabled(usernameField.isEmpty || passwordField.isEmpty || accountManager.isLoading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }

            // Toggle login/register
            HStack {
                Spacer()
                Text(isRegistering ? (zh ? "已有账号？" : "Already have an account?") : (zh ? "没有账号？" : "Don't have an account?"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                Button(isRegistering ? (zh ? "登录" : "Sign In") : (zh ? "注册" : "Register")) {
                    isRegistering.toggle()
                    showError = false
                    errorText = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(accentBlue)
                Spacer()
            }
            .padding(.top, 12)

            // QR code login
            if !isRegistering {
                // Divider
                HStack {
                    Rectangle().fill(SwiftUI.Color.white.opacity(0.08)).frame(height: 0.5)
                    Text("OR")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                    Rectangle().fill(SwiftUI.Color.white.opacity(0.08)).frame(height: 0.5)
                }
                .padding(.top, 16)
                .padding(.bottom, 12)

                SettingsCard(title: zh ? "二维码登录" : "QR Code Login", cardBg: cardBg, borderColor: borderColor) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("QR Code")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 80, alignment: .leading)
                            TextField(zh ? "粘贴二维码值" : "Paste QR code value", text: $qrCodeField)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        HStack {
                            Text(zh ? "从已登录设备扫描二维码" : "Scan the QR code from a logged-in device")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                            Spacer()
                            Button(zh ? "扫码登录" : "Login with QR") {
                                submitQRLogin()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(accentBlue)
                            .disabled(qrCodeField.isEmpty || accountManager.isLoading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func submitForm() {
        showError = false
        Task {
            do {
                if isRegistering {
                    try await accountManager.register(username: usernameField, password: passwordField)
                } else {
                    try await accountManager.login(username: usernameField, password: passwordField)
                }
                await MainActor.run {
                    usernameField = ""
                    passwordField = ""
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func submitQRLogin() {
        showError = false
        Task {
            do {
                try await accountManager.qrLogin(code: qrCodeField)
                await MainActor.run {
                    qrCodeField = ""
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
