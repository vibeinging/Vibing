//
//  ContentView.swift
//  VibeTerminal
//
//  主界面 - 终端显示
//

import SwiftUI

struct ContentView: View {
    @StateObject private var accountManager = AccountManager.shared
    @State private var showPairingCode = false

    var body: some View {
        Group {
            if accountManager.isSignedIn {
                mainContent
            } else {
                OnboardingView()
            }
        }
        .sheet(isPresented: $showPairingCode) {
            PairingCodeView()
        }
    }

    private var mainContent: some View {
        HSplitView {
            // 左侧：终端列表
            SidebarView()
                .frame(minWidth: 200, idealWidth: 250)

            // 右侧：终端内容
            TerminalContentView()
                .frame(minWidth: 400)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    // 连接状态
                    ConnectionStatusIndicator()

                    // 配对按钮
                    Button {
                        showPairingCode = true
                    } label: {
                        Image(systemName: "qrcode")
                    }
                    .help("Show Pairing Code")

                    // 设置
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
            }
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @StateObject private var accountManager = AccountManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // 账户信息
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountManager.accountName ?? "Vibe User")
                        .font(.headline)
                    Text(accountManager.accountId ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 设备列表
            if accountManager.pairedDevices.isEmpty {
                VStack {
                    Spacer()
                    Text("No paired devices")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Scan QR code to connect")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                    Spacer()
                }
            } else {
                List(accountManager.pairedDevices) { device in
                    DeviceRow(device: device)
                }
            }

            Divider()

            // 新建终端按钮
            Button {
                // TODO: 创建新终端会话
            } label: {
                Label("New Terminal", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding()
        }
    }
}

struct DeviceRow: View {
    let device: DeviceInfo

    var body: some View {
        HStack {
            Image(systemName: deviceIcon)
                .foregroundColor(device.isOnline ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                Text(deviceTypeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if device.isOnline {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
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

    private var deviceTypeString: String {
        switch device.type {
        case .mac: return "Mac"
        case .ios: return "iOS"
        case .android: return "Android"
        case .web: return "Web"
        }
    }
}

// MARK: - Terminal Content View

struct TerminalContentView: View {
    var body: some View {
        ZStack {
            Color.black

            VStack {
                Spacer()

                HStack {
                    Spacer()
                    Text("Vibing v0.0.1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Connection Status Indicator

struct ConnectionStatusIndicator: View {
    @State private var isConnected = true

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(isConnected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            // TODO: 实际连接状态检测
        }
    }
}

// MARK: - Pairing Code View

struct PairingCodeView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var accountManager = AccountManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Text("Pair New Device")
                .font(.title)
                .bold()

            Text("Scan this QR code with another device to connect")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // 二维码
            if let qrImage = accountManager.qrCodeImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .frame(width: 200, height: 200)
            } else {
                Button("Generate QR Code") {
                    let _ = accountManager.generatePairingCode()
                }
            }

            // 配对码文本
            if let code = accountManager.pairingCode {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }

            // 待处理的配对请求
            if !accountManager.pendingRequests.isEmpty {
                Divider()
                    .padding(.vertical)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pending Requests")
                        .font(.headline)

                    ForEach(accountManager.pendingRequests) { request in
                        PendingRequestRow(request: request)
                    }
                }
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: 350, height: 500)
        .padding()
        .onAppear {
            if accountManager.qrCodeImage == nil {
                let _ = accountManager.generatePairingCode()
            }
        }
    }
}

struct PendingRequestRow: View {
    let request: PairingRequest
    @StateObject private var accountManager = AccountManager.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.deviceName)
                    .font(.body)
                Text(deviceTypeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Accept") {
                    Task {
                        try? await accountManager.acceptPairingRequest(request)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Decline") {
                    Task {
                        try? await accountManager.rejectPairingRequest(request)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var deviceTypeString: String {
        switch request.deviceType {
        case .mac: return "Mac"
        case .ios: return "iPhone/iPad"
        case .android: return "Android"
        case .web: return "Web Browser"
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
