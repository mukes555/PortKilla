import SwiftUI

struct PortListView: View {
    @ObservedObject var portManager: PortManager
    @State private var hoverId: UUID?
    @State private var searchText = ""

    // Commands for keyboard shortcuts
    // Note: Global shortcuts are handled by AppDelegate/Menu,
    // but view-specific ones can be here if focused.

    var filteredPorts: [PortInfo] {
        if searchText.isEmpty {
            return portManager.activePorts
        } else {
            return portManager.activePorts.filter { port in
                String(port.port).contains(searchText) ||
                port.processName.localizedCaseInsensitiveContains(searchText) ||
                (port.projectName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Title
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text("PortKilla")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("v1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search ports, processes...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)

            // Column Headers (Optional, kept for clarity but made subtler)
            HStack {
                Text("Port")
                    .frame(width: 80, alignment: .leading)
                Text("Process")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Memory")
                    .frame(width: 70, alignment: .trailing)
                Text("Action")
                    .frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // List
            if filteredPorts.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text(searchText.isEmpty ? "No active ports found" : "No results found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredPorts) { port in
                            PortRowView(port: port, manager: portManager)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(hoverId == port.id ? Color.primary.opacity(0.05) : Color.clear)
                                .onHover { isHovering in
                                    hoverId = isHovering ? port.id : nil
                                }
                            Divider()
                        }
                    }
                }
            }

            Divider()

            // Footer Controls
            VStack(spacing: 0) {
                // Status Bar
                HStack {
                    Text("📊 \(portManager.activePorts.count) ports active")
                    Spacer()
                    Text("Last updated: \(timeAgo(from: portManager.lastUpdated))")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                HStack(spacing: 12) {
                    Button(action: {
                        killAllNode()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Kill All Dev")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Kill all Node.js processes (Cmd+K)")

                    Spacer()

                    Button(action: {
                        portManager.refresh()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Refresh (Cmd+R)")

                    Button(action: {
                        openPreferences()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                            Text("Prefs")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Settings (Cmd+,)")

                    // History Button (Icon only)
                    Button(action: {
                        openHistory()
                    }) {
                        Image(systemName: "clock")
                    }
                    .buttonStyle(.borderless)
                    .help("History")

                    // Quit Button (Icon only)
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Image(systemName: "power")
                    }
                    .buttonStyle(.borderless)
                    .help("Quit PortKilla")
                }
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(width: 400, height: 500)
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func killAllNode() {
        let nodePorts = portManager.activePorts.filter { $0.type == .nodejs }
        let count = nodePorts.count

        if count == 0 {
            let alert = NSAlert()
            alert.messageText = "No Node.js Processes Found"
            alert.informativeText = "There are no active Node.js processes to kill."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let processList = nodePorts.map { "• \($0.processName) (:\($0.port))" }.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Kill \(count) Node.js Processes?"
        alert.informativeText = "This will terminate the following processes:\n\n\(processList)\n\nAre you sure?"
        alert.addButton(withTitle: "Kill All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            portManager.killAllPorts(ofType: .nodejs)
        }
    }

    private func openPreferences() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.showPreferences()
        }
    }

    private func openHistory() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.showHistory()
        }
    }
}

struct PortRowView: View {
    let port: PortInfo
    @ObservedObject var manager: PortManager
    @State private var showConfirmation = false
    @ObservedObject var watchlistManager = WatchlistManager.shared

    var body: some View {
        HStack {
            // Port
            HStack(spacing: 4) {
                Image(systemName: port.type.icon)
                    .foregroundColor(Color(nsColor: port.type.color))
                Text(":\(String(port.port))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .frame(width: 80, alignment: .leading)

            // Process
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(port.processName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    if let project = port.projectName {
                        Text(project)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                // Command Line
                HStack(spacing: 4) {
                    Text("└─")
                        .foregroundColor(.secondary)
                    Text(port.command)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("PID: \(port.pid)\nCommand: \(port.command)")

            // Memory
            Text(port.memoryUsage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            // Action
            HStack(spacing: 4) {
                // Watch Button
                Button(action: {
                    watchlistManager.toggleWatch(port.port)
                }) {
                    Image(systemName: watchlistManager.isWatched(port.port) ? "eye.fill" : "eye")
                        .foregroundColor(watchlistManager.isWatched(port.port) ? .blue : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(watchlistManager.isWatched(port.port) ? "Unwatch port" : "Watch port")

                // Kill Button
                Button(action: {
                    // Check for Option key (Force Kill)
                    if NSEvent.modifierFlags.contains(.option) {
                        manager.killPort(port, force: true)
                    } else {
                        showConfirmation = true
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 60, alignment: .trailing)
            .alert(isPresented: $showConfirmation) {
                Alert(
                    title: Text("Kill Process on :\(port.port)?"),
                    message: Text("Are you sure you want to kill '\(port.processName)' (PID: \(port.pid))?"),
                    primaryButton: .destructive(Text("Kill")) {
                        manager.killPort(port)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}
