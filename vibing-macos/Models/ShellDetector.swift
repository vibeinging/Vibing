//
//  ShellDetector.swift
//  VibeTerminal
//
//  系统 Shell 检测与管理
//

import Foundation
import SwiftUI

/// 一个可用的 shell
struct DetectedShell: Identifiable, Codable, Equatable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let version: String
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case path, name, version
        case isDefault = "is_default"
    }
}

/// Shell 检测器 — 本地检测 + 从服务端获取
class ShellDetector: ObservableObject {
    static let shared = ShellDetector()

    @Published var availableShells: [DetectedShell] = []
    @Published var defaultShellPath: String = ""
    @Published var isLoading = false

    /// 用户选择的 shell（持久化到 UserDefaults）
    @AppStorage("selectedShell") var selectedShellPath: String = ""

    /// 当前生效的 shell 路径
    var effectiveShell: String {
        if !selectedShellPath.isEmpty && availableShells.contains(where: { $0.path == selectedShellPath }) {
            return selectedShellPath
        }
        return defaultShellPath
    }

    /// 当前生效的 shell 名称
    var effectiveShellName: String {
        if let shell = availableShells.first(where: { $0.path == effectiveShell }) {
            return shell.name
        }
        return URL(fileURLWithPath: effectiveShell).lastPathComponent
    }

    init() {
        detectLocally()
    }

    /// 本地检测（不依赖服务端，快速）
    func detectLocally() {
        var shells: [DetectedShell] = []
        var seen = Set<String>()

        // 1. 读取 /etc/shells
        if let content = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let path = line.trimmingCharacters(in: .whitespaces)
                if path.isEmpty || path.hasPrefix("#") { continue }
                if FileManager.default.fileExists(atPath: path) && seen.insert(path).inserted {
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    shells.append(DetectedShell(
                        path: path,
                        name: name,
                        version: getShellVersion(path),
                        isDefault: false
                    ))
                }
            }
        }

        // 2. 额外扫描
        let extraPaths = [
            "/usr/local/bin/fish",
            "/opt/homebrew/bin/fish",
            "/usr/local/bin/nu",
            "/opt/homebrew/bin/nu",
            "/usr/local/bin/elvish",
            "/opt/homebrew/bin/elvish",
            "/usr/local/bin/pwsh",
            "/opt/homebrew/bin/pwsh",
        ]
        for path in extraPaths {
            if FileManager.default.fileExists(atPath: path) && seen.insert(path).inserted {
                let name = URL(fileURLWithPath: path).lastPathComponent
                shells.append(DetectedShell(
                    path: path,
                    name: name,
                    version: getShellVersion(path),
                    isDefault: false
                ))
            }
        }

        // 3. 检测默认 shell（dscl 查询）
        let detectedDefault = detectDefaultShell()

        // 标记默认
        shells = shells.map { shell in
            var s = shell
            if shell.path == detectedDefault {
                s = DetectedShell(path: s.path, name: s.name, version: s.version, isDefault: true)
            }
            return s
        }

        // 排序：默认在前
        shells.sort { a, b in
            if a.isDefault != b.isDefault { return a.isDefault }
            return a.name < b.name
        }

        DispatchQueue.main.async {
            self.availableShells = shells
            self.defaultShellPath = detectedDefault
            // 如果用户没有手动选择，使用系统默认
            if self.selectedShellPath.isEmpty {
                self.selectedShellPath = detectedDefault
            }
        }
    }

    /// 从服务端获取（更准确，包含版本信息）
    /// 调用者负责发送 WebSocket 请求，收到响应后调用 handleServerShellInfo
    func markFetchingFromServer() {
        isLoading = true
    }

    /// 处理服务端返回的 shell_info
    func handleServerShellInfo(_ data: [String: Any]) {
        DispatchQueue.main.async {
            self.isLoading = false

            if let shell = data["shell"] as? String {
                self.defaultShellPath = shell
            }

            if let available = data["available_shells"] as? [[String: Any]] {
                self.availableShells = available.compactMap { dict in
                    guard let path = dict["path"] as? String,
                          let name = dict["name"] as? String else { return nil }
                    return DetectedShell(
                        path: path,
                        name: name,
                        version: dict["version"] as? String ?? "",
                        isDefault: dict["is_default"] as? Bool ?? false
                    )
                }
            }

            if self.selectedShellPath.isEmpty {
                self.selectedShellPath = self.defaultShellPath
            }
        }
    }

    // MARK: - Private

    private func detectDefaultShell() -> String {
        // 1. dscl（macOS）
        let user = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        task.arguments = [".", "-read", "/Users/\(user)", "UserShell"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        if let _ = try? task.run() {
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let shell = output.components(separatedBy: "UserShell: ").last?.trimmingCharacters(in: .whitespacesAndNewlines),
               FileManager.default.fileExists(atPath: shell) {
                return shell
            }
        }

        // 2. $SHELL
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           FileManager.default.fileExists(atPath: shell) {
            return shell
        }

        // 3. 回退
        return FileManager.default.fileExists(atPath: "/bin/zsh") ? "/bin/zsh" : "/bin/bash"
    }

    private func getShellVersion(_ path: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["--version"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        guard let _ = try? task.run() else { return "" }
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
