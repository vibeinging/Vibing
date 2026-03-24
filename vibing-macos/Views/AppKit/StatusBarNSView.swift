//
//  StatusBarNSView.swift
//  VibeTerminal
//
//  底部状态栏 — MemMe 风格
//

import AppKit
import Combine

class StatusBarNSView: NSView {

    private let tabManager: TabManager
    private let themeManager: ThemeManager

    private var dot: NSView!
    private var pathLabel: NSTextField!
    private var branchIcon: NSImageView!
    private var branchLabel: NSTextField!
    private var infoLabel: NSTextField!

    init(tabManager: TabManager, themeManager: ThemeManager) {
        self.tabManager = tabManager
        self.themeManager = themeManager
        super.init(frame: .zero)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTheme(themeManager.currentTheme)
    }

    private func setup() {
        // 顶部边框
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = VibingColors.border.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        // 连接状态点
        dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = VibingColors.accent.cgColor
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        // 路径
        pathLabel = NSTextField(labelWithString: "Terminal")
        pathLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        pathLabel.textColor = VibingColors.textSecondary
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pathLabel)

        // Git 分支图标
        let symCfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        branchIcon = NSImageView()
        branchIcon.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?.withSymbolConfiguration(symCfg)
        branchIcon.contentTintColor = VibingColors.accent
        branchIcon.translatesAutoresizingMaskIntoConstraints = false
        branchIcon.isHidden = true
        addSubview(branchIcon)

        // Git 分支名
        branchLabel = NSTextField(labelWithString: "")
        branchLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        branchLabel.textColor = VibingColors.accent
        branchLabel.translatesAutoresizingMaskIntoConstraints = false
        branchLabel.isHidden = true
        addSubview(branchLabel)

        // 右侧信息
        infoLabel = NSTextField(labelWithString: "")
        infoLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        infoLabel.textColor = VibingColors.textGhost
        infoLabel.alignment = .right
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoLabel)

        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: topAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),

            pathLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            pathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 250),

            branchIcon.leadingAnchor.constraint(equalTo: pathLabel.trailingAnchor, constant: 14),
            branchIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            branchIcon.widthAnchor.constraint(equalToConstant: 14),
            branchIcon.heightAnchor.constraint(equalToConstant: 14),

            branchLabel.leadingAnchor.constraint(equalTo: branchIcon.trailingAnchor, constant: 4),
            branchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            infoLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            infoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        refresh()
        detectGitBranch()
    }

    func refresh() {
        let tab = tabManager.activeTab
        pathLabel.stringValue = tab?.title ?? "Terminal"

        var parts: [String] = []
        let scale = UserDefaults.standard.double(forKey: "terminalFontScale")
        if scale > 0 && abs(scale - 1.0) > 0.01 {
            parts.append("\(Int(scale * 100))%")
        }
        if let t = tab, t.splitLayout.paneIds.count > 1 {
            parts.append("\(t.splitLayout.paneIds.count) panes")
        }
        parts.append(themeManager.currentTheme.name)
        infoLabel.stringValue = parts.joined(separator: "  \u{00B7}  ")
    }

    func applyTheme(_ theme: TerminalTheme) {
        wantsLayer = true
        layer?.backgroundColor = VibingColors.bg1.cgColor
        refresh()
    }

    private func detectGitBranch() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !branch.isEmpty && process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        self?.branchLabel.stringValue = branch
                        self?.branchIcon.isHidden = false
                        self?.branchLabel.isHidden = false
                    }
                }
            } catch {}
        }
    }
}
