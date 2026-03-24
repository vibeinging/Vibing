//
//  TerminalMetalView.swift
//  VibeTerminal
//
//  终端 Metal 视图 - 显示终端内容
//

import UIKit
import MetalKit

// MARK: - Delegate Protocol
protocol TerminalMetalViewDelegate: AnyObject {
    func terminalView(_ view: TerminalMetalView, didReceiveKeyPress keyEvent: KeyPressEvent)
    func terminalViewDidChangeSize(_ view: TerminalMetalView, cols: Int, rows: Int)
}

// MARK: - Key Event
struct KeyPressEvent {
    enum KeyType {
        case character(Character)
        case enter
        case tab
        case backspace
        case escape
        case arrowUp
        case arrowDown
        case arrowLeft
        case arrowRight
        case home
        case end
        case pageUp
        case pageDown
        case delete
        case insert
        case f(UInt8)  // F1-F12
    }

    let key: KeyType
    var modifiers: KeyModifiers

    struct KeyModifiers: OptionSet {
        let rawValue: UInt8
        static let control = KeyModifiers(rawValue: 1 << 0)
        static let alt = KeyModifiers(rawValue: 1 << 1)
        static let shift = KeyModifiers(rawValue: 1 << 2)
        static let meta = KeyModifiers(rawValue: 1 << 3)
    }
}

// MARK: - Terminal Metal View
class TerminalMetalView: MTKView {

    // MARK: - Properties

    private var renderer: MetalRenderer?
    private var terminalState: TerminalState

    // 屏幕尺寸（字符网格）
    var gridCols: Int = 80 {
        didSet {
            if gridCols != oldValue {
                updateGridSize()
            }
        }
    }

    var gridRows: Int = 24 {
        didSet {
            if gridRows != oldValue {
                updateGridSize()
            }
        }
    }

    // 字体度量
    private var fontWidth: CGFloat = 10
    private var fontHeight: CGFloat = 20

    weak var delegate: TerminalMetalViewDelegate?

    // 键盘状态
    private var controlKeyActive = false
    private var altKeyActive = false

    // MARK: - Initialization

    override init(frame frameRect: CGRect) {
        // 计算初始行列数
        let fontSize: CGFloat = 14
        let font = UIFont(name: "Menlo", size: fontSize) ??
                   UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // 获取字符尺寸
        let charSize = "X".size(withAttributes: [.font: font])
        fontWidth = charSize.width
        fontHeight = font.lineHeight

        let estimatedCols = Int(frameRect.width / fontWidth)
        let estimatedRows = Int(frameRect.height / fontHeight)

        self.gridCols = max(40, estimatedCols)
        self.gridRows = max(15, estimatedRows)

        self.terminalState = TerminalState(cols: gridCols, rows: gridRows)

        super.init(frame: frameRect)

        setup()
    }

    required init(coder aDecoder: NSCoder) {
        let fontSize: CGFloat = 14
        let font = UIFont(name: "Menlo", size: fontSize) ??
                   UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let charSize = "X".size(withAttributes: [.font: font])
        fontWidth = charSize.width
        fontHeight = font.lineHeight

        self.gridCols = 80
        self.gridRows = 24
        self.terminalState = TerminalState(cols: gridCols, rows: gridRows)

        super.init(coder: aDecoder)

        setup()
    }

    private func setup() {
        // Metal 设置
        self.device = MTLCreateSystemDefaultDevice()
        self.clearColor = MTLClearColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1.0)
        self.framebufferOnly = false
        self.isPaused = true
        self.enableSetNeedsDisplay = false

        guard let device = self.device else {
            print("Metal is not supported on this device")
            return
        }

        // 创建渲染器
        self.renderer = MetalRenderer(device: device, metalKitView: self)
        self.delegate = self

        // 设置手势
        setupGestures()

        // 添加键盘观察者
        setupKeyboardObservers()

        // 添加双击复制功能
        setupContextMenu()
    }

    // MARK: - Setup Helpers

    private func setupGestures() {
        // 点击设置焦点
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)

        // 长按显示菜单
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPressGesture)
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidChangeFrame(_:)),
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil
        )
    }

    private func setupContextMenu() {
        // iOS 13+ 的上下文菜单
        if #available(iOS 13.0, *) {
            let interaction = UIContextMenuInteraction(delegate: self)
            self.addInteraction(interaction)
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        // 计算新的行列数
        let newCols = Int(bounds.width / fontWidth)
        let newRows = Int(bounds.height / fontHeight)

        if newCols != gridCols || newRows != gridRows {
            gridCols = max(40, newCols)
            gridRows = max(15, newRows)
            updateGridSize()
        }
    }

    private func updateGridSize() {
        terminalState.resize(cols: gridCols, rows: gridRows)
        delegate?.terminalViewDidChangeSize(self, cols: gridCols, rows: gridRows)
        setNeedsDisplay()
    }

    // MARK: - Data Update

    /// 更新脏区域
    func update(dirtyRegions: [ProtocolDirtyRegion]) {
        for region in dirtyRegions {
            applyDirtyRegion(region)
        }

        // 触发重绘
        triggerRedraw()
    }

    /// 设置完整状态（用于初始同步）
    func setFullState(_ state: FullStateFrame, cols: Int, rows: Int) {
        let newCols = Int(state.cols)
        let newRows = Int(state.rows)

        if newCols != gridCols || newRows != gridRows {
            gridCols = newCols
            gridRows = newRows
            terminalState.resize(cols: gridCols, rows: gridRows)
        }

        // 应用所有单元格
        var cellGrid: [[TerminalCell]] = Array(repeating: Array(repeating: TerminalCell(), count: newCols),
                                                count: newRows)

        for (index, cellData) in state.cells.enumerated() {
            let y = index / newCols
            let x = index % newCols

            guard y < newRows, x < newCols else { continue }

            var cell = TerminalCell()
            cell.char = Character(cellData.char.first ?? " ")
            cell.fgColor = cellData.fgColor
            cell.bgColor = cellData.bgColor
            cell.attrs = cellData.attrs

            cellGrid[y][x] = cell
        }

        terminalState.updateRegion(cells: cellGrid, x: 0, y: 0)

        // 更新光标
        updateCursor(state.cursor)

        triggerRedraw()
    }

    /// 更新光标
    func updateCursor(_ cursor: ProtocolCursorFrame) {
        terminalState.setCursor(x: Int(cursor.x), y: Int(cursor.y))
        terminalState.setCursorVisible(cursor.visible)

        switch cursor.style {
        case .block:
            terminalState.setCursorStyle(.block)
        case .underline:
            terminalState.setCursorStyle(.underline)
        case .bar:
            terminalState.setCursorStyle(.bar)
        }

        triggerRedraw()
    }

    private func applyDirtyRegion(_ region: ProtocolDirtyRegion) {
        let startX = Int(region.x)
        let startY = Int(region.y)
        let width = Int(region.width)
        let height = Int(region.height)

        for y in 0..<height {
            let rowY = startY + y
            guard rowY < terminalState.rows else { continue }

            for x in 0..<width {
                let colX = startX + x
                guard colX < terminalState.cols else { continue }

                let cellIndex = y * Int(width) + x
                guard cellIndex < region.cells.count else { continue }

                let cellData = region.cells[cellIndex]
                var cell = TerminalCell()
                cell.char = Character(cellData.char.first ?? " ")
                cell.fgColor = cellData.fgRGBA
                cell.bgColor = cellData.bgRGBA
                cell.attrs = cellData.attrs.rawValue

                terminalState.setCell(cell, atX: colX, y: rowY)
            }
        }
    }

    private func triggerRedraw() {
        isPaused = false
        needsDisplay = true
    }

    // MARK: - Gesture Handlers

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        becomeFirstResponder()
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            becomeFirstResponder()

            // 显示选项菜单（如果实现了 UIMenuController）
            // UIMenuController.shared.showMenu(from: self, rect: bounds)
        }
    }

    // MARK: - Keyboard

    @objc func keyboardWillShow(_ notification: Notification) {
        updateKeyboardInset(notification)
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        updateKeyboardInset(notification)
    }

    @objc func keyboardDidChangeFrame(_ notification: Notification) {
        updateKeyboardInset(notification)
    }

    private func updateKeyboardInset(_ notification: Notification) {
        guard let info = notification.userInfo,
              let keyboardFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        // 通知父视图控制器键盘状态变化
        // 可以通过 delegate 或 NotificationCenter 传递
    }

    // MARK: - Key Input

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []

        // Enter
        commands.append(UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(handleEnterKey)))

        // Tab
        commands.append(UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTabKey)))

        // Escape
        commands.append(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscapeKey)))

        // 箭头键
        commands.append(UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleArrowUp)))
        commands.append(UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleArrowDown)))
        commands.append(UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handleArrowLeft)))
        commands.append(UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleArrowRight)))

        // Home/End
        commands.append(UIKeyCommand(input: UIKeyCommand.inputHome, modifierFlags: [], action: #selector(handleHome)))
        commands.append(UIKeyCommand(input: UIKeyCommand.inputEnd, modifierFlags: [], action: #selector(handleEnd)))

        // Page Up/Down
        commands.append(UIKeyCommand(input: UIKeyCommand.inputPageUp, modifierFlags: [], action: #selector(handlePageUp)))
        commands.append(UIKeyCommand(input: UIKeyCommand.inputPageDown, modifierFlags: [], action: #selector(handlePageDown)))

        // Backspace/Delete
        commands.append(UIKeyCommand(input: "\u{8}", modifierFlags: [], action: #selector(handleBackspace)))
        commands.append(UIKeyCommand(input: "\u{127}", modifierFlags: [], action: #selector(handleDelete)))

        // F1-F12
        for i in 1...12 {
            if let input = fKeyInput(i) {
                commands.append(UIKeyCommand(input: input, modifierFlags: [], action: #selector(handleFKey(_:))))
            }
        }

        // Ctrl 组合键
        commands.append(UIKeyCommand(input: "c", modifierFlags: .control, action: #selector(handleCtrlC)))
        commands.append(UIKeyCommand(input: "d", modifierFlags: .control, action: #selector(handleCtrlD)))
        commands.append(UIKeyCommand(input: "l", modifierFlags: .control, action: #selector(handleCtrlL)))
        commands.append(UIKeyCommand(input: "a", modifierFlags: .control, action: #selector(handleCtrlA)))
        commands.append(UIKeyCommand(input: "e", modifierFlags: .control, action: #selector(handleCtrlE)))

        return commands
    }

    // MARK: - Key Actions

    private func sendKey(_ keyType: KeyPressEvent.KeyType, modifiers: KeyPressEvent.KeyModifiers = []) {
        let event = KeyPressEvent(key: keyType, modifiers: modifiers)
        delegate?.terminalView(self, didReceiveKeyPress: event)
    }

    @objc private func handleEnterKey() {
        sendKey(.enter)
    }

    @objc private func handleTabKey() {
        sendKey(.tab)
    }

    @objc private func handleEscapeKey() {
        sendKey(.escape)
    }

    @objc private func handleArrowUp() {
        sendKey(.arrowUp)
    }

    @objc private func handleArrowDown() {
        sendKey(.arrowDown)
    }

    @objc private func handleArrowLeft() {
        sendKey(.arrowLeft)
    }

    @objc private func handleArrowRight() {
        sendKey(.arrowRight)
    }

    @objc private func handleHome() {
        sendKey(.home)
    }

    @objc private func handleEnd() {
        sendKey(.end)
    }

    @objc private func handlePageUp() {
        sendKey(.pageUp)
    }

    @objc private func handlePageDown() {
        sendKey(.pageDown)
    }

    @objc private func handleBackspace() {
        sendKey(.backspace)
    }

    @objc private func handleDelete() {
        sendKey(.delete)
    }

    @objc private func handleFKey(_ keyCommand: UIKeyCommand) {
        // Determine which F key based on input
        if let input = keyCommand.input {
            switch input {
            case UIKeyCommand.inputF1: sendKey(.f(1))
            case UIKeyCommand.inputF2: sendKey(.f(2))
            case UIKeyCommand.inputF3: sendKey(.f(3))
            case UIKeyCommand.inputF4: sendKey(.f(4))
            case UIKeyCommand.inputF5: sendKey(.f(5))
            case UIKeyCommand.inputF6: sendKey(.f(6))
            case UIKeyCommand.inputF7: sendKey(.f(7))
            case UIKeyCommand.inputF8: sendKey(.f(8))
            case UIKeyCommand.inputF9: sendKey(.f(9))
            case UIKeyCommand.inputF10: sendKey(.f(10))
            case UIKeyCommand.inputF11: sendKey(.f(11))
            case UIKeyCommand.inputF12: sendKey(.f(12))
            default: break
            }
        }
    }

    @objc private func handleCtrlC() {
        sendKey(.character("C"), modifiers: .control)
    }

    @objc private func handleCtrlD() {
        sendKey(.character("D"), modifiers: .control)
    }

    @objc private func handleCtrlL() {
        sendKey(.character("L"), modifiers: .control)
    }

    @objc private func handleCtrlA() {
        sendKey(.character("A"), modifiers: .control)
    }

    @objc private func handleCtrlE() {
        sendKey(.character("E"), modifiers: .control)
    }

    private func fKeyInput(_ index: Int) -> String? {
        switch index {
        case 1: return UIKeyCommand.inputF1
        case 2: return UIKeyCommand.inputF2
        case 3: return UIKeyCommand.inputF3
        case 4: return UIKeyCommand.inputF4
        case 5: return UIKeyCommand.inputF5
        case 6: return UIKeyCommand.inputF6
        case 7: return UIKeyCommand.inputF7
        case 8: return UIKeyCommand.inputF8
        case 9: return UIKeyCommand.inputF9
        case 10: return UIKeyCommand.inputF10
        case 11: return UIKeyCommand.inputF11
        case 12: return UIKeyCommand.inputF12
        default: return nil
        }
    }

    // MARK: - Input Accessory View

    private var keyboardAccessoryView: KeyboardAccessoryView?

    override var inputAccessoryView: UIView? {
        if keyboardAccessoryView == nil {
            let accessory = KeyboardAccessoryView()
            accessory.delegate = self
            keyboardAccessoryView = accessory
        }
        return keyboardAccessoryView
    }

    // MARK: - Cleanup

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - MTKViewDelegate
extension TerminalMetalView: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // 尺寸变化由 layoutSubviews 处理
    }

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let renderer = renderer else {
            return
        }

        renderer.render(state: terminalState, in: drawable)
    }
}

// MARK: - UIContextMenuInteractionDelegate
@available(iOS 13.0, *)
extension TerminalMetalView: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                               configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggestedActions in
            return UIMenu(title: "Terminal", children: [
                UIAction(title: "Clear", image: UIImage(systemName: "trash")) { [weak self] _ in
                    // 清屏操作
                },
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                    // 复制操作
                },
                UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { _ in
                    // 粘贴操作
                }
            ])
        }
    }
}

// MARK: - KeyboardAccessoryDelegate
extension TerminalMetalView: KeyboardAccessoryDelegate {

    func accessoryView(_ view: KeyboardAccessoryView, didPressKey key: AccessoryKey, modifiers: KeyModifiers) {
        let keyType: KeyPressEvent.KeyType
        let eventModifiers = convertModifiers(modifiers)

        switch key {
        case .escape:
            keyType = .escape
        case .tab:
            keyType = .tab
        case .arrowUp:
            keyType = .arrowUp
        case .arrowDown:
            keyType = .arrowDown
        case .arrowLeft:
            keyType = .arrowLeft
        case .arrowRight:
            keyType = .arrowRight
        case .home:
            keyType = .home
        case .end:
            keyType = .end
        case .pageUp:
            keyType = .pageUp
        case .pageDown:
            keyType = .pageDown
        case .insert:
            keyType = .insert
        case .delete:
            keyType = .delete
        case .f(let num):
            keyType = .f(num)
        case .character(let char):
            if char.count == 1, let c = char.first {
                keyType = .character(c)
            } else {
                keyType = .character(char.first ?? " ")
            }
        case .modifier, .functionKey:
            return // 这些键通过 modifier 状态变化处理
        }

        let event = KeyPressEvent(key: keyType, modifiers: eventModifiers)
        delegate?.terminalView(self, didReceiveKeyPress: event)
    }

    func accessoryViewDidChangeModifierState(_ view: KeyboardAccessoryView, modifiers: KeyModifiers) {
        // 修饰符状态变化时更新内部状态
        // 可以在这里更新 UI 显示或保存状态
    }

    private func convertModifiers(_ modifiers: KeyModifiers) -> KeyPressEvent.KeyModifiers {
        var result: KeyPressEvent.KeyModifiers = []
        if modifiers.contains(.control) {
            result.insert(.control)
        }
        if modifiers.contains(.alt) {
            result.insert(.alt)
        }
        if modifiers.contains(.shift) {
            result.insert(.shift)
        }
        if modifiers.contains(.meta) {
            result.insert(.meta)
        }
        return result
    }
}

