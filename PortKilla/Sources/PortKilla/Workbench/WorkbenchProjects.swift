import AppKit
import PortKillaCore
import SwiftUI

/// Ports grouped by the project they run from, with the project's own verbs.
struct WorkbenchProjects: View {
    @ObservedObject var portManager: PortManager
    @Binding var selection: String?

    private var groups: [WorkbenchModel.ProjectGroup] {
        WorkbenchModel.projects(from: portManager.visiblePorts)
    }

    var body: some View {
        if groups.isEmpty {
            WorkbenchEmpty(icon: "folder", text: "No listening ports, so no projects")
        } else {
            List(groups) { group in
                card(for: group)
                    .padding(.vertical, 6)
            }
            .listStyle(.inset)
        }
    }

    private func card(for group: WorkbenchModel.ProjectGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: group.path == nil ? "questionmark.folder" : "folder.fill")
                    .foregroundColor(.accentColor)
                Text(group.name).font(.headline)
                Spacer()
                Text(MemoryFormat.string(kilobytes: group.memoryKB))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let path = group.path {
                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            PortChipRow(ports: group.ports, selection: $selection)
            if !group.agents.isEmpty {
                Text("Agents: \(group.agents.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                if let path = group.path {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    if let editor = EditorLauncher.installed.first {
                        Button("Open in \(editor.name)") { EditorLauncher.open(path: path, with: editor) }
                    }
                }
                Button("Kill all (\(group.ports.count))") {
                    KillFlow(portManager: portManager).requestKillAll(group.ports, label: "Kill \(group.name)")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

/// Clickable ":3000 node" chips; the click selects the port in the inspector.
struct PortChipRow: View {
    let ports: [PortInfo]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ports) { port in
                    Button {
                        selection = port.id
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: port.type.icon)
                                .foregroundColor(Color(nsColor: port.type.color))
                            Text(":\(String(port.port)) \(port.processName)")
                                .font(.caption.monospaced())
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(selection == port.id ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct WorkbenchEmpty: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(text)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
