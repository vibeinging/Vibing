//
//  TerminalInputView.swift
//  VibeTerminal
//
//  终端键盘输入处理 - 使用 NSViewController 和 NSEvent
//

import SwiftUI
import AppKit

// MARK: - 终端输入视图（NSViewRepresentable）

struct TerminalInputView: NSViewRepresentable {
    @ObservedObject var viewModel: TerminalViewModel
    let onKeyPress: (KeyPress) -> Bool

    func makeNSView(context: Context) -> TerminalInputNSView {
        let view = TerminalInputNSView()
        view.viewModel = viewModel
        view.onKeyPress = onKeyPress
        return view
    }

    func updateNSView(_ nsView: TerminalInputNSView, context: Context) {
        nsView.viewModel = viewModel
    }
}

// MARK: - 终端输入 NSView

class TerminalInputNSView: NSView {
    weak var viewModel: TerminalViewModel?
    var onKeyPress: ((KeyPress) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) -> Bool {
        guard let handler = onKeyPress else {
            return super.keyDown(with: event)
        }

        let keyPress = KeyPress(nsEvent: event)
        let handled = handler(keyPress)

        if handled {
            // 通知 viewModel 有新输入 - 通过公开方法
            viewModel?.notifyInputReceived()
        }

        return handled
    }

    override func flagsChanged(with event: NSEvent) {
        // 处理修饰键变化（Ctrl, Alt, Shift 等）
        super.flagsChanged(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // 隐藏系统光标
            NSCursor.hide()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            // 显示系统光标
            NSCursor.unhide()
        }
        return result
    }
}

// MARK: - 按键事件

struct KeyPress {
    let key: Key
    let modifiers: NSEvent.ModifierFlags
    let characters: String?

    enum Key {
        case enter
        case tab
        case backspace
        case delete
        case escape
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
        case home
        case end
        case pageUp
        case pageDown
        case f(UInt8)
        case character(Character)
        case unknown
    }

    init(nsEvent: NSEvent) {
        self.modifiers = nsEvent.modifierFlags

        switch nsEvent.keyCode {
        case 36: // Return
            self.key = .enter
            self.characters = "\n"

        case 48: // Tab
            self.key = .tab
            self.characters = "\t"

        case 51: // Delete (Backspace)
            self.key = .backspace
            self.characters = ""

        case 117: // Forward Delete
            self.key = .delete
            self.characters = ""

        case 53: // Escape
            self.key = .escape
            self.characters = "\u{1B}"

        case 126: // Up Arrow
            self.key = .upArrow
            self.characters = "\u{1B}[A"

        case 125: // Down Arrow
            self.key = .downArrow
            self.characters = "\u{1B}[B"

        case 123: // Left Arrow
            self.key = .leftArrow
            self.characters = "\u{1B}[D"

        case 124: // Right Arrow
            self.key = .rightArrow
            self.characters = "\u{1B}[C"

        case 115: // Home
            self.key = .home
            self.characters = "\u{1B}[H"

        case 119: // End
            self.key = .end
            self.characters = "\u{1B}[F"

        case 116: // Page Up
            self.key = .pageUp
            self.characters = "\u{1B}[5~"

        case 121: // Page Down
            self.key = .pageDown
            self.characters = "\u{1B}[6~"

        case 122...125: // F1-F4
            self.key = .f(UInt8(nsEvent.keyCode - 122 + 1))
            self.characters = encodeFKey(UInt8(nsEvent.keyCode - 122 + 1))

        case 0...11: // F5-F12 (需要映射)
            self.key = .unknown
            self.characters = nsEvent.characters

        default:
            if let chars = nsEvent.characters, let char = chars.first {
                self.key = .character(char)
                self.characters = chars
            } else {
                self.key = .unknown
                self.characters = nil
            }
        }
    }

    private func encodeFKey(_ n: UInt8) -> String {
        let codes: [String] = [
            "OP", "OQ", "OR", "OS",  // F1-F4
            "[15~", "[17~", "[18~", "[19~",  // F5-F8
            "[20~", "[21~", "[23~", "[24~"   // F9-F12
        ]
        let index = Int(n - 1)
        if index < codes.count {
            return "\u{1B}\(codes[index])"
        }
        return ""
    }

    var hasControlModifier: Bool {
        modifiers.contains(.control)
    }

    var hasOptionModifier: Bool {
        modifiers.contains(.option)
    }

    var hasShiftModifier: Bool {
        modifiers.contains(.shift)
    }

    var isControlC: Bool {
        hasControlModifier && characters == "c"
    }

    var isControlD: Bool {
        hasControlModifier && characters == "d"
    }
}

// MARK: - 输入处理器

class TerminalInputHandler {
    weak var session: PTYSession?

    func handleKeyPress(_ keyPress: KeyPress) -> Bool {
        // 检查特殊快捷键
        if keyPress.isControlC {
            session?.send([0x03])  // SIGINT
            return true
        }

        if keyPress.isControlD {
            session?.send([0x04])  // EOF
            return true
        }

        // 处理控制组合键
        if keyPress.hasControlModifier, let char = keyPress.characters?.first {
            let code = char.asciiValue ?? 0
            if code >= 0x61 && code <= 0x7A {  // a-z
                session?.send([UInt8(code - 0x61 + 0x01)])
                return true
            }
        }

        // 处理普通按键
        switch keyPress.key {
        case .enter:
            session?.write("\n")

        case .tab:
            session?.write("\t")

        case .backspace:
            session?.send([0x7F])

        case .delete:
            session?.write("\u{1B}[3~")

        case .escape:
            session?.send([0x1B])

        case .upArrow:
            session?.write("\u{1B}[A")

        case .downArrow:
            session?.write("\u{1B}[B")

        case .leftArrow:
            session?.write("\u{1B}[D")

        case .rightArrow:
            session?.write("\u{1B}[C")

        case .home:
            session?.write("\u{1B}[H")

        case .end:
            session?.write("\u{1B}[F")

        case .pageUp:
            session?.write("\u{1B}[5~")

        case .pageDown:
            session?.write("\u{1B}[6~")

        case .f(let n):
            session?.write(encodeFKey(n))

        case .character(let char):
            session?.write(String(char))

        default:
            break
        }

        return true
    }

    private func encodeFKey(_ n: UInt8) -> String {
        switch n {
        case 1...12:
            let codes = [
                "OP", "OQ", "OR", "OS",
                "[15~", "[17~", "[18~", "[19~",
                "[20~", "[21~", "[23~", "[24~"
            ]
            let index = Int(n - 1)
            if index < codes.count {
                return "\u{1B}\(codes[index])"
            }
        default:
            break
        }
        return ""
    }
}
