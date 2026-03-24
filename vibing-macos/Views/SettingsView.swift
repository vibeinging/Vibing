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
        .frame(width: 780, height: 540)
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

    var body: some View {
        // Theme
        SettingsCard(title: "Theme", cardBg: cardBg, borderColor: borderColor) {
            themeGrid
        }

        // Font
        SettingsCard(title: "Font", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "Font Family", description: "Monospace font for terminal") {
                Picker("", selection: $selectedFont) {
                    ForEach(fonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            SettingsRow(label: "Font Size", description: "\(Int(fontSize))pt", showDivider: false) {
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
        SettingsCard(title: "Preview", cardBg: cardBg, borderColor: borderColor) {
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
        SettingsCard(title: "Panes", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "Dim Inactive Panes", description: "Darken non-focused panes in split view") {
                Toggle("", isOn: $dimInactivePanes)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentBlue)
            }

            SettingsRow(label: "Focus Follows Mouse", description: "Activate pane on mouse hover", showDivider: false) {
                Toggle("", isOn: $focusFollowsMouse)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentBlue)
            }
        }

        // Window
        SettingsCard(title: "Window", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "Background Opacity", description: "\(Int(themeManager.currentTheme.backgroundOpacity * 100))%", showDivider: false) {
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

    var body: some View {
        SettingsCard(title: "Shell", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "Default Shell") {
                Picker("", selection: $shellDetector.selectedShellPath) {
                    ForEach(shellDetector.availableShells) { shell in
                        HStack(spacing: 6) {
                            Text(shell.name)
                                .font(.system(size: 13))
                            if shell.isDefault {
                                Text("system")
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
                SettingsRow(label: "Path", description: selected.path) {
                    EmptyView()
                }

                if !selected.version.isEmpty {
                    SettingsRow(label: "Version", description: selected.version) {
                        EmptyView()
                    }
                }
            }

            SettingsRow(label: "Working Directory", showDivider: false) {
                Text("~")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }

        // 检测到的所有 Shell 列表
        SettingsCard(title: "Available Shells (\(shellDetector.availableShells.count))", cardBg: cardBg, borderColor: borderColor) {
            ForEach(Array(shellDetector.availableShells.enumerated()), id: \.element.id) { index, shell in
                let isLast = index == shellDetector.availableShells.count - 1
                SettingsRow(
                    label: shell.name,
                    description: shell.path,
                    showDivider: !isLast
                ) {
                    HStack(spacing: 8) {
                        if shell.isDefault {
                            Text("Default")
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
                            Button("Use") {
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
                    Text("Detecting shells...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }

        SettingsCard(title: "Cursor", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "Cursor Style") {
                Picker("", selection: $cursorStyle) {
                    Text("Block").tag("block")
                    Text("Underline").tag("underline")
                    Text("Bar").tag("bar")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            SettingsRow(label: "Blinking Cursor", showDivider: false) {
                Toggle("", isOn: $cursorBlink)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentBlue)
            }
        }

        SettingsCard(title: "Display", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "Default Columns", description: "\(Int(cols))") {
                Slider(value: $cols, in: 40...200, step: 1)
                    .frame(width: 140)
            }

            SettingsRow(label: "Default Rows", description: "\(Int(rows))") {
                Slider(value: $rows, in: 10...80, step: 1)
                    .frame(width: 140)
            }

            SettingsRow(label: "Scrollback Lines", description: scrollback == 0 ? "Disabled" : "\(Int(scrollback))", showDivider: false) {
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

    var body: some View {
        SettingsCard(title: "General", cardBg: cardBg, borderColor: borderColor) {
            keybindingRow("New Tab", shortcut: "Cmd + T")
            keybindingRow("Close Tab", shortcut: "Cmd + W")
            keybindingRow("Settings", shortcut: "Cmd + ,")
            keybindingRow("Command Palette", shortcut: "Cmd + K")
            keybindingRow("Find", shortcut: "Cmd + F", showDivider: false)
        }

        SettingsCard(title: "Split Panes", cardBg: cardBg, borderColor: borderColor) {
            keybindingRow("Split Horizontal", shortcut: "Cmd + D")
            keybindingRow("Split Vertical", shortcut: "Cmd + Shift + D")
            keybindingRow("Next Pane", shortcut: "Cmd + ]")
            keybindingRow("Previous Pane", shortcut: "Cmd + [")
            keybindingRow("Maximize Pane", shortcut: "Shift + Cmd + Enter", showDivider: false)
        }

        SettingsCard(title: "Navigation", cardBg: cardBg, borderColor: borderColor) {
            keybindingRow("Navigate Up", shortcut: "Alt + Cmd + Up")
            keybindingRow("Navigate Down", shortcut: "Alt + Cmd + Down")
            keybindingRow("Navigate Left", shortcut: "Alt + Cmd + Left")
            keybindingRow("Navigate Right", shortcut: "Alt + Cmd + Right", showDivider: false)
        }

        SettingsCard(title: "Resize", cardBg: cardBg, borderColor: borderColor) {
            keybindingRow("Resize Up", shortcut: "Ctrl + Cmd + Up")
            keybindingRow("Resize Down", shortcut: "Ctrl + Cmd + Down")
            keybindingRow("Resize Left", shortcut: "Ctrl + Cmd + Left")
            keybindingRow("Resize Right", shortcut: "Ctrl + Cmd + Right", showDivider: false)
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

    @AppStorage("relayServerURL") private var relayURL = "http://127.0.0.1:8766"

    var body: some View {
        SettingsCard(title: "Backend Server", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "Server Address") {
                Text("127.0.0.1:8765")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            SettingsRow(label: "Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(SwiftUI.Color.green)
                        .frame(width: 6, height: 6)
                    Text("Running")
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                }
            }

            SettingsRow(label: "Restart Server", showDivider: false) {
                Button("Restart") {
                    // TODO: restart backend
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

        SettingsCard(title: "Relay", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "Relay Server", description: "End-to-end encrypted relay") {
                TextField("", text: $relayURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .font(.system(size: 12, design: .monospaced))
            }

            SettingsRow(label: "Encryption", showDivider: false) {
                Text("AES-256-GCM")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
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

    var body: some View {
        SettingsCard(title: "Features", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "Shell Integration", description: "Enable shell integration features") {
                Toggle("", isOn: $shellIntegration)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255))
            }

            SettingsRow(label: "Bell Sound", description: "Play sound on terminal bell", showDivider: false) {
                Toggle("", isOn: $bellSound)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255))
            }
        }

        SettingsCard(title: "Performance", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "GPU Rendering", description: "Use Metal for terminal rendering") {
                Toggle("", isOn: $gpuRendering)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255))
            }

            SettingsRow(label: "60 FPS Mode", description: "Higher refresh rate rendering", showDivider: false) {
                Toggle("", isOn: $fps60)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255))
            }
        }

        SettingsCard(title: "Diagnostics", cardBg: cardBg, borderColor: borderColor) {
            SettingsRow(label: "View Logs") {
                Button("Open") {
                    // TODO: open logs
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            SettingsRow(label: "Export Configuration") {
                Button("Export") {
                    // TODO: export config
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            SettingsRow(label: "Reset to Defaults", description: "Restore all settings to default values", showDivider: false) {
                Button("Reset") {
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

    var body: some View {
        SettingsCard(title: "Save Current Layout", cardBg: cardBg, borderColor: borderColor) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save your current window layout")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                        let paneCount = tabManager.tabs.reduce(0) { $0 + $1.splitLayout.paneIds.count }
                        Text("\(tabManager.tabs.count) tab(s), \(paneCount) pane(s)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Spacer()
                    if showSaveField {
                        HStack(spacing: 6) {
                            TextField("Config name", text: $newConfigName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .onSubmit { saveConfig() }
                            Button("Save") { saveConfig() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(accentBlue)
                                .disabled(newConfigName.isEmpty)
                        }
                    } else {
                        Button("Save") { showSaveField = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }

        SettingsCard(title: "Saved Configurations", cardBg: cardBg, borderColor: borderColor) {
            if launchConfigManager.configurations.isEmpty {
                HStack {
                    Text("No saved configurations")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            } else {
                ForEach(Array(launchConfigManager.configurations.enumerated()), id: \.element.id) { index, config in
                    let isLast = index == launchConfigManager.configurations.count - 1
                    SettingsRow(label: config.name, description: "\(config.tabs.count) tab(s)", showDivider: !isLast) {
                        HStack(spacing: 8) {
                            Button("Restore") {
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
    @State private var relayURL: String = UserDefaults.standard.string(forKey: "relayServerURL") ?? "http://127.0.0.1:8766"

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

            SettingsRow(label: zh ? "本地服务器" : "Local Server", description: zh ? "终端后端服务" : "Terminal backend", showDivider: false) {
                Text("ws://127.0.0.1:8765")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
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
