//
//  OnboardingView.swift
//  Vibing
//
//  首次使用引导 — 语言、Shell 选择、账号设置
//

import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var isCompleted: Bool

    @State private var currentPage = 0
    @State private var language: AppLanguage = AppLanguage.current

    private let totalPages = 3

    private let bgColor = SwiftUI.Color(red: 22/255, green: 21/255, blue: 20/255)
    private let cardBg = SwiftUI.Color(red: 32/255, green: 30/255, blue: 28/255)
    private let accent = SwiftUI.Color(red: 130/255, green: 200/255, blue: 130/255)

    var zh: Bool { language == .chinese }

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    HStack(spacing: 2) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                            Button(action: {
                                language = lang
                                AppLanguage.current = lang
                            }) {
                                Text(lang.displayName)
                                    .font(.system(size: 12, weight: language == lang ? .semibold : .regular))
                                    .foregroundColor(language == lang ? accent : .white.opacity(0.4))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(language == lang ? accent.opacity(0.12) : .clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    if currentPage < totalPages - 1 {
                        Button(zh ? "跳过" : "Skip") {
                            completeOnboarding()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)

                Spacer()

                // Page content — centered with max width
                Group {
                    switch currentPage {
                    case 0: welcomePage
                    case 1: environmentPage
                    case 2: readyPage
                    default: welcomePage
                    }
                }
                .frame(maxWidth: 520)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                Spacer()

                // Bottom
                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == currentPage ? accent : SwiftUI.Color.white.opacity(0.15))
                                .frame(width: i == currentPage ? 24 : 7, height: 7)
                                .animation(.easeInOut, value: currentPage)
                        }
                    }

                    Button(action: handleNext) {
                        Text(currentPage == totalPages - 1
                             ? (zh ? "开始使用" : "Get Started")
                             : (zh ? "继续" : "Continue"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 240, height: 44)
                            .background(accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 36)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "terminal.fill")
                    .font(.system(size: 50))
                    .foregroundColor(accent)
            }

            VStack(spacing: 10) {
                Text("Vibing")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white)

                Text(zh ? "多设备终端同步" : "Multi-device Terminal Sharing")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
            }

            VStack(spacing: 18) {
                featureItem(icon: "arrow.triangle.2.circlepath",
                           text: zh ? "跨设备共享终端会话" : "Share terminal sessions across devices")
                featureItem(icon: "lock.shield.fill",
                           text: zh ? "端到端加密，安全私密" : "End-to-end encrypted, secure & private")
                featureItem(icon: "bolt.fill",
                           text: zh ? "Metal GPU 加速渲染" : "Metal GPU accelerated rendering")
            }
            .padding(.top, 4)
        }
    }

    private func featureItem(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(accent)
                .frame(width: 32, height: 32)
                .background(accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
        }
    }

    // MARK: - Page 1: Shell Selection

    @ObservedObject private var shellDetector = ShellDetector.shared

    private var environmentPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 40))
                .foregroundColor(accent)

            VStack(spacing: 8) {
                Text(zh ? "选择 Shell" : "Choose Shell")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                Text(zh ? "选择你常用的 Shell 作为默认终端" : "Pick your preferred shell as default terminal")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Shell list
            VStack(spacing: 0) {
                ForEach(Array(shellDetector.availableShells.enumerated()), id: \.element.id) { index, shell in
                    shellRow(shell: shell, isLast: index == shellDetector.availableShells.count - 1)
                }
            }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SwiftUI.Color.white.opacity(0.06), lineWidth: 0.5)
            )

            if shellDetector.availableShells.isEmpty {
                Text(zh ? "正在检测..." : "Detecting...")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    private func shellRow(shell: DetectedShell, isLast: Bool) -> some View {
        let isSelected = shellDetector.selectedShellPath == shell.path

        return VStack(spacing: 0) {
            Button(action: {
                shellDetector.selectedShellPath = shell.path
            }) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(isSelected ? accent : SwiftUI.Color.white.opacity(0.2), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                        if isSelected {
                            Circle()
                                .fill(accent)
                                .frame(width: 11, height: 11)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(shell.name)
                                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.7))

                            if shell.isDefault {
                                Text(zh ? "系统默认" : "default")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(accent.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }

                        Text(shell.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }

                    Spacer()

                    if !shell.version.isEmpty {
                        let ver = String(shell.version.components(separatedBy: "\n").first?.prefix(30) ?? "")
                        Text(ver)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.2))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isSelected ? accent.opacity(0.06) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isLast {
                Rectangle().fill(SwiftUI.Color.white.opacity(0.05)).frame(height: 0.5).padding(.leading, 50)
            }
        }
    }

    // MARK: - Page 2: Account

    @State private var username = ""
    @State private var password = ""
    @State private var relayURL = UserDefaults.standard.string(forKey: "relayServerURL") ?? "http://127.0.0.1:8766"
    @State private var isRegistering = false
    @State private var isLoading = false
    @State private var accountError = ""
    @State private var accountSuccess = false

    private var accountPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(accent)

            VStack(spacing: 8) {
                Text(zh ? "账号设置" : "Account Setup")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                Text(zh ? "登录后自动同步终端到移动设备" : "Sign in to sync terminals to mobile devices")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }

            if accountSuccess {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                    Text(zh ? "登录成功！" : "Signed in!")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                }
            } else {
                // Form card
                VStack(spacing: 0) {
                    formRow(label: zh ? "服务器" : "Server") {
                        TextField("", text: $relayURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                            .onSubmit {
                                UserDefaults.standard.set(relayURL, forKey: "relayServerURL")
                            }
                    }

                    formDivider

                    formRow(label: zh ? "用户名" : "Username") {
                        TextField("", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    }

                    formDivider

                    formRow(label: zh ? "密码" : "Password") {
                        SecureField("", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    }

                    formDivider

                    // Action row
                    HStack {
                        Button(isRegistering
                               ? (zh ? "已有账号？登录" : "Have account? Sign In")
                               : (zh ? "没有账号？注册" : "No account? Register")) {
                            isRegistering.toggle()
                            accountError = ""
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(accent)

                        Spacer()

                        if isLoading {
                            ProgressView().scaleEffect(0.7)
                        }

                        Button(isRegistering ? (zh ? "注册" : "Register") : (zh ? "登录" : "Sign In")) {
                            performAuth()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .tint(accent)
                        .disabled(username.isEmpty || password.isEmpty || isLoading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(SwiftUI.Color.white.opacity(0.06), lineWidth: 0.5)
                )

                if !accountError.isEmpty {
                    Text(accountError)
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }

                Text(zh ? "也可以稍后在设置中配置" : "You can also set this up later in Settings")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    private var formDivider: some View {
        Rectangle().fill(SwiftUI.Color.white.opacity(0.05)).frame(height: 0.5).padding(.leading, 16)
    }

    private func formRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 70, alignment: .leading)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func performAuth() {
        isLoading = true
        accountError = ""

        Task {
            do {
                if isRegistering {
                    try await AccountManager.shared.register(username: username, password: password)
                } else {
                    try await AccountManager.shared.login(username: username, password: password)
                }
                await MainActor.run {
                    isLoading = false
                    accountSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    accountError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Page 3: Ready

    private var readyPage: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(accent)
            }

            Text(zh ? "一切就绪！" : "All Set!")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 14) {
                readyItem(icon: "terminal",
                          text: "Shell: \(ShellDetector.shared.effectiveShellName) (\(ShellDetector.shared.effectiveShell))")

                if AccountManager.shared.isSignedIn {
                    readyItem(icon: "person.fill.checkmark",
                              text: zh ? "已登录: \(AccountManager.shared.username ?? "")" : "Signed in: \(AccountManager.shared.username ?? "")")
                    readyItem(icon: "antenna.radiowaves.left.and.right",
                              text: zh ? "终端将自动共享到移动设备" : "Terminals auto-shared to mobile")
                } else {
                    readyItem(icon: "person.fill.xmark",
                              text: zh ? "未登录（可稍后在设置中配置）" : "Not signed in (configure in Settings)")
                }
            }
        }
    }

    private func readyItem(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(accent.opacity(0.7))
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
    }

    // MARK: - Actions

    private func handleNext() {
        if currentPage < totalPages - 1 {
            withAnimation { currentPage += 1 }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        isCompleted = true
    }
}
