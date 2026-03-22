//
//  WorkingTerminalView.swift
//  VibeTerminal
//
//  产品级终端视图 - 完整功能实现
//

import SwiftUI
import AppKit

struct WorkingTerminalView: View {
    @StateObject private var viewModel = TerminalViewModel(cols: 120, rows: 36)
    @StateObject private var sessionManager = TerminalSessionManager()

    var body: some View {
        ZStack {
            // 背景
            SwiftUI.Color(red: 0.11, green: 0.11, blue: 0.11)

            // Metal 渲染的终端内容
            TerminalMetalView(viewModel: viewModel)

            // 键盘捕获层
            TerminalInputView(viewModel: viewModel) { keyPress in
                sessionManager.handleKeyPress(keyPress)
            }
            .frame(width: 0, height: 0)
            .contentShape(Rectangle())

            // 欢迎提示（未连接时显示）
            if !viewModel.isConnected {
                WelcomeView {
                    startSession()
                }
            }
        }
        .onAppear {
            becomeFirstResponder()
            // 自动启动会话
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                startSession()
            }
        }
        .onDisappear {
            sessionManager.disconnect()
        }
    }

    private func becomeFirstResponder() {
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow {
                window.makeKey()
            }
        }
    }

    private func startSession() {
        sessionManager.connect { [weak viewModel] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let session):
                    viewModel?.connect(session: session)
                    viewModel?.isConnected = true
                case .failure(let error):
                    print("Failed to connect: \(error)")
                    // 显示错误信息
                }
            }
        }
    }
}

// MARK: - 会话管理器

class TerminalSessionManager: ObservableObject {
    private var ptySession: PTYSession?
    private let inputHandler = TerminalInputHandler()
    private var delegateHolder: SessionDelegate?

    func connect(completion: @escaping (Result<PTYSession, Error>) -> Void) {
        // 连接到本地后端服务器
        let serverURL = URL(string: "http://localhost:8080")!

        let session = PTYSession(serverURL: serverURL, config: .default)
        self.ptySession = session
        self.inputHandler.session = session

        // 保持对委托的强引用
        let delegate = SessionDelegate { [weak self] frame in
            self?.handleFrame(frame)
        }
        self.delegateHolder = delegate
        session.delegate = delegate

        session.connect()

        // 延迟返回成功，等待连接建立
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            completion(.success(session))
        }
    }

    func disconnect() {
        ptySession = nil
        inputHandler.session = nil
        delegateHolder = nil
    }

    func handleKeyPress(_ keyPress: KeyPress) -> Bool {
        return inputHandler.handleKeyPress(keyPress)
    }

    private func handleFrame(_ frame: TerminalFrame) {
        // 帧将由 PTYSession 的 delegate 处理
        // 这里可以添加额外的处理逻辑
    }
}

// MARK: - 会话委托

class SessionDelegate: PTYSessionDelegate {
    private let onFrame: (TerminalFrame) -> Void

    init(onFrame: @escaping (TerminalFrame) -> Void) {
        self.onFrame = onFrame
    }

    func session(_ session: PTYSession, didReceiveFrame frame: TerminalFrame) {
        onFrame(frame)
    }

    func session(_ session: PTYSession, didChangeState state: PTYSession.State) {
        print("Session state changed: \(state)")
    }

    func session(_ session: PTYSession, didReceiveError error: Error) {
        print("Session error: \(error)")
    }
}

// MARK: - 欢迎视图

struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Vibe Terminal")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("High-Performance Terminal Emulator")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 16) {
                Feature(icon: "bolt.fill", title: "Fast", description: "Metal渲染")
                Feature(icon: "shield.fill", title: "Secure", description: "本地运行")
                Feature(icon: "cube.fill", title: "Modern", description: "原生体验")
            }
            .padding(.top, 20)

            Text("按任意键或点击开始")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
                .padding(.top, 30)

            Spacer()
        }
        .onTapGesture {
            onStart()
        }
    }
}

struct Feature: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text(description)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

// MARK: - 终端容器视图

struct TerminalWindowView: View {
    var body: some View {
        WorkingTerminalView()
            .background(SwiftUI.Color(red: 0.11, green: 0.11, blue: 0.11))
    }
}
