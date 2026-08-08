import Cocoa
import SwiftUI
import Combine
import ImageIO
import UniformTypeIdentifiers

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate, ObservableObject {

    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var pinnedPanel: NSPanel?
    @Published var isPinned = false
    private var hotKey: GlobalHotKey?

    private enum HotKeyDefaults {
        static let keyCode = "PortKilla.hotkeyKeyCode"
        static let modifiers = "PortKilla.hotkeyModifiers"
        static let display = "PortKilla.hotkeyDisplay"
    }

    @Published var hotkeyDisplay: String = GlobalHotKey.defaultDisplay

    let portManager = PortManager()
    var cancellables = Set<AnyCancellable>()

    static func main() {
        // CLI mode: `PortKilla list`, `PortKilla kill 3000`, …
        let arguments = Array(Foundation.ProcessInfo.processInfo.arguments.dropFirst())
        if let exitCode = PortKillaCLI.run(arguments) {
            exit(exitCode)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "PortKilla")
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Observe port changes to update icon
        portManager.$activePorts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBar()
            }
            .store(in: &cancellables)

        // Create popover
        popover = NSPopover()
        let contentView = PortListView(portManager: portManager)
            .environmentObject(self)
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 500, height: 600)
        // Track visibility so PortManager can slow the scan down while hidden.
        popover.delegate = self

        // Redraw the menu bar when its display preference changes
        portManager.onMenuBarPreferenceChanged = { [weak self] in self?.updateMenuBar() }

        // Hide dock icon (make it a background agent / menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        // Global hotkey from anywhere toggles the popover (permission-free
        // Carbon API); the shortcut is user-configurable via the gear menu.
        registerStoredHotKey()

        // First launch: open the popover once so the user finds the app,
        // instead of it silently vanishing into the menu bar.
        let hasLaunchedKey = "PortKilla.hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: hasLaunchedKey) {
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.togglePopover()
            }
        }

        // Developer-only rendering hooks (screenshots, README GIF, CI smoke
        // test). Compiled only in debug builds — never in the shipped app.
        #if DEBUG
        installDevHooks()
        #endif
    }

    #if DEBUG
    /// Offscreen render hooks, driven by PORTKILLA_* env vars. See CONTRIBUTING.md.
    private func installDevHooks() {
        let env = Foundation.ProcessInfo.processInfo.environment

        if env["PORTKILLA_SHOW_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.togglePopover()
            }
        }

        if let snapshotPath = env["PORTKILLA_SNAPSHOT"] {
            let viewName = env["PORTKILLA_SNAPSHOT_VIEW"] ?? "main"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.writeSnapshot(of: viewName, to: snapshotPath)
                NSApp.terminate(nil)
            }
        }

        if let gifPath = env["PORTKILLA_DEMO_GIF"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.renderDemoReel(to: gifPath)
                NSApp.terminate(nil)
            }
        }
    }

    private func writeSnapshot(of viewName: String, to path: String) {
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
        case "detail":
            let port = portManager.activePorts.first ?? PortInfo(
                port: 3000, pid: 1234, processName: "node",
                command: "/usr/local/bin/node server.js", user: NSUserName(),
                memoryUsage: "45MB", memorySizeKB: 46080, type: .nodejs,
                projectName: "my-app", bindAddress: "*"
            )
            view = NSHostingView(rootView: PortDetailView(port: port))
        default:
            view = NSHostingView(rootView: PortListView(portManager: portManager).environmentObject(self))
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

    func updateMenuBar() {
        guard let button = statusItem.button else { return }
        let count = portManager.menuBarBadgeCount
        let active = count > 0

        button.image = NSImage(
            systemSymbolName: active ? "bolt.fill" : "bolt",
            accessibilityDescription: active ? "Active Ports" : "No Active Ports"
        )
        button.title = (active && portManager.showMenuBarCount) ? "\(count)" : ""
    }

    func popoverWillShow(_ notification: Notification) {
        portManager.setPopoverVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        // A pinned window keeps the fast refresh cadence alive
        portManager.setPopoverVisible(isPinned)
    }

    // MARK: - Pinned floating window

    /// A floating panel with the same content, for keeping an eye on ports
    /// while working ("is my build's port free yet?").
    func togglePinnedWindow() {
        if let panel = pinnedPanel {
            panel.close()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "PortKilla"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // The panel is mouse-driven; a second key monitor would double-handle
        // shortcuts alongside the popover's.
        panel.contentViewController = NSHostingController(
            rootView: PortListView(portManager: portManager, installsKeyMonitor: false)
                .environmentObject(self)
        )
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        pinnedPanel = panel
        isPinned = true
        // The pinned window replaces the popover — close it so there aren't
        // two identical copies on screen.
        popover.performClose(nil)
        portManager.setPopoverVisible(true)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === pinnedPanel else { return }
        pinnedPanel = nil
        isPinned = false
        portManager.setPopoverVisible(popover.isShown)
    }

    @objc func togglePopover() {
        // While pinned, there's a floating window already — don't open a second
        // identical popover; just bring the pinned window forward.
        if let panel = pinnedPanel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Bring app to front when popover is shown (optional)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func closePopover() {
        popover.performClose(nil)
    }

    /// Opens the dedicated Settings window (gear icon / ⌘,).
    func openSettings() {
        // The transient popover floats at a high window level and would sit on
        // top of a normal window — close it so Settings is actually visible.
        popover.performClose(nil)

        if settingsWindow == nil {
            let view = SettingsView(portManager: portManager).environmentObject(self)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "PortKilla Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: view)
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    // MARK: - Global hotkey

    private func registerStoredHotKey() {
        let defaults = UserDefaults.standard
        let keyCode = defaults.object(forKey: HotKeyDefaults.keyCode) as? Int
        let modifiers = defaults.object(forKey: HotKeyDefaults.modifiers) as? Int

        hotkeyDisplay = defaults.string(forKey: HotKeyDefaults.display) ?? GlobalHotKey.defaultDisplay
        hotKey = GlobalHotKey(
            keyCode: keyCode.map(UInt32.init) ?? GlobalHotKey.defaultKeyCode,
            modifiers: modifiers.map(UInt32.init) ?? GlobalHotKey.defaultModifiers
        ) { [weak self] in
            self?.togglePopover()
        }
    }

    /// Replaces the global hotkey; returns false if registration failed
    /// (e.g. the combination is taken by the system).
    @discardableResult
    func setHotKey(keyCode: UInt32, carbonModifiers: UInt32, display: String) -> Bool {
        hotKey = nil // Unregister the old one first (deinit)

        guard let newHotKey = GlobalHotKey(keyCode: keyCode, modifiers: carbonModifiers, onPress: { [weak self] in
            self?.togglePopover()
        }) else {
            registerStoredHotKey() // Fall back to the previous shortcut
            return false
        }

        hotKey = newHotKey
        hotkeyDisplay = display
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: HotKeyDefaults.keyCode)
        defaults.set(Int(carbonModifiers), forKey: HotKeyDefaults.modifiers)
        defaults.set(display, forKey: HotKeyDefaults.display)
        return true
    }

    func resetHotKey() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: HotKeyDefaults.keyCode)
        defaults.removeObject(forKey: HotKeyDefaults.modifiers)
        defaults.removeObject(forKey: HotKeyDefaults.display)
        hotKey = nil
        registerStoredHotKey()
    }

    /// URL scheme: portkilla://kill/3000[?force=1], portkilla://show
    ///
    /// A URL can be opened by any webpage the user visits, so a scheme-initiated
    /// kill is never silent: it always asks for confirmation first. (In-app
    /// kills have their own confirmation flow / explicit modifier keys.)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host {
            case "kill":
                guard let portNumber = Int(url.lastPathComponent) else { break }
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let force = components?.queryItems?.contains { $0.name == "force" && $0.value == "1" } ?? false
                confirmAndKillFromURL(port: portNumber, force: force)
            case "show":
                if !popover.isShown {
                    togglePopover()
                }
            default:
                break
            }
        }
    }

    private func confirmAndKillFromURL(port: Int, force: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let confirmed = KillConfirm.run(
            title: "Kill process on :\(port)?",
            message: "A link asked PortKilla to \(force ? "force-" : "")kill whatever is listening on :\(port). Only continue if you initiated this."
        )
        if confirmed {
            // respectProtected: a link must not be able to kill a protected process
            portManager.killPortNumber(port, force: force, respectProtected: true)
        }
    }

    func showHistory() {
        if historyWindow == nil {
            let historyView = HistoryView(portManager: portManager)
            historyWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            historyWindow?.center()
            historyWindow?.title = "PortKilla History"
            historyWindow?.contentViewController = NSHostingController(rootView: historyView)
            historyWindow?.isReleasedWhenClosed = false
        }

        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
