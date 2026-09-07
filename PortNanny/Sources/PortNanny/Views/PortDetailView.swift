import PortNannyCore
import SwiftUI

struct PortDetailView: View {
    let port: PortInfo
    @Environment(\.dismiss) private var dismiss

    private var executablePath: String? {
        let trimmed = port.command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailTitleBar(onClose: { dismiss() })

            HStack(alignment: .top) {
                Image(systemName: port.type.icon)
                    .font(.title2)
                    .foregroundColor(Color(nsColor: port.type.color))

                VStack(alignment: .leading, spacing: 2) {
                    Text(port.processName)
                        .font(.headline)
                    Text(":\(String(port.port)) • PID \(String(port.pid))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { Browser.openLocalhost(port: port.port) }) {
                    Image(systemName: "safari")
                }
                .buttonStyle(.plain)
                .help("Open http://localhost:\(port.port)")

                Menu {
                    Button("Copy Port") { Pasteboard.copy(":\(port.port)") }
                    Button("Copy PID") { Pasteboard.copy("\(port.pid)") }
                    Button("Copy Command") { Pasteboard.copy(port.command) }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .menuStyle(BorderlessButtonMenuStyle())
            }

            Divider()

            Group {
                DetailRow(label: "User", value: port.user)
                DetailRow(label: "Memory", value: port.memoryUsage)
                DetailRow(label: "Type", value: port.type.rawValue)
                if let bind = port.bindAddress {
                    DetailRow(label: "Bind", value: port.isExposed ? "\(bind) (exposed to network)" : bind)
                }
                DetailRow(label: "Proto", value: port.proto.uppercased())
                DetailRow(label: "Clients", value: port.connections == 0 ? "none connected" : "\(port.connections) connected")
                DetailRow(label: "CPU", value: String(format: "%.1f%%", port.cpuPercent))
                if let age = port.age {
                    DetailRow(label: "Age", value: age)
                }
                if let agent = port.agentOwner {
                    DetailRow(label: "Agent", value: agent.detail)
                }
                if let managed = port.managedBy {
                    DetailRow(label: "Managed by", value: "\(managed.label); \(managed.consequence)")
                }
                if let project = port.projectName {
                    DetailRow(label: "Project", value: project)
                }
                if let exec = executablePath {
                    DetailRow(label: "Executable", value: exec)
                }
                if let container = port.containerName {
                    DetailRow(label: "Container", value: container)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Command")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(port.command.isEmpty ? "(No command available)" : port.command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
        // Must fit inside the 500pt-wide popover window it's presented over
        .frame(width: 450, height: 430)
    }
}
