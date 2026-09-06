// swift-tools-version: 5.9
import PackageDescription

// Three products, one core:
// - PortKillaCore: models, scanner, attribution, kill decision, history, the
//   CLI and the MCP server. Foundation only, no AppKit, so it is testable
//   without the app and links light.
// - PortKilla: the menu bar app (AppKit/SwiftUI) on top of the core. It also
//   answers CLI invocations, so existing symlinks keep working.
// - portkilla: the standalone CLI binary the cask links; no AppKit, so
//   `portkilla mcp` stays small when an agent keeps one running.
let package = Package(
    name: "PortKilla",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PortKilla", targets: ["PortKilla"]),
        .executable(name: "portkilla", targets: ["portkilla-cli"]),
        .library(name: "PortKillaCore", targets: ["PortKillaCore"]),
    ],
    targets: [
        .target(
            name: "CLibProc",
            path: "Sources/CLibProc"
        ),
        .target(
            name: "PortKillaCore",
            dependencies: ["CLibProc"],
            path: "Sources/PortKillaCore"
        ),
        .executableTarget(
            name: "PortKilla",
            dependencies: ["PortKillaCore"],
            path: "Sources/PortKilla"
        ),
        .executableTarget(
            name: "portkilla-cli",
            dependencies: ["PortKillaCore"],
            path: "Sources/portkilla-cli"
        ),
        .testTarget(
            name: "PortKillaTests",
            dependencies: ["PortKillaCore", "PortKilla"]
        ),
    ]
)
