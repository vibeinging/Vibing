//
//  ThemeManager.swift
//  VibeTerminal
//
//  Terminal theme system
//

import SwiftUI

// MARK: - Terminal Theme

struct TerminalTheme: Equatable, Identifiable {
    var id: String { name }
    let name: String

    // Core colors (r, g, b)
    let background: (UInt8, UInt8, UInt8)
    let foreground: (UInt8, UInt8, UInt8)
    let cursor: (UInt8, UInt8, UInt8)
    let selection: (UInt8, UInt8, UInt8)

    // ANSI 16 colors
    let ansiColors: [(UInt8, UInt8, UInt8)]

    // Font settings
    let fontName: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let letterSpacing: CGFloat

    // Window
    let backgroundOpacity: CGFloat
    let cursorStyle: String

    // SwiftUI convenience
    var backgroundSwiftUI: SwiftUI.Color {
        SwiftUI.Color(red: Double(background.0) / 255, green: Double(background.1) / 255, blue: Double(background.2) / 255)
    }

    var foregroundSwiftUI: SwiftUI.Color {
        SwiftUI.Color(red: Double(foreground.0) / 255, green: Double(foreground.1) / 255, blue: Double(foreground.2) / 255)
    }

    // Metal SIMD4 conversions
    func backgroundSIMD4() -> SIMD4<UInt8> {
        SIMD4(background.0, background.1, background.2, UInt8(backgroundOpacity * 255))
    }

    func foregroundSIMD4() -> SIMD4<UInt8> {
        SIMD4(foreground.0, foreground.1, foreground.2, 255)
    }

    static func == (lhs: TerminalTheme, rhs: TerminalTheme) -> Bool {
        lhs.name == rhs.name
    }
}

// MARK: - Built-in Themes

extension TerminalTheme {
    static let dracula = TerminalTheme(
        name: "Dracula",
        background: (40, 42, 54), foreground: (248, 248, 242),
        cursor: (248, 248, 242), selection: (68, 71, 90),
        ansiColors: [
            (33, 34, 44), (255, 85, 85), (80, 250, 123), (241, 250, 140),
            (98, 114, 164), (255, 121, 198), (139, 233, 253), (248, 248, 242),
            (98, 114, 164), (255, 110, 110), (105, 255, 148), (255, 255, 165),
            (123, 139, 189), (255, 146, 223), (164, 255, 255), (255, 255, 255),
        ],
        fontName: "Menlo", fontSize: 13, lineHeight: 1.2, letterSpacing: 0,
        backgroundOpacity: 1.0, cursorStyle: "block"
    )

    static let oneDark = TerminalTheme(
        name: "One Dark",
        background: (40, 44, 52), foreground: (171, 178, 191),
        cursor: (82, 139, 255), selection: (62, 68, 81),
        ansiColors: [
            (40, 44, 52), (224, 108, 117), (152, 195, 121), (229, 192, 123),
            (97, 175, 239), (198, 120, 221), (86, 182, 194), (171, 178, 191),
            (92, 99, 112), (224, 108, 117), (152, 195, 121), (229, 192, 123),
            (97, 175, 239), (198, 120, 221), (86, 182, 194), (255, 255, 255),
        ],
        fontName: "Menlo", fontSize: 13, lineHeight: 1.2, letterSpacing: 0,
        backgroundOpacity: 1.0, cursorStyle: "block"
    )

    static let nord = TerminalTheme(
        name: "Nord",
        background: (46, 52, 64), foreground: (216, 222, 233),
        cursor: (216, 222, 233), selection: (67, 76, 94),
        ansiColors: [
            (59, 66, 82), (191, 97, 106), (163, 190, 140), (235, 203, 139),
            (129, 161, 193), (180, 142, 173), (136, 192, 208), (229, 233, 240),
            (76, 86, 106), (191, 97, 106), (163, 190, 140), (235, 203, 139),
            (129, 161, 193), (180, 142, 173), (143, 188, 187), (236, 239, 244),
        ],
        fontName: "Menlo", fontSize: 13, lineHeight: 1.2, letterSpacing: 0,
        backgroundOpacity: 1.0, cursorStyle: "block"
    )

    static let tokyoNight = TerminalTheme(
        name: "Tokyo Night",
        background: (26, 27, 38), foreground: (169, 177, 214),
        cursor: (199, 208, 245), selection: (42, 46, 68),
        ansiColors: [
            (21, 22, 30), (247, 118, 142), (158, 206, 106), (224, 175, 104),
            (122, 162, 247), (187, 154, 247), (125, 207, 255), (169, 177, 214),
            (65, 72, 104), (247, 118, 142), (158, 206, 106), (224, 175, 104),
            (122, 162, 247), (187, 154, 247), (125, 207, 255), (199, 208, 245),
        ],
        fontName: "Menlo", fontSize: 13, lineHeight: 1.2, letterSpacing: 0,
        backgroundOpacity: 1.0, cursorStyle: "block"
    )

    static let catppuccinMocha = TerminalTheme(
        name: "Catppuccin Mocha",
        background: (30, 30, 46), foreground: (205, 214, 244),
        cursor: (245, 224, 220), selection: (88, 91, 112),
        ansiColors: [
            (69, 71, 90), (243, 139, 168), (166, 227, 161), (249, 226, 175),
            (137, 180, 250), (245, 194, 231), (148, 226, 213), (186, 194, 222),
            (88, 91, 112), (243, 139, 168), (166, 227, 161), (249, 226, 175),
            (137, 180, 250), (245, 194, 231), (148, 226, 213), (205, 214, 244),
        ],
        fontName: "Menlo", fontSize: 13, lineHeight: 1.2, letterSpacing: 0,
        backgroundOpacity: 1.0, cursorStyle: "block"
    )

    static let solarizedDark = TerminalTheme(
        name: "Solarized Dark",
        background: (0, 43, 54), foreground: (131, 148, 150),
        cursor: (131, 148, 150), selection: (7, 54, 66),
        ansiColors: [
            (7, 54, 66), (220, 50, 47), (133, 153, 0), (181, 137, 0),
            (38, 139, 210), (211, 54, 130), (42, 161, 152), (238, 232, 213),
            (0, 43, 54), (203, 75, 22), (88, 110, 117), (101, 123, 131),
            (131, 148, 150), (108, 113, 196), (147, 161, 161), (253, 246, 227),
        ],
        fontName: "Menlo", fontSize: 13, lineHeight: 1.2, letterSpacing: 0,
        backgroundOpacity: 1.0, cursorStyle: "block"
    )

    static let gruvbox = TerminalTheme(
        name: "Gruvbox Dark",
        background: (40, 40, 40), foreground: (235, 219, 178),
        cursor: (235, 219, 178), selection: (80, 73, 69),
        ansiColors: [
            (40, 40, 40), (204, 36, 29), (152, 151, 26), (215, 153, 33),
            (69, 133, 136), (177, 98, 134), (104, 157, 106), (168, 153, 132),
            (146, 131, 116), (251, 73, 52), (184, 187, 38), (250, 189, 47),
            (131, 165, 152), (211, 134, 155), (142, 192, 124), (235, 219, 178),
        ],
        fontName: "Menlo", fontSize: 13, lineHeight: 1.2, letterSpacing: 0,
        backgroundOpacity: 1.0, cursorStyle: "block"
    )
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    @Published var currentTheme: TerminalTheme

    let builtinThemes: [TerminalTheme] = [
        .dracula, .oneDark, .nord, .tokyoNight, .catppuccinMocha, .solarizedDark, .gruvbox
    ]

    @Published var customThemes: [TerminalTheme] = []

    var allThemes: [TerminalTheme] {
        builtinThemes + customThemes
    }

    init() {
        let savedName = UserDefaults.standard.string(forKey: "selectedTheme") ?? "Tokyo Night"
        let all: [TerminalTheme] = [.dracula, .oneDark, .nord, .tokyoNight, .catppuccinMocha, .solarizedDark, .gruvbox]
        self.currentTheme = all.first(where: { $0.name == savedName }) ?? .tokyoNight
    }

    func applyTheme(_ theme: TerminalTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.name, forKey: "selectedTheme")
        // 通知 SwiftTerm 视图更新主题
        NotificationCenter.default.post(name: .init("ThemeChanged"), object: theme)
    }

    func nextTheme() {
        let themes = allThemes
        guard let idx = themes.firstIndex(where: { $0.name == currentTheme.name }) else { return }
        let next = (idx + 1) % themes.count
        applyTheme(themes[next])
    }
}
