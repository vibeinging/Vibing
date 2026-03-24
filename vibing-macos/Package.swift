// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vibing",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Vibing",
            targets: ["Vibing"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Vibing",
            dependencies: ["SwiftTerm"],
            path: ".",
            exclude: [
                "README.md",
                "Package.swift",
                "Info.plist",
                "vibing-server",
                "VibeTerminal",
            ],
            sources: [
                "VibeTerminalApp.swift",
                // Models
                "Models/AccountManager.swift",
                "Models/RelaySessionManager.swift",
                "Models/TabManager.swift",
                "Models/ThemeManager.swift",
                "Models/LaunchConfigManager.swift",
                "Models/ShellDetector.swift",
                // Views — AppKit 主架构
                "Views/AppKit/MainWindowRepresentable.swift",
                "Views/AppKit/MainWindowController.swift",
                "Views/AppKit/TitleBarNSView.swift",
                "Views/AppKit/StatusBarNSView.swift",
                "Views/AppKit/TerminalSplitContainer.swift",
                "Views/AppKit/TerminalPaneController.swift",
                "Views/AppKit/OverlayManager.swift",
                "Views/AppKit/FileTreePanel.swift",
                // Views — SwiftUI overlay（通过 NSHostingView 嵌入）
                "Views/WorkingTerminalView.swift",
                "Views/ShareSessionView.swift",
                "Views/OnboardingView.swift",
                "Views/SearchBarView.swift",
                "Views/CommandPaletteView.swift",
                "Views/SettingsView.swift",
                // Rendering
                "Rendering/SwiftTerminalView.swift",
                // Network
                "Network/TerminalProtocol.swift",
                "Network/TerminalWebSocketClient.swift",
                "Network/BinaryProtocolEncoder.swift",
            ],
            cSettings: [
                .headerSearchPath("."),
                .define("IOKIT_DEPRECATED", to: "1", .when(platforms: [.macOS]))
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        )
    ]
)
