import Cocoa
import SwiftUI
import Combine

@main
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var historyWindow: NSWindow?

    let portManager = PortManager()
    var cancellables = Set<AnyCancellable>()

    // Toggle state for menu bar display
    var showMemoryState = false
    var displayTimer: Timer?

    static func main() {
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

        // Start toggle timer (every 3 seconds)
        displayTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.showMemoryState.toggle()
            self.updateMenuBar()
        }

        // Create popover
        popover = NSPopover()
        let contentView = PortListView(portManager: portManager)
            .environmentObject(self)
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 400, height: 500)

        // Request permissions
        requestAccessibilityPermissions()

        // Hide dock icon (make it a background agent / menu bar app only)
        NSApp.setActivationPolicy(.accessory)
    }

    func updateMenuBar() {
        guard let button = statusItem.button else { return }
        let count = portManager.activePorts.count

        if count > 0 {
            // Active state
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Active Ports")
            button.title = "\(count)"
        } else {
            // Idle state
            button.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "No Active Ports")
            button.title = ""
        }
    }

    @objc func togglePopover() {
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

    func showHistory() {
        if historyWindow == nil {
            let historyView = HistoryView()
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

    func requestAccessibilityPermissions() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
    }
}
