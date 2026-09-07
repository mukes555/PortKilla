// swift-tools-version: 5.9
import PackageDescription

// Three products, one core:
// - PortNannyCore: models, scanner, attribution, kill decision, history, the
//   CLI and the MCP server. Foundation only, no AppKit, so it is testable
//   without the app and links light.
// - PortNanny: the menu bar app (AppKit/SwiftUI) on top of the core. It also
//   answers CLI invocations, so existing symlinks keep working.
// - portnanny: the standalone CLI binary the cask links; no AppKit, so
//   `portnanny mcp` stays small when an agent keeps one running.
let package = Package(
    name: "PortNanny",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PortNanny", targets: ["PortNanny"]),
        // Not "portnanny": on a case-insensitive volume that is the same file
        // as the app's "PortNanny" and the two links clobber each other.
        .executable(name: "portnanny-cli", targets: ["portnanny-cli"]),
        .library(name: "PortNannyCore", targets: ["PortNannyCore"]),
    ],
    targets: [
        .target(
            name: "CLibProc",
            path: "Sources/CLibProc"
        ),
        .target(
            name: "PortNannyCore",
            dependencies: ["CLibProc"],
            path: "Sources/PortNannyCore"
        ),
        .executableTarget(
            name: "PortNanny",
            dependencies: ["PortNannyCore"],
            path: "Sources/PortNanny"
        ),
        .executableTarget(
            name: "portnanny-cli",
            dependencies: ["PortNannyCore"],
            path: "Sources/portnanny-cli"
        ),
        .testTarget(
            name: "PortNannyTests",
            dependencies: ["PortNannyCore", "PortNanny"]
        ),
    ]
)
