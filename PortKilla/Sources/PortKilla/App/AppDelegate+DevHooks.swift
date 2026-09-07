import PortKillaCore
import Cocoa
import SwiftUI

// MARK: - Developer render hooks
// Offscreen renders driven by PORTKILLA_* environment variables: README
// screenshots, the demo GIF, and CI's UI smoke test. Debug builds only.
extension AppDelegate {
    #if DEBUG
    /// Offscreen render hooks, driven by PORTKILLA_* env vars. See CONTRIBUTING.md.
    func installDevHooks() {
        let env = Foundation.ProcessInfo.processInfo.environment

        if env["PORTKILLA_SHOW_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.togglePopover()
            }
        }

        if let snapshotPath = env["PORTKILLA_SNAPSHOT"] {
            let viewName = env["PORTKILLA_SNAPSHOT_VIEW"] ?? "main"
            // Render what an open popover shows: full scans, not the light
            // hidden-state ones.
            portManager.setUIVisible(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.writeSnapshot(of: viewName, to: snapshotPath)
                // The live capture quits on its own once it has drawn.
                if viewName != "workbench-live" { NSApp.terminate(nil) }
            }
        }

        if let gifPath = env["PORTKILLA_DEMO_GIF"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.renderDemoReel(to: gifPath)
                NSApp.terminate(nil)
            }
        }
    }

    /// By window id first; by screen region (the window's frame, flipped to
    /// screencapture's top-left origin) when the window server declines.
    private func captureWorkbench(to path: String) {
        guard let window = workbenchWindow, let screen = window.screen ?? NSScreen.main else {
            FileHandle.standardError.write(Data("no workbench window to capture\n".utf8))
            return
        }
        if (try? CommandRunner.run("/usr/sbin/screencapture", ["-x", "-o", "-l", "\(window.windowNumber)", path], timeout: 10)) != nil {
            return
        }
        let frame = window.frame
        let top = screen.frame.maxY - frame.maxY
        let region = "\(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))"
        do {
            _ = try CommandRunner.run("/usr/sbin/screencapture", ["-x", "-R", region, path], timeout: 10)
        } catch {
            FileHandle.standardError.write(Data("screencapture failed by window and by region \(region): \(error)\n".utf8))
        }
    }

    func writeSnapshot(of viewName: String, to path: String) {
        // Seed watched ports so the watched section can be rendered in snapshots
        if let watchList = Foundation.ProcessInfo.processInfo.environment["PORTKILLA_SNAPSHOT_WATCH"] {
            portManager.watchedPorts = Set(watchList.split(separator: ",").compactMap { Int($0) })
        }
        if let density = Foundation.ProcessInfo.processInfo.environment["PORTKILLA_SNAPSHOT_DENSITY"],
           let value = PortManager.ViewDensity(rawValue: density) {
            portManager.viewDensity = value
        }

        let view: NSView
        switch viewName {
        case "bulkkill":
            view = NSHostingView(rootView: BulkKillView(portManager: portManager))
        case "protected":
            view = NSHostingView(rootView: ProtectedProcessListView(portManager: portManager))
        case "settings":
            view = NSHostingView(rootView: SettingsView(portManager: portManager).environmentObject(self))
        case "workbench":
            // PORTKILLA_SNAPSHOT_SECTION=ports|projects|agents|watchlist|history and
            // PORTKILLA_SNAPSHOT_SELECT=<port> pick what the Workbench shows.
            let env = Foundation.ProcessInfo.processInfo.environment
            let section = env["PORTKILLA_SNAPSHOT_SECTION"].flatMap { WorkbenchView.Section(rawValue: $0.capitalized) } ?? .ports
            let selected = env["PORTKILLA_SNAPSHOT_SELECT"].flatMap(Int.init).flatMap { number in portManager.activePorts.first { $0.port == number }?.id }
            view = NSHostingView(rootView: WorkbenchView(portManager: portManager, initialSection: section, initialSelection: selected)
                .environmentObject(self).frame(width: 1380, height: 740))
        case "tour":
            view = NSHostingView(rootView: TourView(portManager: portManager, onFinish: {}).environmentObject(self))
        case "workbench-live":
            // Sidebar material is composited by the window server, so an
            // offscreen render shows it blank: open the real window and let
            // screencapture photograph it (needs Screen Recording permission).
            let env = Foundation.ProcessInfo.processInfo.environment
            let section = env["PORTKILLA_SNAPSHOT_SECTION"].flatMap { WorkbenchView.Section(rawValue: $0.capitalized) } ?? .ports
            let selected = env["PORTKILLA_SNAPSHOT_SELECT"].flatMap(Int.init).flatMap { number in portManager.activePorts.first { $0.port == number }?.id }
            openWorkbench(section: section, selection: selected)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.captureWorkbench(to: path)
                NSApp.terminate(nil)
            }
            return
        case "detail":
            let port = portManager.activePorts.first ?? PortInfo(
                port: 3000, pid: 1234, processName: "node",
                command: "/usr/local/bin/node server.js", user: NSUserName(),
                memoryUsage: "45MB", memorySizeKB: 46080, type: .nodejs,
                projectName: "my-app", bindAddress: "*"
            )
            view = NSHostingView(rootView: PortDetailView(port: port))
        default:
            // PORTKILLA_SNAPSHOT_TEXTSIZE=large renders at an accessibility
            // text size to check that the rows reflow instead of clipping.
            let textSize: DynamicTypeSize = Foundation.ProcessInfo.processInfo.environment["PORTKILLA_SNAPSHOT_TEXTSIZE"] == "large" ? .accessibility1 : .medium
            // PORTKILLA_SNAPSHOT_SEARCH seeds the search field, so the palette
            // bar ("kill 3000", "> ...") can be rendered.
            let search = Foundation.ProcessInfo.processInfo.environment["PORTKILLA_SNAPSHOT_SEARCH"] ?? ""
            view = NSHostingView(rootView: PortListView(portManager: portManager, initialSearchText: search).environmentObject(self).dynamicTypeSize(textSize))
        }

        let size = view.fittingSize == .zero ? NSSize(width: 500, height: 600) : view.fittingSize

        // Host in an offscreen window so the view gets a real appearance chain
        // (otherwise dark-mode colors resolve against a transparent void).
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        switch Foundation.ProcessInfo.processInfo.environment["PORTKILLA_SNAPSHOT_APPEARANCE"] {
        case "light": window.appearance = NSAppearance(named: .aqua)
        case "dark": window.appearance = NSAppearance(named: .darkAqua)
        default: window.appearance = NSApp.effectiveAppearance
        }
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
    #endif
}
