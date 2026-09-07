import PortNannyCore
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
    var settingsWindow: NSWindow?
    let settingsRouter = SettingsView.Router()
    var workbenchWindow: NSWindow?
    var tourWindow: NSWindow?
    private(set) var pinnedPanel: NSPanel?
    @Published var isPinned = false
    private var hotKey: GlobalHotKey?
    private var refusalWatcher: RefusalWatcher?


    @Published var hotkeyDisplay: String = GlobalHotKey.defaultDisplay

    let portManager: PortManager = {
        let defaults = AppDelegate.preferenceDefaults
        let history = defaults === UserDefaults.standard ? HistoryManager.shared : HistoryManager(defaults: defaults)
        return PortManager(defaults: defaults, history: history)
    }()
    var cancellables = Set<AnyCancellable>()

    /// Debug renders honour PORTNANNY_DEFAULTS_SUITE for preferences as well
    /// as history, so a snapshot's density or watch list never lands in the
    /// developer's own settings.
    static var preferenceDefaults: UserDefaults {
        #if DEBUG
        if let suite = Foundation.ProcessInfo.processInfo.environment["PORTNANNY_DEFAULTS_SUITE"], !suite.isEmpty,
           let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        #endif
        return .standard
    }

    static func main() {
        // CLI mode: `PortNanny list`, `PortNanny kill 3000`, …
        let arguments = Array(Foundation.ProcessInfo.processInfo.arguments.dropFirst())
        if let exitCode = PortNannyCLI.run(arguments) {
            exit(exitCode)
        }

        // PortKilla's preferences come along on the first run under the new name.
        if preferenceDefaults === UserDefaults.standard { PreferencesMigration.run() }
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
            button.image = MenuBarGlyph.image(portManager.menuBarIcon, active: false)
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Redraw the icon after the port list has changed. (A Combine sink on
        // $activePorts fires before the new value lands, so it needed a
        // run-loop hop; a callback from didSet needs none.)
        portManager.onPortsChanged = { [weak self] in self?.updateMenuBar() }

        // Create popover
        popover = NSPopover()
        let contentView = PortListView(portManager: portManager)
            .environmentObject(self)
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = portManager.popoverSize.dimensions
        // Track visibility so PortManager can slow the scan down while hidden.
        popover.delegate = self

        // Redraw the menu bar when its display preference changes
        portManager.onMenuBarPreferenceChanged = { [weak self] in self?.updateMenuBar() }
        portManager.onPopoverSizeChanged = { [weak self] in self?.applyPopoverSize() }

        // Hide dock icon (make it a background agent / menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        // Global hotkey from anywhere toggles the popover (permission-free
        // Carbon API); the shortcut is user-configurable via the gear menu.
        registerStoredHotKey()

        // A refusal the CLI issues to an agent becomes a notification here.
        refusalWatcher = RefusalWatcher(portManager: portManager) { [weak self] in self?.revealPorts() }

        // First launch: the tour, then the popover, so the app does not
        // silently vanish into the menu bar. An upgrade skips the tour (it
        // stays in the menu) but still sees the popover once per install.
        let defaults = Self.preferenceDefaults
        let isFirstLaunch = !defaults.bool(forKey: DefaultsKey.hasLaunchedBefore)
        if isFirstLaunch {
            defaults.set(true, forKey: DefaultsKey.hasLaunchedBefore)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showTour()
            }
        } else if defaults.object(forKey: DefaultsKey.didFinishTour) == nil {
            defaults.set(true, forKey: DefaultsKey.didFinishTour)
        }

        // Developer-only rendering hooks (screenshots, README GIF, CI smoke
        // test). Compiled only in debug builds — never in the shipped app.
        #if DEBUG
        installDevHooks()
        #endif
    }


    private var menuBarState: (active: Bool, title: String, icon: PortManager.MenuBarIcon)?

    func updateMenuBar() {
        guard let button = statusItem.button else { return }
        let count = portManager.menuBarBadgeCount
        let active = count > 0
        let title = (active && portManager.showMenuBarCount) ? "\(count)" : ""
        let icon = portManager.menuBarIcon

        // Same state, same drawing: skip the AppKit work.
        if let state = menuBarState, state.active == active, state.title == title, state.icon == icon { return }
        menuBarState = (active, title, icon)
        button.image = MenuBarGlyph.image(icon, active: active)
        button.title = title
    }

    /// The popover takes the chosen size at once; the pinned panel grows to
    /// it when it is smaller and keeps whatever the person stretched it to.
    func applyPopoverSize() {
        let size = portManager.popoverSize.dimensions
        popover.contentSize = size
        guard let panel = pinnedPanel else { return }
        panel.minSize = size
        if panel.frame.width < size.width || panel.frame.height < size.height {
            panel.setContentSize(size)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        portManager.setUIVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        // A pinned window or the Workbench keeps the fast refresh cadence alive
        portManager.setUIVisible(isPinned || workbenchIsVisible)
    }

    private var workbenchIsVisible: Bool {
        workbenchWindow?.isVisible ?? false
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
            contentRect: NSRect(origin: .zero, size: portManager.popoverSize.dimensions),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "PortNanny"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.minSize = portManager.popoverSize.dimensions
        panel.contentViewController = NSHostingController(
            rootView: PortListView(portManager: portManager, hostedInPinnedWindow: true)
                .environmentObject(self)
        )
        panel.delegate = self
        // Remember where the user put it (and on which display); centre only
        // the very first time.
        panel.setFrameAutosaveName("PortNannyPinnedWindow")
        if !panel.setFrameUsingName("PortNannyPinnedWindow") {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        pinnedPanel = panel
        isPinned = true
        // The pinned window replaces the popover — close it so there aren't
        // two identical copies on screen.
        popover.performClose(nil)
        portManager.setUIVisible(true)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        if closing === workbenchWindow {
            portManager.setUIVisible(popover.isShown || isPinned)
            return
        }
        guard closing === pinnedPanel else { return }
        pinnedPanel = nil
        isPinned = false
        portManager.setUIVisible(popover.isShown || workbenchIsVisible)
    }

    // MARK: - Tour

    func showTour() {
        popover.performClose(nil)
        if tourWindow == nil {
            let view = TourView(portManager: portManager) { [weak self] in
                self?.tourWindow?.close()
                self?.togglePopover()
            }
            .environmentObject(self)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "Welcome to PortNanny"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: view)
            window.center()
            tourWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        tourWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Workbench

    /// The full-size window: table, projects, agent sessions, watchlist,
    /// history, and an inspector. One instance, remembered position.
    func openWorkbench(section: WorkbenchView.Section = .ports, selection: String? = nil) {
        popover.performClose(nil)
        if workbenchWindow == nil {
            let view = WorkbenchView(portManager: portManager, initialSection: section, initialSelection: selection).environmentObject(self)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1380, height: 740),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "PortNanny Workbench"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: view)
            window.setFrameAutosaveName("PortNannyWorkbench")
            if !window.setFrameUsingName("PortNannyWorkbench") {
                window.center()
            }
            window.delegate = self
            workbenchWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        workbenchWindow?.makeKeyAndOrderFront(nil)
        portManager.setUIVisible(true)
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

    /// Brings the port list forward without toggling it away when it is
    /// already showing.
    func revealPorts() {
        if pinnedPanel != nil || !popover.isShown {
            togglePopover()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Opens the dedicated Settings window (gear icon / ⌘,), at a pane when
    /// something points there.
    func openSettings(pane: SettingsView.Pane? = nil) {
        // The transient popover floats at a high window level and would sit on
        // top of a normal window; close it so Settings is actually visible.
        popover.performClose(nil)
        if let pane { settingsRouter.pane = pane }

        if settingsWindow == nil {
            let view = SettingsView(portManager: portManager, router: settingsRouter).environmentObject(self)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "PortNanny Settings"
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
        let keyCode = defaults.object(forKey: DefaultsKey.hotkeyKeyCode) as? Int
        let modifiers = defaults.object(forKey: DefaultsKey.hotkeyModifiers) as? Int

        hotkeyDisplay = defaults.string(forKey: DefaultsKey.hotkeyDisplay) ?? GlobalHotKey.defaultDisplay
        hotKey = GlobalHotKey(
            keyCode: keyCode.flatMap(Self.storedKeyCode) ?? GlobalHotKey.defaultKeyCode,
            modifiers: modifiers.flatMap(UInt32.init(exactly:)) ?? GlobalHotKey.defaultModifiers
        ) { [weak self] in
            self?.togglePopover()
        }
    }

    /// Preferences are untrusted: a negative or oversized value would trap in
    /// `UInt32(_:)` and crash every launch with no way to recover in-app.
    private static func storedKeyCode(_ value: Int) -> UInt32? {
        guard let code = UInt32(exactly: value), code <= 0x7F else { return nil }
        return code
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
        defaults.set(Int(keyCode), forKey: DefaultsKey.hotkeyKeyCode)
        defaults.set(Int(carbonModifiers), forKey: DefaultsKey.hotkeyModifiers)
        defaults.set(display, forKey: DefaultsKey.hotkeyDisplay)
        return true
    }

    func resetHotKey() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKey.hotkeyKeyCode)
        defaults.removeObject(forKey: DefaultsKey.hotkeyModifiers)
        defaults.removeObject(forKey: DefaultsKey.hotkeyDisplay)
        hotKey = nil
        registerStoredHotKey()
    }

    /// URL scheme: portnanny://kill/3000[?force=1], portnanny://show
    ///
    /// A URL can be opened by any webpage the user visits, so a scheme-initiated
    /// kill is never silent: it always asks for confirmation first. (In-app
    /// kills have their own confirmation flow / explicit modifier keys.)
    func application(_ application: NSApplication, open urls: [URL]) {
        var askedThisDelivery = false
        for url in urls {
            switch URLCommand.parse(url) {
            case .kill(let port, let force):
                // One confirmation per delivery, and a cooldown after it: a page
                // could otherwise stack modal dialogs until one is clicked through.
                guard !askedThisDelivery, urlKillCooldownElapsed else { break }
                askedThisDelivery = true
                lastURLKillAsked = Date()
                confirmAndKillFromURL(port: port, force: force)
            case .show:
                // The URL can arrive during launch, before the popover exists.
                guard popover != nil else { break }
                if !popover.isShown {
                    togglePopover()
                }
            case nil:
                break
            }
        }
    }

    private var lastURLKillAsked = Date.distantPast
    private static let urlKillCooldown: TimeInterval = 3

    private var urlKillCooldownElapsed: Bool {
        Date().timeIntervalSince(lastURLKillAsked) > Self.urlKillCooldown
    }

    private func confirmAndKillFromURL(port: Int, force: Bool) {
        // respectProtected: a link must not be able to kill a protected process
        portManager.killPortNumber(port, force: force, respectProtected: true, initiator: .link) { target in
            NSApp.activate(ignoringOtherApps: true)
            var message = "A link asked PortNanny to \(force ? "force-" : "")kill '\(target.processName)' (PID \(target.pid)) on :\(port). Only continue if you initiated this."
            if case .warn(let reason) = KillDecision.forHuman(target: target.agentOwner) {
                message += "\n\n\(reason)"
            }
            return KillConfirm.run(title: "Kill process on :\(port)?", message: message)
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
            historyWindow?.title = "PortNanny History"
            historyWindow?.contentViewController = NSHostingController(rootView: historyView)
            historyWindow?.isReleasedWhenClosed = false
        }

        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
