import PortNannyCore
import SwiftUI
import AppKit

/// Right-click actions for a port row. Kills go back through the row's
/// request closure so the shared confirmation flow applies.
struct PortRowContextMenu: View {
    let port: PortInfo
    let manager: PortManager // unobserved: read when the menu opens
    let onSelect: () -> Void
    let onKillRequest: (_ force: Bool, _ killTree: Bool) -> Void

    var body: some View {
        Button("Open in Browser") {
            Browser.openLocalhost(port: port.port)
        }
        Button(manager.isWatched(port.port) ? "Stop Watching :\(String(port.port))" : "Watch :\(String(port.port))") {
            manager.toggleWatch(port.port)
        }
        Button(manager.isGuarded(port.port) ? "Remove Guard on :\(String(port.port))" : "Guard :\(String(port.port))") {
            GuardConfirm.toggle(port.port, in: manager)
        }
        Button("Show Details") {
            onSelect()
        }
        if let projectPath = port.projectPath {
            Divider()
            ForEach(EditorLauncher.installed, id: \.name) { editor in
                Button("Open Project in \(editor.name)") {
                    EditorLauncher.open(path: projectPath, with: editor)
                }
            }
            Button("Reveal Project in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: projectPath)])
            }
            Button("Open Project in Terminal") {
                NSWorkspace.shared.open(
                    [URL(fileURLWithPath: projectPath)],
                    withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
            Button("Copy Project Path") {
                Pasteboard.copy(projectPath)
            }
        }
        Divider()
        // Through the same request path as the button, so the
        // confirm-before-kill setting applies to the menu too.
        Button("Kill Process Tree") {
            onKillRequest(false, true)
        }
        Button("Force Kill (SIGKILL)") {
            onKillRequest(true, false)
        }
        Divider()
        if let container = port.containerName {
            Button("Stop Docker Container") {
                manager.stopDockerContainer(container)
            }
            Divider()
        }
        Button("Copy Port") {
            Pasteboard.copy(":\(port.port)")
        }
        Button("Copy PID") {
            Pasteboard.copy("\(port.pid)")
        }
        Button("Copy Command") {
            Pasteboard.copy(port.command)
        }
    }
}
