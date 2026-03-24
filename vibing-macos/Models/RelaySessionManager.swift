//
//  RelaySessionManager.swift
//  VibeTerminal
//
//  管理终端会话的 relay 共享状态
//  每个终端 pane（PTY session）有独立的 relay session
//  已登录时自动共享，无需手动操作
//

import Foundation
import SwiftUI

// MARK: - 单个 Relay Session 的状态

class RelaySessionState: ObservableObject, Identifiable {
    let id: String  // local PTY session ID

    @Published var isSharing = false
    @Published var relaySessionId: String?
    @Published var peerConnected = false
    @Published var errorMessage: String?

    init(localSessionId: String) {
        self.id = localSessionId
    }
}

// MARK: - Relay Session Manager

class RelaySessionManager: ObservableObject {

    // MARK: - State

    /// 所有活跃的 relay sessions: localSessionId → RelaySessionState
    @Published var sessions: [String: RelaySessionState] = [:]

    // MARK: - Singleton

    static let shared = RelaySessionManager()

    private init() {}

    // MARK: - Get/Create State

    /// 获取指定 session 的 relay 状态
    func state(for localSessionId: String) -> RelaySessionState {
        if let existing = sessions[localSessionId] {
            return existing
        }
        let newState = RelaySessionState(localSessionId: localSessionId)
        DispatchQueue.main.async {
            self.sessions[localSessionId] = newState
        }
        return newState
    }

    // MARK: - Start Sharing

    /// 自动共享指定的终端会话到 relay
    @discardableResult
    func startSharing(wsClient: Any?, localSessionId: String) async throws -> String {
        let account = AccountManager.shared
        guard account.isSignedIn,
              let token = account.authToken else {
            throw RelayError.notSignedIn
        }

        let relayURL = RelayAPIClient.shared.relayWebSocketURL
        let relaySessionId = generateRelaySessionId()

        // 构造 start_relay 命令
        let command: [String: Any] = [
            "type": "start_relay",
            "session_id": localSessionId,
            "relay_url": relayURL,
            "token": token,
            "relay_session_id": relaySessionId,
        ]

        // 发送到本地 vibing-server
        if let jsonData = try? JSONSerialization.data(withJSONObject: command),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            NotificationCenter.default.post(
                name: .sendRelayCommand,
                object: nil,
                userInfo: ["command": jsonString]
            )
        }

        let sessionState = state(for: localSessionId)
        await MainActor.run {
            sessionState.relaySessionId = relaySessionId
            sessionState.isSharing = true
            sessionState.peerConnected = false
            sessionState.errorMessage = nil
        }

        return relaySessionId
    }

    // MARK: - Stop Sharing

    func stopSharing(localSessionId: String) async {
        let command: [String: Any] = [
            "type": "stop_relay",
            "session_id": localSessionId,
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: command),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            NotificationCenter.default.post(
                name: .sendRelayCommand,
                object: nil,
                userInfo: ["command": jsonString]
            )
        }

        await MainActor.run {
            self.sessions.removeValue(forKey: localSessionId)
        }
    }

    // MARK: - Handle Relay Messages from Server

    /// 处理 vibing-server 返回的 relay 状态消息
    func handleRelayMessage(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }

        // 从 relay_session_id 或 session_id 找到对应的 state
        let relaySessionId = json["relay_session_id"] as? String
        let localSessionId = json["session_id"] as? String

        DispatchQueue.main.async {
            // 查找匹配的 session state
            let sessionState: RelaySessionState? = {
                if let lid = localSessionId, let s = self.sessions[lid] {
                    return s
                }
                if let rid = relaySessionId {
                    return self.sessions.values.first { $0.relaySessionId == rid }
                }
                return nil
            }()

            switch type {
            case "relay_started":
                if let state = sessionState {
                    state.isSharing = true
                    if let sid = relaySessionId {
                        state.relaySessionId = sid
                    }
                    state.errorMessage = nil
                }

            case "relay_stopped":
                if let state = sessionState {
                    state.isSharing = false
                    state.relaySessionId = nil
                    state.peerConnected = false
                }

            case "relay_peer_connected":
                sessionState?.peerConnected = true

            case "relay_peer_disconnected":
                sessionState?.peerConnected = false

            case "relay_error":
                // 如果有对应 state，更新错误
                if let state = sessionState {
                    state.errorMessage = json["error"] as? String
                }

            default:
                break
            }
        }
    }

    // MARK: - Cleanup

    /// 终端 pane 关闭时清理
    func removeSession(_ localSessionId: String) {
        sessions.removeValue(forKey: localSessionId)
    }

    // MARK: - Helpers

    /// 生成 16 字符的 relay session ID
    private func generateRelaySessionId() -> String {
        let charset = "abcdefghjkmnpqrstuvwxyz23456789"
        return String((0..<16).map { _ in charset.randomElement()! })
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 发送 relay 命令到本地 vibing-server
    static let sendRelayCommand = Notification.Name("sendRelayCommand")
}

// MARK: - Errors

enum RelayError: LocalizedError {
    case notSignedIn
    case connectionFailed(String)
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Please sign in first"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .sessionNotFound: return "Session not found"
        }
    }
}
