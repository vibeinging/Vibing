//
//  LaunchConfigManager.swift
//  VibeTerminal
//
//  Launch Configurations - save and restore window/tab/pane layouts
//

import Foundation
import SwiftUI

// MARK: - Launch Configuration Models

struct LaunchPaneConfig: Codable, Equatable {
    let cwd: String?
}

indirect enum LaunchSplitConfig: Codable, Equatable {
    case single(pane: LaunchPaneConfig)
    case horizontal(left: LaunchSplitConfig, right: LaunchSplitConfig, splitRatio: CGFloat)
    case vertical(top: LaunchSplitConfig, bottom: LaunchSplitConfig, splitRatio: CGFloat)

    // Custom Codable for indirect enum
    enum CodingKeys: String, CodingKey {
        case type, pane, left, right, top, bottom, splitRatio
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .single(let pane):
            try container.encode("single", forKey: .type)
            try container.encode(pane, forKey: .pane)
        case .horizontal(let left, let right, let ratio):
            try container.encode("horizontal", forKey: .type)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
            try container.encode(ratio, forKey: .splitRatio)
        case .vertical(let top, let bottom, let ratio):
            try container.encode("vertical", forKey: .type)
            try container.encode(top, forKey: .top)
            try container.encode(bottom, forKey: .bottom)
            try container.encode(ratio, forKey: .splitRatio)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "single":
            let pane = try container.decode(LaunchPaneConfig.self, forKey: .pane)
            self = .single(pane: pane)
        case "horizontal":
            let left = try container.decode(LaunchSplitConfig.self, forKey: .left)
            let right = try container.decode(LaunchSplitConfig.self, forKey: .right)
            let ratio = try container.decode(CGFloat.self, forKey: .splitRatio)
            self = .horizontal(left: left, right: right, splitRatio: ratio)
        case "vertical":
            let top = try container.decode(LaunchSplitConfig.self, forKey: .top)
            let bottom = try container.decode(LaunchSplitConfig.self, forKey: .bottom)
            let ratio = try container.decode(CGFloat.self, forKey: .splitRatio)
            self = .vertical(top: top, bottom: bottom, splitRatio: ratio)
        default:
            self = .single(pane: LaunchPaneConfig(cwd: nil))
        }
    }

    init(_ layout: SplitPane, panes: [UUID: TerminalPane]) {
        switch layout {
        case .single(let paneId):
            self = .single(pane: LaunchPaneConfig(cwd: panes[paneId]?.cwd))
        case .horizontal(let left, let right, let ratio):
            self = .horizontal(
                left: LaunchSplitConfig(left, panes: panes),
                right: LaunchSplitConfig(right, panes: panes),
                splitRatio: ratio
            )
        case .vertical(let top, let bottom, let ratio):
            self = .vertical(
                top: LaunchSplitConfig(top, panes: panes),
                bottom: LaunchSplitConfig(bottom, panes: panes),
                splitRatio: ratio
            )
        }
    }
}

struct LaunchTabConfig: Codable, Equatable {
    let title: String
    let splitLayout: LaunchSplitConfig
}

struct LaunchConfiguration: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var tabs: [LaunchTabConfig]
    let createdAt: Date

    init(name: String, tabs: [LaunchTabConfig]) {
        self.id = UUID()
        self.name = name
        self.tabs = tabs
        self.createdAt = Date()
    }
}

// MARK: - Launch Config Manager

class LaunchConfigManager: ObservableObject {
    @Published var configurations: [LaunchConfiguration] = []

    private let storageKey = "launchConfigurations"

    init() {
        load()
    }

    // MARK: - Save from current state

    func saveCurrentLayout(name: String, tabManager: TabManager) {
        let tabConfigs = tabManager.tabs.map { tab in
            LaunchTabConfig(
                title: tab.title,
                splitLayout: LaunchSplitConfig(tab.splitLayout, panes: tabManager.panes)
            )
        }
        let config = LaunchConfiguration(name: name, tabs: tabConfigs)
        configurations.append(config)
        persist()
    }

    // MARK: - Restore to TabManager

    func restore(_ config: LaunchConfiguration, tabManager: TabManager) {
        // Clear existing state
        tabManager.tabs.removeAll()
        tabManager.panes.removeAll()
        tabManager.activeTabId = nil
        tabManager.activePaneId = nil

        for (index, tabConfig) in config.tabs.enumerated() {
            let (layout, newPanes) = buildSplitPane(from: tabConfig.splitLayout)
            for pane in newPanes {
                tabManager.panes[pane.id] = pane
            }

            var tab = TerminalTab(title: tabConfig.title, paneId: layout.paneIds.first!)
            tab.splitLayout = layout
            tab.isActive = index == 0
            // We need to fix the tab's splitLayout since TerminalTab.init creates a .single
            // Override with our actual layout
            tabManager.tabs.append(tab)

            if index == 0 {
                tabManager.activeTabId = tab.id
                tabManager.activePaneId = layout.paneIds.first
            }
        }

        // If no tabs were created, create a default one
        if tabManager.tabs.isEmpty {
            tabManager.createTab()
        }
    }

    private func buildSplitPane(from config: LaunchSplitConfig) -> (SplitPane, [TerminalPane]) {
        switch config {
        case .single(let paneConfig):
            let pane = TerminalPane(cwd: paneConfig.cwd)
            return (.single(paneId: pane.id), [pane])
        case .horizontal(let left, let right, let ratio):
            let (leftLayout, leftPanes) = buildSplitPane(from: left)
            let (rightLayout, rightPanes) = buildSplitPane(from: right)
            return (.horizontal(left: leftLayout, right: rightLayout, splitRatio: ratio), leftPanes + rightPanes)
        case .vertical(let top, let bottom, let ratio):
            let (topLayout, topPanes) = buildSplitPane(from: top)
            let (bottomLayout, bottomPanes) = buildSplitPane(from: bottom)
            return (.vertical(top: topLayout, bottom: bottomLayout, splitRatio: ratio), topPanes + bottomPanes)
        }
    }

    // MARK: - CRUD

    func rename(_ id: UUID, to name: String) {
        if let idx = configurations.firstIndex(where: { $0.id == id }) {
            configurations[idx].name = name
            persist()
        }
    }

    func delete(_ id: UUID) {
        configurations.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let configs = try? JSONDecoder().decode([LaunchConfiguration].self, from: data) else { return }
        configurations = configs
    }
}
