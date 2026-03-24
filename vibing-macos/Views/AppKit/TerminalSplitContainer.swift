//
//  TerminalSplitContainer.swift
//  VibeTerminal
//
//  终端分屏容器 — 递归 NSSplitView 管理
//

import AppKit
import Combine

class TerminalSplitContainer: NSView, NSSplitViewDelegate {

    private let tabManager: TabManager
    private let themeManager: ThemeManager
    private var cancellables = Set<AnyCancellable>()

    // Pane 缓存：复用已有终端会话
    private var paneCache: [UUID: TerminalPaneController] = [:]
    private var currentLayout: SplitPane?

    init(tabManager: TabManager, themeManager: ThemeManager) {
        self.tabManager = tabManager
        self.themeManager = themeManager
        super.init(frame: .zero)
        wantsLayer = true

        // 监听 tab 切换和 split layout 变化
        tabManager.$activeTabId
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildIfNeeded() }
            .store(in: &cancellables)

        // 首次构建
        rebuildIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 核心重建方法

    func rebuildIfNeeded() {
        guard let tab = tabManager.activeTab else {
            fputs("[SplitContainer] rebuildIfNeeded: no active tab\n", stderr)
            return
        }
        let newLayout = tab.splitLayout
        fputs("[SplitContainer] rebuildIfNeeded: tab=\(tab.id.uuidString.prefix(8)), panes=\(newLayout.paneIds.count), container.bounds=\(bounds)\n", stderr)

        // 简单比较——如果 layout ID 相同则不重建
        if let current = currentLayout, current.id == newLayout.id {
            updateActivePane()
            return
        }

        currentLayout = newLayout
        rebuild(from: newLayout)
        updateActivePane()
    }

    private func rebuild(from layout: SplitPane) {
        // 移除旧子视图（但不销毁 pane cache）
        subviews.forEach { $0.removeFromSuperview() }

        let contentView = buildView(from: layout)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // 清理不再使用的 pane
        let activePaneIds = Set(layout.paneIds)
        let staleIds = paneCache.keys.filter { !activePaneIds.contains($0) }
        for id in staleIds {
            paneCache[id]?.disconnect()
            paneCache.removeValue(forKey: id)
        }
    }

    private func buildView(from layout: SplitPane) -> NSView {
        switch layout {
        case .single(let paneId):
            let pane = getOrCreatePane(paneId)
            // 关键：设置 autoresizingMask 让 view 跟随父容器 resize
            pane.view.autoresizingMask = [.width, .height]
            return pane.view

        case .horizontal(let left, let right, let ratio):
            let splitView = StyledSplitView()
            splitView.isVertical = true  // 左右分
            splitView.dividerStyle = .thin
            splitView.delegate = self

            let leftView = buildView(from: left)
            let rightView = buildView(from: right)
            leftView.autoresizingMask = [.width, .height]
            rightView.autoresizingMask = [.width, .height]
            splitView.addSubview(leftView)
            splitView.addSubview(rightView)

            // 延迟设置比例（等 layout 完成）
            DispatchQueue.main.async {
                splitView.setPosition(splitView.bounds.width * ratio, ofDividerAt: 0)
            }

            return splitView

        case .vertical(let top, let bottom, let ratio):
            let splitView = StyledSplitView()
            splitView.isVertical = false  // 上下分
            splitView.dividerStyle = .thin
            splitView.delegate = self

            let topView = buildView(from: top)
            let bottomView = buildView(from: bottom)
            topView.autoresizingMask = [.width, .height]
            bottomView.autoresizingMask = [.width, .height]
            splitView.addSubview(topView)
            splitView.addSubview(bottomView)

            DispatchQueue.main.async {
                splitView.setPosition(splitView.bounds.height * ratio, ofDividerAt: 0)
            }

            return splitView
        }
    }

    // MARK: - Pane 缓存

    private func getOrCreatePane(_ paneId: UUID) -> TerminalPaneController {
        if let existing = paneCache[paneId] {
            return existing
        }

        let cwd = tabManager.panes[paneId]?.cwd
        let pane = TerminalPaneController(paneId: paneId, cwd: cwd, theme: themeManager.currentTheme)

        // 点击 pane 切换焦点
        pane.onPaneClicked = { [weak self] in
            self?.tabManager.selectPane(id: paneId)
        }

        paneCache[paneId] = pane
        return pane
    }

    // MARK: - 活跃 Pane 管理

    func updateActivePane() {
        let activeId = tabManager.activePaneId
        for (id, pane) in paneCache {
            pane.setActive(id == activeId)
        }
    }

    func getPaneController(_ paneId: UUID) -> TerminalPaneController? {
        return paneCache[paneId]
    }

    func focusActivePane() {
        let activeId = tabManager.activePaneId
        if let pane = paneCache[activeId ?? UUID()] {
            pane.setActive(true)
        }
    }

    // MARK: - 主题 / 字体

    func applyTheme(_ theme: TerminalTheme) {
        for pane in paneCache.values {
            pane.applyTheme(theme)
        }
    }

    func setFontScale(_ scale: CGFloat) {
        for pane in paneCache.values {
            pane.setFontScale(scale)
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 100 // 最小 100pt
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        return total - 100
    }
}

// MARK: - 自定义 NSSplitView（更醒目的分割线）

private class StyledSplitView: NSSplitView {
    override var dividerColor: NSColor {
        return VibingColors.accent.withAlphaComponent(0.25)
    }

    override var dividerThickness: CGFloat {
        return 2
    }
}
