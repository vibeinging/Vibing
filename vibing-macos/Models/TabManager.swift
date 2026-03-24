//
//  TabManager.swift
//  VibeTerminal
//
//  Tab and split pane manager for the terminal
//

import Foundation
import SwiftUI

// MARK: - Terminal Pane

/// A single terminal pane within a tab. Panes are the actual terminal sessions.
struct TerminalPane: Identifiable, Equatable {
    let id: UUID
    var cwd: String?

    init(cwd: String? = nil) {
        self.id = UUID()
        self.cwd = cwd
    }
}

// MARK: - Terminal Tab

/// A tab contains one or more panes arranged in a split layout.
struct TerminalTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isActive: Bool
    var splitLayout: SplitPane
    let createdAt: Date

    init(title: String = "Terminal", paneId: UUID) {
        self.id = UUID()
        self.title = title
        self.isActive = false
        self.splitLayout = .single(paneId: paneId)
        self.createdAt = Date()
    }

    static func == (lhs: TerminalTab, rhs: TerminalTab) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.isActive == rhs.isActive
            && lhs.splitLayout == rhs.splitLayout
    }
}

// MARK: - Pane Direction

enum PaneDirection {
    case up, down, left, right
}

// MARK: - Split Pane

indirect enum SplitPane: Equatable, Identifiable {
    case single(paneId: UUID)
    case horizontal(left: SplitPane, right: SplitPane, splitRatio: CGFloat)
    case vertical(top: SplitPane, bottom: SplitPane, splitRatio: CGFloat)

    var id: String {
        switch self {
        case .single(let paneId):
            return "single_\(paneId.uuidString)"
        case .horizontal(let left, let right, _):
            return "h_\(left.id)_\(right.id)"
        case .vertical(let top, let bottom, _):
            return "v_\(top.id)_\(bottom.id)"
        }
    }

    /// All pane IDs contained in this split pane tree.
    var paneIds: [UUID] {
        switch self {
        case .single(let paneId):
            return [paneId]
        case .horizontal(let left, let right, _):
            return left.paneIds + right.paneIds
        case .vertical(let top, let bottom, _):
            return top.paneIds + bottom.paneIds
        }
    }

    /// Replace a specific pane ID within the tree, returning the updated tree.
    func replacing(paneId target: UUID, with replacement: SplitPane) -> SplitPane {
        switch self {
        case .single(let paneId):
            return paneId == target ? replacement : self
        case .horizontal(let left, let right, let ratio):
            return .horizontal(
                left: left.replacing(paneId: target, with: replacement),
                right: right.replacing(paneId: target, with: replacement),
                splitRatio: ratio
            )
        case .vertical(let top, let bottom, let ratio):
            return .vertical(
                top: top.replacing(paneId: target, with: replacement),
                bottom: bottom.replacing(paneId: target, with: replacement),
                splitRatio: ratio
            )
        }
    }

    /// Find a neighboring pane in the given direction relative to the target pane.
    func neighbor(of targetId: UUID, direction: PaneDirection) -> UUID? {
        switch self {
        case .single:
            return nil
        case .horizontal(let left, let right, _):
            let leftIds = left.paneIds
            let rightIds = right.paneIds
            if leftIds.contains(targetId) {
                if direction == .right { return rightIds.first }
                return left.neighbor(of: targetId, direction: direction)
            }
            if rightIds.contains(targetId) {
                if direction == .left { return leftIds.last }
                return right.neighbor(of: targetId, direction: direction)
            }
            return nil
        case .vertical(let top, let bottom, _):
            let topIds = top.paneIds
            let bottomIds = bottom.paneIds
            if topIds.contains(targetId) {
                if direction == .down { return bottomIds.first }
                return top.neighbor(of: targetId, direction: direction)
            }
            if bottomIds.contains(targetId) {
                if direction == .up { return topIds.last }
                return bottom.neighbor(of: targetId, direction: direction)
            }
            return nil
        }
    }

    /// Adjust the split ratio of the nearest ancestor split containing the target pane.
    func adjustingRatio(for targetId: UUID, direction: PaneDirection, step: CGFloat) -> SplitPane {
        switch self {
        case .single:
            return self
        case .horizontal(let left, let right, let ratio):
            let leftIds = left.paneIds
            let rightIds = right.paneIds
            if leftIds.contains(targetId) || rightIds.contains(targetId) {
                if direction == .left || direction == .right {
                    let delta: CGFloat = direction == .right ? step : -step
                    let newRatio = min(0.85, max(0.15, ratio + (leftIds.contains(targetId) ? delta : -delta)))
                    return .horizontal(left: left, right: right, splitRatio: newRatio)
                }
            }
            return .horizontal(
                left: left.adjustingRatio(for: targetId, direction: direction, step: step),
                right: right.adjustingRatio(for: targetId, direction: direction, step: step),
                splitRatio: ratio
            )
        case .vertical(let top, let bottom, let ratio):
            let topIds = top.paneIds
            let bottomIds = bottom.paneIds
            if topIds.contains(targetId) || bottomIds.contains(targetId) {
                if direction == .up || direction == .down {
                    let delta: CGFloat = direction == .down ? step : -step
                    let newRatio = min(0.85, max(0.15, ratio + (topIds.contains(targetId) ? delta : -delta)))
                    return .vertical(top: top, bottom: bottom, splitRatio: newRatio)
                }
            }
            return .vertical(
                top: top.adjustingRatio(for: targetId, direction: direction, step: step),
                bottom: bottom.adjustingRatio(for: targetId, direction: direction, step: step),
                splitRatio: ratio
            )
        }
    }

    /// Remove a pane ID from the tree, collapsing the parent split if needed.
    func removing(paneId target: UUID) -> SplitPane? {
        switch self {
        case .single(let paneId):
            return paneId == target ? nil : self
        case .horizontal(let left, let right, let ratio):
            let newLeft = left.removing(paneId: target)
            let newRight = right.removing(paneId: target)
            if let l = newLeft, let r = newRight {
                return .horizontal(left: l, right: r, splitRatio: ratio)
            }
            return newLeft ?? newRight
        case .vertical(let top, let bottom, let ratio):
            let newTop = top.removing(paneId: target)
            let newBottom = bottom.removing(paneId: target)
            if let t = newTop, let b = newBottom {
                return .vertical(top: t, bottom: b, splitRatio: ratio)
            }
            return newTop ?? newBottom
        }
    }
}

// MARK: - Tab Manager

class TabManager: ObservableObject {

    // MARK: - Published Properties

    @Published var tabs: [TerminalTab] = []
    @Published var activeTabId: UUID?
    @Published var activePaneId: UUID?
    @Published var panes: [UUID: TerminalPane] = [:]

    // MARK: - Computed Properties

    var activeTab: TerminalTab? {
        tabs.first { $0.id == activeTabId }
    }

    var activePane: TerminalPane? {
        guard let paneId = activePaneId else { return nil }
        return panes[paneId]
    }

    /// The split layout of the currently active tab.
    var activeSplitLayout: SplitPane? {
        activeTab?.splitLayout
    }

    var tabCount: Int {
        tabs.count
    }

    // MARK: - Initialization

    init() {
        let pane = TerminalPane()
        panes[pane.id] = pane

        var tab = TerminalTab(paneId: pane.id)
        tab.isActive = true
        tabs = [tab]
        activeTabId = tab.id
        activePaneId = pane.id
    }

    // MARK: - Tab Operations

    /// Create a new terminal tab and make it active.
    @discardableResult
    func createTab(title: String = "Terminal") -> TerminalTab {
        let pane = TerminalPane()
        panes[pane.id] = pane

        var tab = TerminalTab(title: title, paneId: pane.id)
        tab.isActive = true

        deactivateAllTabs()
        tabs.append(tab)
        activeTabId = tab.id
        activePaneId = pane.id

        return tab
    }

    /// Close a tab by its ID. Removes all panes within the tab.
    func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }

        let wasActive = id == activeTabId

        // Remove all panes belonging to this tab
        if let tab = tabs.first(where: { $0.id == id }) {
            for paneId in tab.splitLayout.paneIds {
                panes.removeValue(forKey: paneId)
            }
        }

        tabs.removeAll { $0.id == id }

        if wasActive {
            if let lastTab = tabs.last {
                selectTab(id: lastTab.id)
            }
        }
    }

    /// Close the active pane. If it's the last pane in the tab, close the tab.
    func closeActivePane() {
        guard let paneId = activePaneId, let tabIdx = activeTabIndex else { return }

        let tab = tabs[tabIdx]
        let allPaneIds = tab.splitLayout.paneIds

        if allPaneIds.count <= 1 {
            // Last pane in tab → close the tab
            closeTab(id: tab.id)
            return
        }

        // Remove pane from layout
        if let newLayout = tab.splitLayout.removing(paneId: paneId) {
            tabs[tabIdx].splitLayout = newLayout
            panes.removeValue(forKey: paneId)

            // Activate a sibling pane
            let remainingPanes = newLayout.paneIds
            activePaneId = remainingPanes.first
        }
    }

    /// Select a tab by its ID, making it active.
    func selectTab(id: UUID) {
        guard let tabIdx = tabs.firstIndex(where: { $0.id == id }) else { return }

        deactivateAllTabs()
        tabs[tabIdx].isActive = true
        activeTabId = id

        // Activate the first pane in the tab
        activePaneId = tabs[tabIdx].splitLayout.paneIds.first
    }

    /// Move a tab from one index to another.
    func moveTab(from source: Int, to destination: Int) {
        guard source >= 0, source < tabs.count,
              destination >= 0, destination < tabs.count,
              source != destination else { return }
        let tab = tabs.remove(at: source)
        tabs.insert(tab, at: destination)
    }

    /// Move a tab from an IndexSet.
    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    /// Update the title of a specific tab.
    func updateTabTitle(id: UUID, title: String) {
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            tabs[index].title = title
        }
    }

    // MARK: - Split Operations

    enum SplitDirection {
        case horizontal
        case vertical
    }

    /// Split the active pane in the given direction. The new pane inherits the cwd.
    @discardableResult
    func splitActivePane(_ direction: SplitDirection) -> TerminalPane? {
        guard let currentPaneId = activePaneId, let tabIdx = activeTabIndex else { return nil }

        let sourceCwd = panes[currentPaneId]?.cwd
        let newPane = TerminalPane(cwd: sourceCwd)
        panes[newPane.id] = newPane

        let newSplit: SplitPane
        switch direction {
        case .horizontal:
            newSplit = .horizontal(
                left: .single(paneId: currentPaneId),
                right: .single(paneId: newPane.id),
                splitRatio: 0.5
            )
        case .vertical:
            newSplit = .vertical(
                top: .single(paneId: currentPaneId),
                bottom: .single(paneId: newPane.id),
                splitRatio: 0.5
            )
        }

        tabs[tabIdx].splitLayout = tabs[tabIdx].splitLayout.replacing(
            paneId: currentPaneId, with: newSplit
        )

        return newPane
    }

    /// Remove a pane from its tab, collapsing the split.
    func unsplit(paneId: UUID) {
        guard let tabIdx = tabIndex(containingPane: paneId) else { return }

        let tab = tabs[tabIdx]
        let allPaneIds = tab.splitLayout.paneIds
        guard allPaneIds.count > 1 else { return }

        if let newLayout = tab.splitLayout.removing(paneId: paneId) {
            tabs[tabIdx].splitLayout = newLayout
            panes.removeValue(forKey: paneId)

            if paneId == activePaneId {
                activePaneId = newLayout.paneIds.first
            }
        }
    }

    // MARK: - Pane Navigation

    /// Navigate to the next pane within the active tab.
    func selectNextPane() {
        guard let tabIdx = activeTabIndex, let paneId = activePaneId else { return }
        let allPaneIds = tabs[tabIdx].splitLayout.paneIds
        guard allPaneIds.count > 1,
              let currentIndex = allPaneIds.firstIndex(of: paneId) else { return }
        activePaneId = allPaneIds[(currentIndex + 1) % allPaneIds.count]
    }

    /// Navigate to the previous pane within the active tab.
    func selectPreviousPane() {
        guard let tabIdx = activeTabIndex, let paneId = activePaneId else { return }
        let allPaneIds = tabs[tabIdx].splitLayout.paneIds
        guard allPaneIds.count > 1,
              let currentIndex = allPaneIds.firstIndex(of: paneId) else { return }
        activePaneId = allPaneIds[(currentIndex - 1 + allPaneIds.count) % allPaneIds.count]
    }

    /// Navigate to a pane in the given direction.
    func navigatePane(_ direction: PaneDirection) {
        guard let tabIdx = activeTabIndex, let paneId = activePaneId else { return }
        if let targetId = tabs[tabIdx].splitLayout.neighbor(of: paneId, direction: direction) {
            activePaneId = targetId
        }
    }

    /// Select a pane by its ID.
    func selectPane(id: UUID) {
        guard panes[id] != nil else { return }
        activePaneId = id
    }

    // MARK: - Pane Resize

    private let resizeStep: CGFloat = 0.05

    func resizeActivePane(_ direction: PaneDirection) {
        guard let tabIdx = activeTabIndex, let paneId = activePaneId else { return }
        tabs[tabIdx].splitLayout = tabs[tabIdx].splitLayout.adjustingRatio(
            for: paneId, direction: direction, step: resizeStep
        )
    }

    // MARK: - Pane Maximize

    @Published var maximizedPaneId: UUID?
    private var savedLayouts: [UUID: SplitPane] = [:]

    func toggleMaximizeActivePane() {
        guard let paneId = activePaneId, let tabIdx = activeTabIndex else { return }
        let tabId = tabs[tabIdx].id

        if maximizedPaneId != nil {
            // Restore
            if let saved = savedLayouts.removeValue(forKey: tabId) {
                tabs[tabIdx].splitLayout = saved
            }
            maximizedPaneId = nil
        } else {
            // Maximize
            savedLayouts[tabId] = tabs[tabIdx].splitLayout
            tabs[tabIdx].splitLayout = .single(paneId: paneId)
            maximizedPaneId = paneId
        }
    }

    // MARK: - Tab Navigation

    func selectNextTab() {
        guard let currentId = activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        selectTab(id: tabs[nextIndex].id)
    }

    func selectPreviousTab() {
        guard let currentId = activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let previousIndex = (currentIndex - 1 + tabs.count) % tabs.count
        selectTab(id: tabs[previousIndex].id)
    }

    func selectTab(at position: Int) {
        let index = position - 1
        guard index >= 0, index < tabs.count else { return }
        selectTab(id: tabs[index].id)
    }

    // MARK: - Pane to Tab

    /// Move a pane out of its current tab into a new standalone tab.
    func movePaneToNewTab(paneId: UUID) {
        guard let tabIdx = tabIndex(containingPane: paneId) else { return }
        let tab = tabs[tabIdx]
        // Only move if the tab has multiple panes
        guard tab.splitLayout.paneIds.count > 1 else { return }
        guard let pane = panes[paneId] else { return }

        // Remove pane from current tab's layout
        if let newLayout = tab.splitLayout.removing(paneId: paneId) {
            tabs[tabIdx].splitLayout = newLayout
        }

        // Create a new tab using the existing pane
        var newTab = TerminalTab(title: "Terminal", paneId: pane.id)
        newTab.isActive = true

        deactivateAllTabs()
        tabs.append(newTab)
        activeTabId = newTab.id
        activePaneId = pane.id
    }

    // MARK: - Pane CWD

    /// Update the cwd of a pane (called when the terminal detects a directory change).
    func updatePaneCwd(_ paneId: UUID, cwd: String) {
        panes[paneId]?.cwd = cwd
    }

    // MARK: - Private Helpers

    private var activeTabIndex: Int? {
        guard let tabId = activeTabId else { return nil }
        return tabs.firstIndex(where: { $0.id == tabId })
    }

    private func tabIndex(containingPane paneId: UUID) -> Int? {
        tabs.firstIndex { $0.splitLayout.paneIds.contains(paneId) }
    }

    private func deactivateAllTabs() {
        for index in tabs.indices {
            tabs[index].isActive = false
        }
    }
}
