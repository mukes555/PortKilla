// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PortKilla",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PortKilla", targets: ["PortKilla"])
    ],
    targets: [
        .target(
            name: "CLibProc",
            path: "Sources/CLibProc"
        ),
        .executableTarget(
            name: "PortKilla",
            dependencies: ["CLibProc"],
            path: "Sources/PortKilla"
        ),
        .testTarget(
            name: "PortKillaTests",
            dependencies: ["PortKilla"]
        ),
    ]
)
