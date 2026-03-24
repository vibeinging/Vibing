//
//  FileTreePanel.swift
//  VibeTerminal
//
//  文件树侧边栏 — 显示当前工作目录的文件/文件夹
//

import AppKit

// MARK: - File Node

class FileNode: NSObject {
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileNode] = []
    var isExpanded = false

    init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }
}

// MARK: - File Tree Panel

class FileTreePanel: NSView, NSOutlineViewDelegate, NSOutlineViewDataSource {

    var onFileSelected: ((String) -> Void)?
    var onDirectorySelected: ((String) -> Void)?
    var onNeedsFocusReturn: (() -> Void)?

    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!
    private var headerLabel: NSTextField!
    private var rootNode: FileNode?
    private var currentPath: String = ""

    private var textColor: NSColor { VibingColors.textSecondary }
    private var textDim: NSColor { VibingColors.textGhost }
    private var hoverColor: NSColor { NSColor.white.withAlphaComponent(0.06) }
    private var dividerColor: NSColor { VibingColors.border }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // 头部：路径标题
        headerLabel = NSTextField(labelWithString: "FILES")
        headerLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        headerLabel.textColor = VibingColors.textGhost
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        // 右侧分隔线
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = dividerColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        // OutlineView
        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 14
        outlineView.backgroundColor = .clear
        outlineView.selectionHighlightStyle = .none
        outlineView.focusRingType = .none
        outlineView.target = self
        outlineView.action = #selector(outlineClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            headerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
        ])

        // 不默认加载——等用户展开面板时才加载当前 session 对应的目录
    }

    // MARK: - 加载目录

    func loadDirectory(_ path: String) {
        currentPath = path
        let shortName = (path as NSString).lastPathComponent
        headerLabel.stringValue = shortName.isEmpty ? "FILES" : shortName.uppercased()
        rootNode = buildTree(at: path)
        outlineView.reloadData()
    }

    private func buildTree(at path: String) -> FileNode {
        let root = FileNode(name: (path as NSString).lastPathComponent, path: path, isDirectory: true)
        root.children = loadOneLevel(at: path)
        return root
    }

    /// 只加载一层子节点（不递归）
    private func loadOneLevel(at path: String) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        return items
            .filter { !$0.hasPrefix(".") }
            .sorted { a, b in
                var d1: ObjCBool = false
                var d2: ObjCBool = false
                fm.fileExists(atPath: (path as NSString).appendingPathComponent(a), isDirectory: &d1)
                fm.fileExists(atPath: (path as NSString).appendingPathComponent(b), isDirectory: &d2)
                if d1.boolValue != d2.boolValue { return d1.boolValue }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            .prefix(200) // 限制数量
            .map { item in
                let fullPath = (path as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                return FileNode(name: item, path: fullPath, isDirectory: isDir.boolValue)
                // 子目录的 children 为空，展开时再加载
            }
    }

    // MARK: - 主题

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = VibingColors.bg0.cgColor
    }

    func applyTheme(_ theme: TerminalTheme) {
        wantsLayer = true
        layer?.backgroundColor = VibingColors.bg0.cgColor
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootNode?.children.count ?? 0 }
        return (item as? FileNode)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootNode!.children[index] }
        return (item as! FileNode).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return (item as? FileNode)?.isDirectory ?? false
    }

    // 展开时懒加载子目录
    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        if node.isDirectory && node.children.isEmpty {
            node.children = loadOneLevel(at: node.path)
            outlineView.reloadItem(node, reloadChildren: true)
        }
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }

        let cell = NSTableCellView()
        cell.wantsLayer = true

        // SF Symbol 图标 — 干净、原生
        let iconName = node.isDirectory ? sfIconForDirectory(node.name, expanded: outlineView.isItemExpanded(node)) : sfIconForFile(node.name)
        let iconColor = node.isDirectory ? dirColor(node.name) : NSColor.white.withAlphaComponent(0.35)

        let iconView = NSImageView()
        let symCfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(symCfg)
        iconView.contentTintColor = iconColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(iconView)

        let label = NSTextField(labelWithString: node.name)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = node.isDirectory ? textColor : textDim
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        ])

        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }

    @objc private func outlineClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }

        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                if node.children.isEmpty {
                    node.children = loadOneLevel(at: node.path)
                }
                outlineView.expandItem(node)
            }
            outlineView.reloadItem(node)
            onDirectorySelected?(node.path)
        } else {
            onFileSelected?(node.path)
        }

        // 点击后把焦点还给终端
        DispatchQueue.main.async { [weak self] in
            self?.onNeedsFocusReturn?()
        }
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let row = FileTreeRowView()
        return row
    }

    // MARK: - SF Symbol 图标

    private func sfIconForDirectory(_ name: String, expanded: Bool) -> String {
        // 展开/折叠状态用不同图标
        if expanded {
            return "folder.fill"
        }
        return "folder"
    }

    private func dirColor(_ name: String) -> NSColor {
        // 读取 memory 中的偏好色
        return NSColor(calibratedRed: 0.45, green: 0.75, blue: 0.55, alpha: 0.8)
    }

    private func sfIconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "rs": return "gearshape.fill"
        case "js", "ts", "jsx", "tsx": return "j.square"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "md", "txt": return "doc.text"
        case "json", "yaml", "yml", "toml": return "gearshape"
        case "sh", "bash", "zsh", "fish": return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        case "mp3", "wav", "m4a": return "music.note"
        case "mp4", "mov", "avi": return "film"
        case "zip", "tar", "gz", "bz2", "xz": return "archivebox"
        case "pdf": return "doc.richtext"
        case "html", "css": return "globe"
        default: return "doc"
        }
    }
}

// MARK: - 自定义行视图（hover 效果）

class FileTreeRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.08).setFill()
        bounds.fill()
    }
}
