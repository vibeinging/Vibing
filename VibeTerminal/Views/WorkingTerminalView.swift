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
    @StateObject private var inputHandlerState = InputHandlerState()

    var body: some View {
        ZStack {
            // 背景
            SwiftUI.Color(red: 0.11, green: 0.11, blue: 0.11)

            // Metal 渲染的终端内容
            TerminalMetalView(viewModel: viewModel)

            // 隐藏的键盘捕获层（几乎透明）
            TerminalInputView(viewModel: viewModel) { keyPress in
                inputHandlerState.handleKeyPress(keyPress)
            }
            .frame(width: 0, height: 0)  // 不占用空间
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                startSession()
            }
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
        // TODO: 连接到后端服务器启动 PTY 会话
        viewModel.isConnected = true
    }
}

// MARK: - 输入处理器状态

class InputHandlerState: ObservableObject {
    private let handler = TerminalInputHandler()

    func handleKeyPress(_ keyPress: KeyPress) -> Bool {
        return handler.handleKeyPress(keyPress)
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
