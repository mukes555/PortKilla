import Cocoa
import SwiftUI
import Combine

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var preferencesWindowController: PreferencesWindow?
    var historyWindowController: NSWindowController?

    let portManager = PortManager()
    var cancellables = Set<AnyCancellable>()

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
            .sink { [weak self] ports in
                self?.updateMenuBarIcon(count: ports.count)
            }
            .store(in: &cancellables)

        // Create popover
        popover = NSPopover()
        let contentView = PortListView(portManager: portManager)
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 400, height: 500)

        // Request permissions
        requestAccessibilityPermissions()

        // Hide dock icon (make it a background agent / menu bar app only)
        NSApp.setActivationPolicy(.accessory)
    }

    func updateMenuBarIcon(count: Int) {
        guard let button = statusItem.button else { return }

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

    func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindow()
        }
        preferencesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showHistory() {
        if historyWindowController == nil {
            let historyView = HistoryView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Port History"
            window.contentViewController = NSHostingController(rootView: historyView)
            window.center()
            historyWindowController = NSWindowController(window: window)
        }
        historyWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func requestAccessibilityPermissions() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
    }
}
