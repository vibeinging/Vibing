//
//  OverlayManager.swift
//  VibeTerminal
//
//  管理 SwiftUI overlay（命令面板、搜索、设置）在 AppKit 中的显示
//

import AppKit
import SwiftUI
import Combine

class OverlayManager {

    private weak var container: NSView?
    private let commandPalette: CommandPaletteManager
    private let searchManager: TerminalSearchManager
    private let themeManager: ThemeManager
    private let tabManager: TabManager
    private let launchConfigManager: LaunchConfigManager

    private var commandPaletteHosting: NSHostingView<AnyView>?
    private var searchBarHosting: NSHostingView<AnyView>?
    private var settingsPanel: NSPanel?

    private var cancellables = Set<AnyCancellable>()

    init(container: NSView,
         commandPalette: CommandPaletteManager,
         searchManager: TerminalSearchManager,
         themeManager: ThemeManager,
         tabManager: TabManager,
         launchConfigManager: LaunchConfigManager) {
        self.container = container
        self.commandPalette = commandPalette
        self.searchManager = searchManager
        self.themeManager = themeManager
        self.tabManager = tabManager
        self.launchConfigManager = launchConfigManager

        // 监听命令面板 visibility
        commandPalette.$isVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                if visible {
                    self?.showCommandPaletteView()
                } else {
                    self?.hideCommandPaletteView()
                }
            }
            .store(in: &cancellables)

        // 监听搜索 visibility
        searchManager.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                if active {
                    self?.showSearchView()
                } else {
                    self?.hideSearchView()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 命令面板

    func toggleCommandPalette() {
        commandPalette.toggle()
    }

    private func showCommandPaletteView() {
        guard let container = container, commandPaletteHosting == nil else { return }

        let view = CommandPaletteView(manager: commandPalette)
        let hosting = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, .dark)))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        commandPaletteHosting = hosting
    }

    private func hideCommandPaletteView() {
        commandPaletteHosting?.removeFromSuperview()
        commandPaletteHosting = nil
    }

    // MARK: - 搜索栏

    func toggleSearch() {
        searchManager.toggle()
    }

    private func showSearchView() {
        guard let container = container, searchBarHosting == nil else { return }

        let view = SearchBarView(searchManager: searchManager)
        let hosting = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, .dark)))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)

        // 搜索栏定位在右上角
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            hosting.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
        ])

        searchBarHosting = hosting
    }

    private func hideSearchView() {
        searchBarHosting?.removeFromSuperview()
        searchBarHosting = nil
    }

    // MARK: - 设置

    func showSettings() {
        if let panel = settingsPanel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView(
            themeManager: themeManager,
            tabManager: tabManager,
            launchConfigManager: launchConfigManager,
            isVisible: Binding(
                get: { [weak self] in self?.settingsPanel?.isVisible ?? false },
                set: { [weak self] visible in
                    if !visible { self?.settingsPanel?.close() }
                }
            )
        )

        let hosting = NSHostingView(rootView: settingsView.environment(\.colorScheme, .dark))
        hosting.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        let zh = AppLanguage.current == .chinese
        panel.title = zh ? "设置" : "Settings"
        panel.minSize = NSSize(width: 600, height: 400)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.isReleasedWhenClosed = false

        settingsPanel = panel
    }
}
