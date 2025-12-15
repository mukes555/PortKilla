import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    var popover: NSPopover!
    // Hold a strong reference to the view controller
    var contentViewController: PortListViewController!

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
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "PortKilla")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        contentViewController = PortListViewController()
        popover.contentViewController = contentViewController
        popover.behavior = .transient
        popover.animates = true

        // Request permissions
        requestAccessibilityPermissions()
        
        // Hide dock icon (make it a background agent / menu bar app only)
        NSApp.setActivationPolicy(.accessory)
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

    func requestAccessibilityPermissions() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
    }
}
