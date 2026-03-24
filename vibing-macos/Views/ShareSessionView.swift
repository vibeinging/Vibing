//
//  ShareSessionView.swift
//  VibeTerminal
//
//  终端会话 relay 状态 UI（每个 pane 独立状态）
//  已登录时自动通过 relay 共享，此视图展示连接状态
//

import SwiftUI

// MARK: - Share Status View (per session)

struct ShareSessionView: View {
    @ObservedObject var sessionState: RelaySessionState
    @ObservedObject var account = AccountManager.shared

    var body: some View {
        VStack(spacing: 16) {
            if !account.isSignedIn {
                notSignedInView
            } else if sessionState.isSharing {
                sharingActiveView
            } else {
                connectingView
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    // MARK: - Not Signed In

    private var notSignedInView: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            Text("Not Signed In")
                .font(.headline)

            Text("Sign in to automatically share terminal sessions with your mobile devices.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Connecting

    private var connectingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Connecting to relay...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Sharing Active

    private var sharingActiveView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .foregroundColor(sessionState.peerConnected ? SwiftUI.Color.green : SwiftUI.Color.yellow)
                    .frame(width: 8, height: 8)

                Text(sessionState.peerConnected ? "Mobile Connected" : "Waiting for mobile...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let sessionId = sessionState.relaySessionId {
                VStack(spacing: 6) {
                    Text("Session Code")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(sessionId)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(SwiftUI.Color.gray.opacity(0.15)))

                    Text("Enter this code on your mobile device")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let error = sessionState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Status Bar Indicator (per session)

struct RelayStatusIndicator: View {
    @ObservedObject var sessionState: RelaySessionState
    @ObservedObject var account = AccountManager.shared

    @State private var showPopover = false

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            statusIcon
        }
        .buttonStyle(.plain)
        .help(statusTooltip)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ShareSessionView(sessionState: sessionState)
        }
    }

    private var statusIcon: some View {
        Group {
            if !account.isSignedIn {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundColor(.secondary)
            } else if sessionState.peerConnected {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(SwiftUI.Color.green)
            } else if sessionState.isSharing {
                Image(systemName: "antenna.radiowaves.left.and.right.circle")
                    .foregroundColor(SwiftUI.Color.yellow)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.circle")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 12))
    }

    private var statusTooltip: String {
        if !account.isSignedIn {
            return "Not signed in"
        } else if sessionState.peerConnected {
            return "Mobile device connected"
        } else if sessionState.isSharing {
            return "Waiting for mobile device"
        } else {
            return "Connecting to relay..."
        }
    }
}
