//
//  SettingsView.swift
//  VibeTerminal
//
//  设置界面
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var accountManager = AccountManager.shared
    @State private var selectedTab: SettingsTab = .account

    enum SettingsTab: String, CaseIterable {
        case account = "Account"
        case devices = "Devices"
        case appearance = "Appearance"
        case terminal = "Terminal"
        case advanced = "Advanced"
    }

    var body: some View {
        NavigationSplitView {
            // 侧边栏
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tabIcon)
            }
            .frame(minWidth: 150, maxWidth: 200)
        } detail: {
            // 内容区域
            Group {
                switch selectedTab {
                case .account:
                    AccountSettingsView()
                case .devices:
                    DevicesSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .terminal:
                    TerminalSettingsView()
                case .advanced:
                    AdvancedSettingsView()
                }
            }
            .frame(minWidth: 400, minHeight: 300)
            .padding()
        }
    }

    private var tabIcon: String {
        switch selectedTab {
        case .account: return "person.circle"
        case .devices: return "iphone"
        case .appearance: return "paintbrush"
        case .terminal: return "terminal"
        case .advanced: return "gearshape.2"
        }
    }
}

// MARK: - Account Settings View

struct AccountSettingsView: View {
    @StateObject private var accountManager = AccountManager.shared
    @State private var showQRCode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Account")
                .font(.title)
                .bold()

            // 账户信息
            GroupBox("Your Account") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Name:")
                            .foregroundColor(.secondary)
                        Text(accountManager.accountName ?? "Unknown")
                    }

                    HStack {
                        Text("Account ID:")
                            .foregroundColor(.secondary)
                        Text(accountManager.accountId ?? "Unknown")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }

            // 配对选项
            GroupBox("Device Pairing") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect other devices by scanning a QR code")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    HStack(spacing: 12) {
                        Button("Show QR Code") {
                            showQRCode = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Scan QR Code") {
                            // TODO: 打开扫描器
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    Text("Paired Devices (\(accountManager.pairedDevices.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if accountManager.pairedDevices.isEmpty {
                        Text("No devices paired yet")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(accountManager.pairedDevices) { device in
                            PairedDeviceRow(device: device)
                        }
                    }
                }
            }

            Spacer()

            // 登出
            HStack {
                Spacer()
                Button("Sign Out") {
                    accountManager.signOut()
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showQRCode) {
            PairingCodeView()
        }
    }
}

struct PairedDeviceRow: View {
    let device: DeviceInfo
    @StateObject private var accountManager = AccountManager.shared

    var body: some View {
        HStack {
            Image(systemName: deviceIcon)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                Text("Paired \(device.pairedAt, style: .relative) • Last seen \(device.lastSeen, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if device.isOnline {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }

            Button {
                Task {
                    try? await accountManager.removePairedDevice(device.id)
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove Device")
        }
        .padding(.vertical, 4)
    }

    private var deviceIcon: String {
        switch device.type {
        case .mac: return "desktopcomputer"
        case .ios: return "iphone"
        case .android: return "appletv"
        case .web: return "globe"
        }
    }
}

// MARK: - Devices Settings View

struct DevicesSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Devices")
                .font(.title)
                .bold()

            Text("Manage your connected devices")
                .foregroundColor(.secondary)

            // TODO: 设备管理界面
        }
    }
}

// MARK: - Appearance Settings View

struct AppearanceSettingsView: View {
    @AppStorage("terminalFontSize") private var fontSize: Double = 14
    @AppStorage("terminalFont") private var selectedFont = "SF Mono"
    @AppStorage("terminalTheme") private var selectedTheme = "Dark"

    let fonts = ["SF Mono", "Menlo", "Monaco", "Consolas", "Courier New"]
    let themes = ["Dark", "Light", "Solarized Dark", "Solarized Light", "Dracula", "Nord"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance")
                .font(.title)
                .bold()

            // 字体设置
            GroupBox("Font") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Font Family:")
                            .frame(width: 100, alignment: .leading)
                        Picker("", selection: $selectedFont) {
                            ForEach(fonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("Font Size:")
                            .frame(width: 100, alignment: .leading)
                        Slider(value: $fontSize, in: 10...24, step: 1) {
                            Text("\(Int(fontSize))pt")
                        }
                    }

                    // 预览
                    Text("Preview: The quick brown fox jumps over the lazy dog")
                        .font(.system(size: CGFloat(fontSize), design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                }
            }

            // 主题设置
            GroupBox("Theme") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(themes, id: \.self) { theme in
                        HStack {
                            Text(theme)
                                .frame(width: 150, alignment: .leading)
                            Spacer()
                            if selectedTheme == theme {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedTheme = theme
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Terminal Settings View

struct TerminalSettingsView: View {
    @AppStorage("terminalCols") private var cols: Double = 80
    @AppStorage("terminalRows") private var rows: Double = 24
    @AppStorage("scrollbackSize") private var scrollback: Double = 10000
    @AppStorage("cursorBlink") private var cursorBlink = true
    @AppStorage("cursorStyle") private var cursorStyle = "block"

    let cursorStyles = ["block", "underline", "bar"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Terminal")
                .font(.title)
                .bold()

            // 窗口大小
            GroupBox("Default Window Size") {
                HStack {
                    Text("Columns:")
                        .frame(width: 100, alignment: .leading)
                    Slider(value: $cols, in: 40...160, step: 1) {
                        Text("\(Int(cols))")
                    }
                }

                HStack {
                    Text("Rows:")
                        .frame(width: 100, alignment: .leading)
                    Slider(value: $rows, in: 10...60, step: 1) {
                        Text("\(Int(rows))")
                    }
                }
            }

            // 滚动
            GroupBox("Scrollback") {
                HStack {
                    Text("Lines:")
                        .frame(width: 100, alignment: .leading)
                    Slider(value: $scrollback, in: 0...50000, step: 1000) {
                        Text("\(Int(scrollback))")
                    }

                    if scrollback == 0 {
                        Text("(disabled)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }

            // 光标
            GroupBox("Cursor") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Blinking Cursor", isOn: $cursorBlink)

                    HStack {
                        Text("Style:")
                            .frame(width: 100, alignment: .leading)
                        Picker("", selection: $cursorStyle) {
                            ForEach(cursorStyles, id: \.self) { style in
                                Text(style.capitalized).tag(style)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }
}

// MARK: - Advanced Settings View

struct AdvancedSettingsView: View {
    @AppStorage("enableShellIntegration") private var shellIntegration = true
    @AppStorage("enableBellSound") private var bellSound = false
    @AppStorage("enableUnicodeNormalization") private var unicodeNormalization = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Advanced")
                .font(.title)
                .bold()

            GroupBox("Features") {
                Toggle("Shell Integration", isOn: $shellIntegration)
                Divider()
                Toggle("Bell Sound", isOn: $bellSound)
                Divider()
                Toggle("Unicode Normalization", isOn: $unicodeNormalization)
            }

            GroupBox("Backend") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Status:")
                        Text("Running")
                            .foregroundColor(.green)
                        Spacer()
                        Button("Restart") {
                            // TODO: 重启后端
                        }
                    }

                    HStack {
                        Text("Port:")
                        Text("8765")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Version:")
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }

            GroupBox("Diagnostics") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("View Logs") {
                        // TODO: 打开日志
                    }

                    Button("Export Configuration") {
                        // TODO: 导出配置
                    }

                    Button("Reset to Defaults") {
                        // TODO: 重置设置
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
