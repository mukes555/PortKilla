import SwiftUI
import AppKit

struct PortListContent: View {
    let groupedPorts: [(key: PortInfo.PortCategory, value: [PortInfo])]
    @ObservedObject var portManager: PortManager
    @Binding var hoverId: String?
    @Binding var selectedId: String?
    @Binding var expandedIds: Set<String>
    let onSelectPort: (PortInfo) -> Void
    let onKillRequest: (PortInfo, _ force: Bool, _ killTree: Bool) -> Void
    let onKillChild: (PortInfo.ProcessInfo) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedPorts, id: \.key) { category, ports in
                        PortSectionView(
                            category: category,
                            ports: ports,
                            portManager: portManager,
                            hoverId: $hoverId,
                            selectedId: $selectedId,
                            expandedIds: $expandedIds,
                            onSelectPort: onSelectPort,
                            onKillRequest: onKillRequest,
                            onKillChild: onKillChild
                        )
                    }
                }
            }
            .onChange(of: selectedId) { newValue in
                if let newValue {
                    proxy.scrollTo(newValue)
                }
            }
        }
    }
}

struct PortSectionView: View {
    let category: PortInfo.PortCategory
    let ports: [PortInfo]
    @ObservedObject var portManager: PortManager
    @Binding var hoverId: String?
    @Binding var selectedId: String?
    @Binding var expandedIds: Set<String>
    let onSelectPort: (PortInfo) -> Void
    let onKillRequest: (PortInfo, _ force: Bool, _ killTree: Bool) -> Void
    let onKillChild: (PortInfo.ProcessInfo) -> Void

    var body: some View {
        Section(header:
            HStack {
                Text(category.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        ) {
            ForEach(ports) { port in
                PortRowView(
                    port: port,
                    manager: portManager,
                    isExpanded: expansionBinding(for: port.id),
                    isSelected: selectedId == port.id,
                    onSelect: { onSelectPort(port) },
                    onKillRequest: { force, killTree in onKillRequest(port, force, killTree) },
                    onKillChild: onKillChild
                )
                    .id(port.id)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(rowBackground(for: port.id))
                    .onHover { isHovering in
                        hoverId = isHovering ? port.id : nil
                    }
                Divider()
            }
        }
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedIds.contains(id) },
            set: { expanded in
                if expanded {
                    expandedIds.insert(id)
                } else {
                    expandedIds.remove(id)
                }
            }
        )
    }

    private func rowBackground(for id: String) -> Color {
        if selectedId == id {
            return Color.accentColor.opacity(0.15)
        }
        if hoverId == id {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }
}

struct PortRowView: View {
    static func chipText(_ text: String, cap: Int = 24) -> String {
        text.count > cap ? text.prefix(cap) + "…" : text
    }

    private var rowTooltip: String {
        var lines = ["PID: \(port.pid)"]
        if let age = port.age {
            lines.append("Running for: \(age)")
        }
        lines.append(String(format: "CPU: %.1f%%", port.cpuPercent))
        lines.append("Command: \(port.command)")
        return lines.joined(separator: "\n")
    }

    let port: PortInfo
    @ObservedObject var manager: PortManager
    @Binding var isExpanded: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onKillRequest: (_ force: Bool, _ killTree: Bool) -> Void
    let onKillChild: (PortInfo.ProcessInfo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Expand/Collapse Button (Process Tree)
                if let children = port.children, !children.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundColor(.secondary)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16)
                } else {
                    Spacer().frame(width: 16)
                }

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
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 160, alignment: .leading)
                                .layoutPriority(1)

                            if manager.isProtectedProcessName(port.processName) {
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                                    .help("Protected: skipped by bulk kill actions")
                            }

                            if manager.isWatched(port.port) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.yellow)
                                    .help("Watched: you'll be notified when this port frees up or gets taken")
                            }

                            if port.isExposed {
                                HStack(spacing: 2) {
                                    Image(systemName: "wifi.exclamationmark")
                                        .font(.system(size: 8))
                                    Text("exposed")
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                }
                                .fixedSize()
                                .foregroundColor(.orange)
                                .padding(.horizontal, 4)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(4)
                                .help("Listening on all interfaces (\(port.bindAddress ?? "*")) — reachable from your local network")
                            }

                        }

                        // Second line: project and container chips (the useful
                        // bits), then the command path with leftover space.
                        HStack(spacing: 4) {
                            Text("└─")
                                .foregroundColor(.secondary)
                            if port.proto == "udp" {
                                Text("UDP")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 3)
                                    .background(Color.purple.opacity(0.12))
                                    .cornerRadius(3)
                                    .fixedSize()
                            }
                            // Chips truncate at the string level and render at
                            // fixed size — layout-level truncation kept stealing
                            // width from its HStack siblings.
                            if let project = port.projectName {
                                Text(Self.chipText(project))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                                    .fixedSize()
                                    .help(port.projectPath ?? project)
                            }
                            if let container = port.containerName {
                                HStack(spacing: 2) {
                                    Image(systemName: "shippingbox")
                                        .font(.system(size: 8))
                                    Text(Self.chipText(container))
                                        .font(.system(size: 10))
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                                .fixedSize()
                                .help(container)
                            }
                            Text(port.command)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(rowTooltip)

                    // Memory
                    Text(port.memoryUsage)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Click anywhere on the row to toggle expansion if children exist
                    if let children = port.children, !children.isEmpty {
                        isExpanded.toggle()
                    } else {
                        onSelect()
                    }
                }

                // Action
                HStack(spacing: 6) {
                    Button(action: onSelect) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show details for \(port.processName) on port \(port.port)")
                    .help("Show Details")

                    Button(action: {
                        // Option = force kill (SIGKILL), Shift = kill process tree
                        let force = NSEvent.modifierFlags.contains(.option)
                        let killTree = NSEvent.modifierFlags.contains(.shift)
                        onKillRequest(force, killTree)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kill \(port.processName) on port \(port.port)")
                    .help("Click to kill. Option+Click to force kill. Shift+Click to kill process tree.")
                }
                .frame(width: 80, alignment: .trailing)
            }
            .contextMenu {
                Button("Open in Browser") {
                    Browser.openLocalhost(port: port.port)
                }
                Button(manager.isWatched(port.port) ? "Unwatch :\(String(port.port))" : "Watch :\(String(port.port))") {
                    manager.toggleWatch(port.port)
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
                Button("Kill Process Tree") {
                    manager.killPort(port, killTree: true)
                }
                Button("Force Kill (SIGKILL)") {
                    manager.killPort(port, force: true)
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

            // Expanded Children View
            if isExpanded, let children = port.children, !children.isEmpty {
                ForEach(children) { child in
                    HStack {
                        Spacer().frame(width: 36) // Indent

                        Image(systemName: "arrow.turn.down.right")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.system(size: 10))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(child.name)
                                .font(.system(size: 12))
                            Text("PID: \(String(child.pid))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: { onKillChild(child) }) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Kill child process \(child.name)")
                        .help("Kill \(child.name)")
                        .padding(.trailing, 12)
                    }
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.05))
                }
            }
        }
    }
}
