//
//  WorkingTerminalView.swift
//  VibeTerminal
//
//  终端会话管理器 — 管理 WebSocket 连接和数据流
//  （原 SwiftUI WorkingTerminalView 已被 TerminalPaneController 替代）
//

import Foundation
import AppKit

// MARK: - 会话管理器

class TerminalSessionManager: NSObject, ObservableObject, TerminalWebSocketClientDelegate {
    @Published var isConnected = false
    @Published var connectionState: ConnectionState = .disconnected
    var lastKnownCwd: String?

    private var wsClient: TerminalWebSocketClient?
    private(set) var currentSessionId: String?
    private var initialCwd: String?
    weak var terminalView: RemoteTerminalView?
    private var sessionCreated = false
    private var relayCommandObserver: NSObjectProtocol?

    func startSession(terminalView: RemoteTerminalView, cwd: String? = nil) {
        self.terminalView = terminalView
        self.initialCwd = cwd

        // 设置 RemoteTerminalView 的 delegate
        terminalView.remoteDelegate = self
        fputs("[SessionMgr] startSession: delegate set, connecting to ws://127.0.0.1:8765\n", stderr)

        let serverURL = URL(string: "ws://127.0.0.1:8765")!
        let client = TerminalWebSocketClient(serverURL: serverURL)
        client.delegate = self
        self.wsClient = client
        client.connect()

        // 监听 relay 命令通知
        relayCommandObserver = NotificationCenter.default.addObserver(
            forName: .sendRelayCommand,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let command = notification.userInfo?["command"] as? String,
                  let client = self?.wsClient else { return }
            Task {
                try? await client.sendRawText(command)
            }
        }
    }

    func disconnect() {
        if let observer = relayCommandObserver {
            NotificationCenter.default.removeObserver(observer)
            relayCommandObserver = nil
        }
        // 清理 relay session
        if let sessionId = currentSessionId {
            RelaySessionManager.shared.removeSession(sessionId)
        }
        wsClient?.disconnect()
        wsClient = nil
        currentSessionId = nil
        isConnected = false
    }

    /// 发送原始终端数据（来自 SwiftTerm 的键盘输入）
    func sendData(_ data: Data) {
        guard let sessionId = currentSessionId, let client = wsClient else {
            fputs("[SessionMgr] sendData SKIPPED: sessionId=\(currentSessionId ?? "nil") hasClient=\(wsClient != nil)\n", stderr)
            return
        }
        Task {
            try? await client.sendJsonText(type: "input", payload: [
                "session_id": sessionId,
                "data": String(data: data, encoding: .utf8) ?? ""
            ])
        }
    }

    /// 发送 resize（带 debounce，避免拖动时频繁触发）
    private var resizeTimer: Timer?
    private var pendingCols: Int = 0
    private var pendingRows: Int = 0

    func sendResize(cols: Int, rows: Int) {
        pendingCols = cols
        pendingRows = rows

        // 取消上一次的定时器
        resizeTimer?.invalidate()
        // 100ms debounce——拖动停止后才发送
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.flushResize()
        }
    }

    private func flushResize() {
        guard let sessionId = currentSessionId, let client = wsClient else { return }
        let cols = pendingCols
        let rows = pendingRows
        guard cols > 0 && rows > 0 else { return }
        Task {
            try? await client.sendJsonText(type: "resize", payload: [
                "session_id": sessionId,
                "cols": cols,
                "rows": rows
            ])
        }
    }

    // MARK: - WebSocket Delegate

    private var createSessionTimer: Timer?

    func client(_ client: TerminalWebSocketClient, didChangeState state: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectionState = state
            if state == .connected {
                // 延迟 300ms 创建 session，等 view layout 稳定拿到最终尺寸
                self.createSessionTimer?.invalidate()
                self.createSessionTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.negotiateAndCreateSession(client: client)
                }
            } else if state == .disconnected {
                self.isConnected = false
            }
        }
    }

    private func negotiateAndCreateSession(client: TerminalWebSocketClient) {
        guard !sessionCreated else { return }
        sessionCreated = true

        Task {
            do {
                // 协商原始字节流模式
                try await client.sendJsonText(type: "negotiate", payload: [
                    "protocol": "raw_stream",
                    "version": 2
                ])

                // 获取 SwiftTerm 的真实尺寸
                var cols = 80
                var rows = 24
                await MainActor.run {
                    if let tv = self.terminalView {
                        let term = tv.getTerminal()
                        if term.cols > 0 { cols = term.cols }
                        if term.rows > 0 { rows = term.rows }
                    }
                }

                // 创建会话
                let shellDetector = ShellDetector.shared
                let selectedShell = shellDetector.effectiveShell
                var request: CreateSessionRequest
                if !selectedShell.isEmpty && selectedShell != "default" {
                    request = CreateSessionRequest(
                        command: selectedShell,
                        args: ["--login"],
                        cwd: initialCwd,
                        env: nil
                    )
                } else {
                    request = CreateSessionRequest.shell()
                    if let cwd = initialCwd {
                        request = request.withCwd(cwd)
                    }
                }
                request.cols = cols
                request.rows = rows

                let sessionId = try await client.createSession(request: request)
                await MainActor.run {
                    self.currentSessionId = sessionId
                    self.isConnected = true
                }
                try await client.subscribe(toSessionIds: [sessionId])

                // 等 shell 完全启动后发 clear，清除 fish 初始化时设的显式背景色
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self = self, self.isConnected else { return }
                    self.sendData(Data("clear\n".utf8))
                }

                // 自动通过 relay 共享：已登录则立即发 start_relay
                self.autoStartRelay(localSessionId: sessionId)
            } catch {
                fputs("[Vibing] Failed to create session: \(error)\n", stderr)
            }
        }
    }

    // MARK: - Auto Relay

    /// 已登录时自动启动 relay 共享
    private func autoStartRelay(localSessionId: String) {
        let account = AccountManager.shared
        guard account.isSignedIn, let _ = account.authToken else {
            fputs("[SessionMgr] Not signed in, skipping auto relay\n", stderr)
            return
        }

        Task {
            do {
                try await RelaySessionManager.shared.startSharing(
                    wsClient: nil,
                    localSessionId: localSessionId
                )
                fputs("[SessionMgr] Auto relay started for session \(localSessionId)\n", stderr)
            } catch {
                fputs("[SessionMgr] Auto relay failed: \(error)\n", stderr)
            }
        }
    }

    // 原始字节输出 → feed 给 RemoteTerminalView
    private var dumpCount = 0

    func client(_ client: TerminalWebSocketClient, didReceiveRawOutput data: Data, forSession sessionId: String) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalView?.feedData(data)

            // 前 3 次数据到达后 dump cell 颜色
            if let self = self, self.dumpCount < 3 {
                self.dumpCount += 1
                self.terminalView?.dumpCellColors()
            }
        }
    }

    func client(_ client: TerminalWebSocketClient, didReceiveOutput frame: ScreenFrame, forSession sessionId: String) {}
    func client(_ client: TerminalWebSocketClient, didUpdateCursor cursor: CursorFrame, forSession sessionId: String) {}

    func client(_ client: TerminalWebSocketClient, didCloseSession sessionId: String) {
        DispatchQueue.main.async { [weak self] in
            if self?.currentSessionId == sessionId {
                self?.isConnected = false
                self?.currentSessionId = nil
            }
        }
    }

    func client(_ client: TerminalWebSocketClient, didReceiveError error: Error) {
        fputs("[Vibing] WebSocket error: \(error)\n", stderr)
    }
}

// MARK: - RemoteTerminalViewDelegate

extension TerminalSessionManager: RemoteTerminalViewDelegate {
    func sendData(source: RemoteTerminalView, data: Data) {
        fputs("[SessionMgr] remoteDelegate.sendData: \(data.count) bytes, connected=\(isConnected)\n", stderr)
        sendData(data)
    }

    func sizeChanged(source: RemoteTerminalView, newCols: Int, newRows: Int) {
        fputs("[SessionMgr] remoteDelegate.sizeChanged: \(newCols)x\(newRows)\n", stderr)
        sendResize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: RemoteTerminalView, title: String) {
        // TODO: 更新 tab 标题
    }

    func hostCurrentDirectoryUpdate(source: RemoteTerminalView, directory: String?) {
        guard let dir = directory else { return }
        // 解析 file:// URL 格式（OSC 7 标准格式）
        let path: String
        if let url = URL(string: dir), url.scheme == "file" {
            path = url.path
        } else {
            path = dir
        }
        lastKnownCwd = path
        fputs("[SessionMgr] cwd updated: \(path)\n", stderr)
    }
}
