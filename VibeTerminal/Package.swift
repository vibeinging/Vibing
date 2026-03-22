// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeTerminal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "VibeTerminal",
            targets: ["VibeTerminal"]
        )
    ],
    dependencies: [
        // 可以添加依赖包
    ],
    targets: [
        .executableTarget(
            name: "VibeTerminal",
            dependencies: [],
            path: ".",
            exclude: [
                "README.md",
                "Package.swift"
            ],
            sources: [
                "VibeTerminalApp.swift",
                "Models/AccountManager.swift",
                "Views/ContentView.swift",
                "Views/SettingsView.swift",
                "Views/WorkingTerminalView.swift",
                "Views/TerminalInputView.swift",
                "Rendering/TerminalMetalView.swift",
                "Rendering/OptimizedMetalRenderer.swift",
                "Network/TerminalProtocol.swift",
                "Network/TerminalWebSocketClient.swift",
                "Network/BinaryProtocolEncoder.swift",
                "IPC/SharedMemoryBuffer.swift",
                "IPC/LocalPTYConnection.swift",
                "Terminal/PTYSession.swift",
                "Terminal/VT100Parser.swift"
            ],
            resources: [
                .process("Resources/Shaders.metal")
            ],
            cSettings: [
                .headerSearchPath("."),
                .define("IOKIT_DEPRECATED", to: "1", .when(platforms: [.macOS]))
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Metal"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("CoreImage")
            ]
        )
    ]
)
