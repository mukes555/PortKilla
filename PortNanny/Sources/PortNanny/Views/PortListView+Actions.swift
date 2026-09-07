import PortNannyCore
import SwiftUI
import Foundation
import AppKit
import Carbon.HIToolbox

/// Virtual key codes by name (Carbon's constants are Int32; NSEvent's are UInt16).
enum KeyCode {
    static let escape = UInt16(kVK_Escape)
    static let `return` = UInt16(kVK_Return)
    static let upArrow = UInt16(kVK_UpArrow)
    static let downArrow = UInt16(kVK_DownArrow)
    static let leftArrow = UInt16(kVK_LeftArrow)
    static let rightArrow = UInt16(kVK_RightArrow)
}

// MARK: - Keyboard handling and kill flows
extension PortListView {

    func installKeyMonitorIfNeeded() {
        // The popover can re-show without a matching onDisappear;
        // guard so shortcuts never stack duplicate monitors.
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event) ? nil : event
        }
    }

    /// Returns true when the event was handled (and should be consumed).
    func handleKeyDown(_ event: NSEvent) -> Bool {
        // Don't hijack keys while a sheet or alert has its own focus.
        guard activeSheet == nil else { return false }
        // Both the popover and the pinned panel host this view; only the
        // copy whose window is key may act, or every shortcut fires twice.
        // With no key window at all (one just closed) the panel copy still
        // answers, as long as the popover isn't the thing on screen.
        let keyWindow = NSApp.keyWindow
        let pinnedIsKey = keyWindow != nil && keyWindow === appDelegate.pinnedPanel
        if hostedInPinnedWindow {
            let nothingIsKey = keyWindow == nil && !appDelegate.popover.isShown
            guard pinnedIsKey || nothingIsKey else { return false }
        } else {
            guard !pinnedIsKey else { return false }
        }

        let hasCommand = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case KeyCode.escape: // clear the search first, then close
            if !searchText.isEmpty {
                searchText = ""
            } else {
                appDelegate.closePopover()
            }
            return true
        case KeyCode.downArrow:
            moveSelection(by: 1)
            return true
        case KeyCode.upArrow:
            moveSelection(by: -1)
            return true
        case KeyCode.rightArrow: // expands the tree, but only when not editing search text
            if searchText.isEmpty, let port = selectedPort, port.children?.isEmpty == false {
                expandedIds.insert(port.id)
                return true
            }
            return false
        case KeyCode.leftArrow:
            if searchText.isEmpty, let port = selectedPort {
                expandedIds.remove(port.id)
                return true
            }
            return false
        case KeyCode.return: // runs the typed verb, else kills the selection; ⌘⏎ force kills
            if runPaletteAction() {
                return true
            }
            if filter == .tests, let test = selectedTest {
                requestKillTest(test, force: hasCommand)
                return true
            }
            if let port = selectedPort {
                requestKill(port, force: hasCommand, killTree: false)
                return true
            }
            return false
        default:
            break
        }

        guard hasCommand, let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch characters {
        case "r":
            portManager.refresh(showToast: true)
            return true
        case "k":
            killAllForCurrentFilter()
            return true
        case "o":
            if let port = selectedPort {
                Browser.openLocalhost(port: port.port)
                return true
            }
            return false
        case "c":
            // Only steal ⌘C from the search field when there's nothing to copy there.
            if searchText.isEmpty, let port = selectedPort {
                Pasteboard.copy("\(port.port)")
                portManager.showToast("Copied \(port.port)")
                return true
            }
            return false
        case "q":
            NSApplication.shared.terminate(nil)
            return true
        default:
            return false
        }
    }

    func moveSelection(by offset: Int) {
        let ids = visibleIdsInOrder
        guard !ids.isEmpty else { return }

        guard let current = selectedId, let index = ids.firstIndex(of: current) else {
            selectedId = offset >= 0 ? ids.first : ids.last
            return
        }
        let next = min(max(index + offset, 0), ids.count - 1)
        selectedId = ids[next]
    }

    var killFlow: KillFlow { KillFlow(portManager: portManager) }

    /// Kills go through the shared flow; the view only keeps the keyboard
    /// position on a neighbour when the killed row disappears.
    func requestKill(_ port: PortInfo, force: Bool, killTree: Bool) {
        if killFlow.requestKill(port, force: force, killTree: killTree) {
            moveSelectionOff(port.id)
        }
    }

    /// The killed row disappears; keep the keyboard position on its neighbour
    /// instead of snapping back to the top of the list.
    func moveSelectionOff(_ id: String) {
        guard selectedId == id else { return }
        let ids = visibleIdsInOrder
        guard let index = ids.firstIndex(of: id) else { return }
        if index + 1 < ids.count {
            selectedId = ids[index + 1]
        } else if index > 0 {
            selectedId = ids[index - 1]
        } else {
            selectedId = nil
        }
    }

    func requestKillTest(_ test: TestProcessInfo, force: Bool = false) {
        killFlow.requestKillTest(test, force: force)
    }

    func requestKillChild(_ child: PortInfo.ProcessInfo) {
        killFlow.requestKillChild(child)
    }

    /// ⌘K and the footer button kill what the active filter shows, never
    /// web servers from behind the Databases tab.
    func killAllForCurrentFilter() {
        if filter == .tests {
            killFlow.requestKillAllTests()
            return
        }
        let targets = portManager.visiblePorts.filter { filter.includesInBulkKill($0) }
        killFlow.requestKillAll(targets, label: filter.bulkKillLabel)
    }
}
