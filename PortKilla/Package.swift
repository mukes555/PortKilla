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
        .executableTarget(
            name: "PortKilla",
            path: "Sources/PortKilla",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
