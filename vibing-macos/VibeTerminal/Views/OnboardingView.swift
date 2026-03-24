//
//  OnboardingView.swift
//  Vibing
//
//  用户引导界面 - 支持多语言
//

import SwiftUI

// MARK: - 语言支持

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .chinese: return "🇨🇳"
        }
    }
}

// MARK: - 本地化字符串

struct LocalizedStrings {
    let appName: String
    let appTagline: String
    let welcomeTitle: String
    let welcomeSubtitle: String
    let feature1Title: String
    let feature1Desc: String
    let feature2Title: String
    let feature2Desc: String
    let feature3Title: String
    let feature3Desc: String
    let nameLabel: String
    let namePlaceholder: String
    let getStarted: String
    let skipButton: String
    let continueButton: String
    let languageTitle: String
    let creatingAccount: String
    let accountCreated: String
    let enterNameHint: String

    static let english = LocalizedStrings(
        appName: "Vibing",
        appTagline: "Multi-device Terminal Synchronization",
        welcomeTitle: "Welcome",
        welcomeSubtitle: "Let's get you started with Vibing",
        feature1Title: "🔄 Sync Across Devices",
        feature1Desc: "Access your terminal sessions from any device, anytime.",
        feature2Title: "🔒 Secure & Private",
        feature2Desc: "End-to-end encryption keeps your data safe.",
        feature3Title: "⚡ Blazing Fast",
        feature3Desc: "Metal-accelerated rendering for smooth performance.",
        nameLabel: "Your Name",
        namePlaceholder: "Enter your name",
        getStarted: "Get Started",
        skipButton: "Skip",
        continueButton: "Continue",
        languageTitle: "Language",
        creatingAccount: "Creating your account...",
        accountCreated: "Account created successfully!",
        enterNameHint: "Enter your name to personalize your experience"
    )

    static let chinese = LocalizedStrings(
        appName: "Vibing",
        appTagline: "多设备终端同步",
        welcomeTitle: "欢迎",
        welcomeSubtitle: "开始使用 Vibing",
        feature1Title: "🔄 跨设备同步",
        feature1Desc: "随时随地从任何设备访问您的终端会话。",
        feature2Title: "🔒 安全私密",
        feature2Desc: "端到端加密保护您的数据安全。",
        feature3Title: "⚡ 极速体验",
        feature3Desc: "Metal 加速渲染，流畅顺滑。",
        nameLabel: "您的名字",
        namePlaceholder: "请输入您的名字",
        getStarted: "开始使用",
        skipButton: "跳过",
        continueButton: "继续",
        languageTitle: "语言",
        creatingAccount: "正在创建账户...",
        accountCreated: "账户创建成功！",
        enterNameHint: "输入您的名字以个性化体验"
    )

    static func strings(for language: AppLanguage) -> LocalizedStrings {
        switch language {
        case .english: return english
        case .chinese: return chinese
        }
    }
}

// MARK: - 页面指示器

struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: index == currentPage ? 24 : 8, height: 4)
                    .animation(.easeInOut, value: currentPage)
            }
        }
    }
}

// MARK: - 引导视图

struct OnboardingView: View {
    @StateObject private var accountManager = AccountManager.shared
    @State private var currentPage = 0
    @State private var selectedLanguage: AppLanguage = .chinese
    @State private var accountName = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isCreating = false
    @State private var showSuccess = false
    @FocusState private var isNameFieldFocused: Bool

    private let totalPages = 4

    var strings: LocalizedStrings {
        LocalizedStrings.strings(for: selectedLanguage)
    }

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部导航
                HStack {
                    // 语言切换器
                    Menu {
                        ForEach(AppLanguage.allCases) { lang in
                            Button {
                                withAnimation {
                                    selectedLanguage = lang
                                }
                            } label: {
                                HStack {
                                    Text(lang.flag)
                                    Text(lang.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedLanguage.flag)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)

                    Spacer()

                    // 跳过按钮
                    if currentPage < totalPages - 1 {
                        Button(strings.skipButton) {
                            withAnimation {
                                currentPage = totalPages - 1
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()

                Spacer()

                // 页面内容 - 使用自定义页面切换
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        pageContent
                            .frame(width: geometry.size.width)
                            .offset(x: CGFloat(currentPage) * -geometry.size.width)
                    }
                    .animation(.easeInOut, value: currentPage)
                }
                .clipped()

                Spacer()

                // 底部指示器和按钮
                VStack(spacing: 20) {
                    PageIndicator(currentPage: currentPage, totalPages: totalPages)

                    // 继续按钮
                    Button {
                        handleContinue()
                    } label: {
                        if isCreating {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text(strings.creatingAccount)
                            }
                            .frame(width: 200)
                        } else if currentPage == totalPages - 1 {
                            Text(strings.getStarted)
                        } else {
                            Text(strings.continueButton)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(currentPage == 3 && accountName.isEmpty)
                    .frame(width: 200)
                }
                .padding()
            }
        }
        .frame(width: 500, height: 500)
    }

    // MARK: - 页面内容

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case 0: welcomePage
        case 1: featuresPage
        case 2: detailPage
        case 3: createAccountPage
        default: welcomePage
        }
    }

    // MARK: - 页面

    private var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.accentColor.opacity(0.3),
                                Color.accentColor.opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "terminal.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 12) {
                Text(strings.welcomeTitle)
                    .font(.system(size: 36, weight: .bold))

                Text(strings.appTagline)
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private var featuresPage: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 32) {
                FeatureRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: strings.feature1Title,
                    description: strings.feature1Desc
                )

                FeatureRow(
                    icon: "lock.shield",
                    title: strings.feature2Title,
                    description: strings.feature2Desc
                )

                FeatureRow(
                    icon: "bolt.fill",
                    title: strings.feature3Title,
                    description: strings.feature3Desc
                )
            }

            Spacer()
        }
        .padding()
    }

    private var detailPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            VStack(spacing: 12) {
                Text("QR Code Pairing")
                    .font(.title2)
                    .bold()

                Text(selectedLanguage == .chinese
                    ? "扫描二维码即可在其他设备上同步您的终端"
                    : "Scan QR code to sync your terminal across devices")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    private var createAccountPage: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text(strings.nameLabel)
                    .font(.title2)
                    .bold()

                Text(strings.enterNameHint)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // 名称输入框
            TextField(strings.namePlaceholder, text: $accountName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .font(.body)
                .focused($isNameFieldFocused)
                .onChange(of: accountName) { oldValue, newValue in
                    showError = false
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isNameFieldFocused = true
                    }
                }

            if showError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if showSuccess {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(strings.accountCreated)
                        .foregroundColor(.green)
                }
                .font(.body)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - 辅助方法

    private func handleContinue() {
        switch currentPage {
        case 3:
            // 创建账户
            createAccount()
        default:
            withAnimation {
                if currentPage < totalPages - 1 {
                    currentPage += 1
                }
            }
        }
    }

    private func createAccount() {
        isCreating = true
        showError = false

        Task {
            do {
                try await AccountManager.shared.createAccount(name: accountName.isEmpty ? "Vibe User" : accountName)
                await MainActor.run {
                    isCreating = false
                    showSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        // 成功后会自动跳转到主界面
                    }
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - 功能行组件

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal)
    }
}

// MARK: - 预览

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
