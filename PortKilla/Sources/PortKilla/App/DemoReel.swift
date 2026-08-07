import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Renders the README demo GIF: a scripted search → kill → "port is free"
/// sequence over fabricated data, drawn offscreen (no screen recording needed).
extension AppDelegate {

    private static let demoSize = NSSize(width: 500, height: 600)

    func renderDemoReel(to path: String) {
        UserDefaults.standard.set(true, forKey: "PortKilla.didDismissHotkeyTip")

        let manager = PortManager()
        manager.stopAutoRefresh()
        manager.hideSystemProcesses = true
        manager.activeTests = [Self.demoTest]
        manager.watchedPorts = [3000]
        manager.activePorts = Self.demoPorts(includePort3000: true)
        manager.lastUpdated = Date()

        let selectedNodeId = manager.activePorts.first { $0.port == 3000 }!.id

        var frames: [(image: NSImage, delay: Double)] = []
        func addFrame(search: String = "", selected: String? = nil, delay: Double) {
            let view = PortListView(portManager: manager, initialSearchText: search, initialSelectedId: selected)
                .environmentObject(self)
            if let image = renderFrame(AnyView(view)) {
                frames.append((image, delay))
            }
        }

        // 1. The full picture
        addFrame(delay: 2.0)

        // 2–4. Typing ":3000" into search
        addFrame(search: "3", delay: 0.45)
        addFrame(search: "300", delay: 0.4)
        addFrame(search: "3000", selected: selectedNodeId, delay: 1.6)

        // 5. Kill: port gone, toast up, search shows the "free" answer state
        manager.activePorts = Self.demoPorts(includePort3000: false)
        manager.toastMessage = "Killed :3000"
        addFrame(search: "3000", delay: 2.0)

        // 6. Back to the list — watched section confirms :3000 is free
        manager.toastMessage = nil
        addFrame(delay: 2.4)

        writeGIF(frames: frames, to: URL(fileURLWithPath: path))
    }

    private func renderFrame(_ view: AnyView) -> NSImage? {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: Self.demoSize)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

        let image = NSImage(size: Self.demoSize)
        image.addRepresentation(rep)
        return image
    }

    private func writeGIF(frames: [(image: NSImage, delay: Double)], to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return }

        let gifProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0] // loop forever
        ] as CFDictionary
        CGImageDestinationSetProperties(destination, gifProperties)

        for frame in frames {
            guard let cgImage = frame.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let frameProperties = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame.delay]
            ] as CFDictionary
            CGImageDestinationAddImage(destination, cgImage, frameProperties)
        }
        CGImageDestinationFinalize(destination)
    }

    // MARK: - Demo data

    private static let demoTest = TestProcessInfo(
        pid: 4101, processName: "node", command: "node node_modules/.bin/vitest --watch",
        memoryUsage: "312MB", memorySizeKB: 319_488, cpuPercent: 46, type: .vitest
    )

    private static func demoPorts(includePort3000: Bool) -> [PortInfo] {
        var ports: [PortInfo] = [
            PortInfo(
                port: 5173, pid: 2002, processName: "node",
                command: "node /Users/dev/projects/my-app/node_modules/.bin/vite",
                user: NSUserName(), memoryUsage: "84MB", memorySizeKB: 86_016, type: .nodejs,
                projectName: "my-app", projectPath: "/Users/dev/projects/my-app",
                bindAddress: "127.0.0.1", cpuPercent: 1.2, age: "2h 14m"
            ),
            PortInfo(
                port: 8080, pid: 2003, processName: "api-server",
                command: "/Users/dev/projects/api/bin/api-server --dev",
                user: NSUserName(), memoryUsage: "24MB", memorySizeKB: 24_576, type: .go,
                projectName: "api", projectPath: "/Users/dev/projects/api",
                bindAddress: "*", cpuPercent: 0.4, age: "3h 2m"
            ),
            PortInfo(
                port: 5432, pid: 903, processName: "postgres",
                command: "/opt/homebrew/opt/postgresql@16/bin/postgres -D /opt/homebrew/var/postgresql@16",
                user: NSUserName(), memoryUsage: "6MB", memorySizeKB: 6_144, type: .database,
                bindAddress: "127.0.0.1", cpuPercent: 0.0, age: "2d 5h"
            ),
            PortInfo(
                port: 6379, pid: 2005, processName: "com.docker.backend",
                command: "/Applications/Docker.app/Contents/MacOS/com.docker.backend",
                user: NSUserName(), memoryUsage: "120MB", memorySizeKB: 122_880, type: .docker,
                containerName: "redis-dev", bindAddress: "127.0.0.1", cpuPercent: 0.8, age: "1d 3h"
            ),
        ]

        if includePort3000 {
            ports.insert(PortInfo(
                port: 3000, pid: 2001, processName: "node",
                command: "node /Users/dev/projects/my-app/node_modules/.bin/next dev",
                user: NSUserName(), memoryUsage: "512MB", memorySizeKB: 524_288, type: .nodejs,
                projectName: "my-app", projectPath: "/Users/dev/projects/my-app",
                children: [PortInfo.ProcessInfo(pid: 2010, name: "node", command: "next-render-worker")],
                bindAddress: "*", cpuPercent: 12.5, age: "4h 32m"
            ), at: 0)
        }

        return ports
    }
}
