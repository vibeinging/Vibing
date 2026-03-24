//
//  SwiftTerminalView.swift
//  VibeTerminal
//
//  远程终端视图 — 基于 SwiftTerm，通过 WebSocket 连接服务端
//  参照 LocalProcessTerminalView 的模式，用 WebSocket 替代本地 PTY
//

import AppKit
import SwiftTerm

// MARK: - Remote Terminal View Delegate

protocol RemoteTerminalViewDelegate: AnyObject {
    func sizeChanged(source: RemoteTerminalView, newCols: Int, newRows: Int)
    func setTerminalTitle(source: RemoteTerminalView, title: String)
    func hostCurrentDirectoryUpdate(source: RemoteTerminalView, directory: String?)
    func sendData(source: RemoteTerminalView, data: Data)
}

// MARK: - Remote Terminal View

/// 远程终端视图：继承 SwiftTerm.TerminalView，将键盘输入发送到 WebSocket
/// 外部通过 `feedData(_:)` 将 WebSocket 接收的原始字节流喂给终端渲染
class RemoteTerminalView: TerminalView, TerminalViewDelegate {

    weak var remoteDelegate: RemoteTerminalViewDelegate?

    private var currentTheme: TerminalTheme?

    init(frame: CGRect, theme: TerminalTheme?) {
        self.currentTheme = theme
        let font = NSFont(name: "Menlo", size: 15)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        super.init(frame: frame, font: font)
        terminalDelegate = self

        // 初始化时不 applyTheme——等 viewDidLoad 中设置
        // 因为 super.init → setup() 会重置背景色为黑色
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        terminalDelegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        terminalDelegate = self
    }

    override func setFrameSize(_ newSize: NSSize) {
        fputs("[RemoteTV] setFrameSize: \(newSize) terminal=\(getTerminal().cols)x\(getTerminal().rows)\n", stderr)
        super.setFrameSize(newSize)
        syncLayerBackground()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // window 就绪后重新应用主题（确保颜色生效）
        if let theme = currentTheme {
            applyTheme(theme)
        }
        syncLayerBackground()
    }

    /// 确保 layer 背景色和终端背景色一致
    private func syncLayerBackground() {
        wantsLayer = true
        layer?.backgroundColor = nativeBackgroundColor.cgColor
    }

    /// 是否为活跃窗格
    var isActivePane: Bool = false

    /// 点击时的回调（用于通知切换活跃 pane）
    var onClicked: (() -> Void)?

    /// 将远程服务端的原始 PTY 字节流喂给终端渲染
    func feedData(_ data: Data) {
        let bytes = [UInt8](data)
        feed(byteArray: bytes[bytes.startIndex..<bytes.endIndex])
    }

    /// 调试：dump 终端 buffer 中前几行 cell 的背景色
    func dumpCellColors() {
        let term = getTerminal()
        let buf = term.getBufferAsData() // 只是获取文本，不是 cell 属性
        // 用另一个方式：检查第一行和最后一行的属性
        fputs("[RemoteTV] dumpCellColors: cols=\(term.cols) rows=\(term.rows)\n", stderr)
        fputs("[RemoteTV] nativeBackgroundColor=\(nativeBackgroundColor)\n", stderr)
        fputs("[RemoteTV] layer.backgroundColor=\(String(describing: layer?.backgroundColor))\n", stderr)

        // 检查 terminal 的 backgroundColor
        let tbg = term.backgroundColor
        fputs("[RemoteTV] terminal.backgroundColor=r:\(tbg.red) g:\(tbg.green) b:\(tbg.blue)\n", stderr)

        // 检查第一行第一个 cell 和最后一行第一个 cell 的背景色
        let cellFirst = term.getCharData(col: 0, row: 0)
        let lastRow = term.rows - 1
        let cellLast = term.getCharData(col: 0, row: lastRow)
        fputs("[RemoteTV] cell(0,0).bg=\(String(describing: cellFirst?.attribute.bg)) cell(0,\(lastRow)).bg=\(String(describing: cellLast?.attribute.bg))\n", stderr)
    }

    /// 应用主题
    func applyTheme(_ theme: TerminalTheme) {
        currentTheme = theme
        fputs("[RemoteTV] applyTheme: \(theme.name) bg=(\(theme.background.0),\(theme.background.1),\(theme.background.2)) hasLayer=\(layer != nil)\n", stderr)

        let bg = NSColor(
            calibratedRed: CGFloat(theme.background.0) / 255,
            green: CGFloat(theme.background.1) / 255,
            blue: CGFloat(theme.background.2) / 255, alpha: 1)

        // 1. 设置前景/背景/光标色
        nativeForegroundColor = NSColor(
            calibratedRed: CGFloat(theme.foreground.0) / 255,
            green: CGFloat(theme.foreground.1) / 255,
            blue: CGFloat(theme.foreground.2) / 255, alpha: 1)
        nativeBackgroundColor = bg
        caretColor = NSColor(
            calibratedRed: CGFloat(theme.cursor.0) / 255,
            green: CGFloat(theme.cursor.1) / 255,
            blue: CGFloat(theme.cursor.2) / 255, alpha: 1)

        // 2. 安装 ANSI 调色板 — installColors 内部调 colorsChanged() 清除缓存触发全屏重绘
        let ansi: [SwiftTerm.Color] = theme.ansiColors.map { (r, g, b) in
            SwiftTerm.Color(red: UInt16(r) << 8, green: UInt16(g) << 8, blue: UInt16(b) << 8)
        }
        if ansi.count >= 16 {
            installColors(ansi)  // 这会触发 colorsChanged() → 清缓存 → 重绘
        }

        // 3. 同步 layer 背景色（填充 cell 之外的区域）
        wantsLayer = true
        layer?.backgroundColor = bg.cgColor
        fputs("[RemoteTV] applyTheme done: nativeBg=\(nativeBackgroundColor) layerBg=\(String(describing: layer?.backgroundColor))\n", stderr)
    }

    /// 设置字体大小
    func setFontSize(_ size: CGFloat) {
        let f = NSFont(name: font.fontName, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        font = f
        syncLayerBackground()
    }

    // MARK: - TerminalViewDelegate (must be public to satisfy SwiftTerm's public protocol)

    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        remoteDelegate?.sendData(source: self, data: Data(data))
    }

    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        remoteDelegate?.sizeChanged(source: self, newCols: newCols, newRows: newRows)
    }

    public func setTerminalTitle(source: TerminalView, title: String) {
        remoteDelegate?.setTerminalTitle(source: self, title: title)
    }

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        remoteDelegate?.hostCurrentDirectoryUpdate(source: self, directory: directory)
    }

    public func scrolled(source: TerminalView, position: Double) {}
    public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    public func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    public func bell(source: TerminalView) { NSSound.beep() }

    public func clipboardCopy(source: TerminalView, content: Data) {
        if let str = String(bytes: content, encoding: .utf8) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([str as NSString])
        }
    }

    public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}

