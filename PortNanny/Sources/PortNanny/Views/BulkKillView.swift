import PortNannyCore
import SwiftUI
import AppKit

struct BulkKillView: View {
    @ObservedObject var portManager: PortManager
    @Environment(\.dismiss) private var dismiss

    @State private var minPortText = ""
    @State private var maxPortText = ""
    @State private var projectContains = ""
    @State private var commandContains = ""
    @State private var includeProtected = false
    @State private var forceKill = false

    private var minPort: Int? {
        let trimmed = minPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private var maxPort: Int? {
        let trimmed = maxPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private var isPortRangeValid: Bool {
        if let minPort, let maxPort {
            return minPort <= maxPort
        }
        return true
    }

    private var matchingPorts: [PortInfo] {
        if !isPortRangeValid {
            return []
        }

        let projectNeedle = projectContains.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandNeedle = commandContains.trimmingCharacters(in: .whitespacesAndNewlines)

        // visiblePorts: bulk kill honors the hide-system-processes setting
        return portManager.visiblePorts.filter { port in
            if !includeProtected && portManager.isProtectedProcessName(port.processName) {
                return false
            }

            if let minPort, port.port < minPort {
                return false
            }
            if let maxPort, port.port > maxPort {
                return false
            }

            if !projectNeedle.isEmpty {
                guard let projectName = port.projectName else { return false }
                if !projectName.localizedCaseInsensitiveContains(projectNeedle) {
                    return false
                }
            }

            if !commandNeedle.isEmpty {
                if !port.command.localizedCaseInsensitiveContains(commandNeedle) {
                    return false
                }
            }

            return true
        }
        .sorted { $0.port < $1.port }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailTitleBar(onClose: { dismiss() })

            Text("Bulk Kill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Port Range")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("Min", text: $minPortText)
                            .frame(width: 90)
                        Text("to")
                            .foregroundColor(.secondary)
                        TextField("Max", text: $maxPortText)
                            .frame(width: 90)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Contains")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. webapp", text: $projectContains)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command Contains")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. vite", text: $commandContains)
                    }
                }

                if !isPortRangeValid {
                    Text("Port range is invalid (min must be ≤ max).")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack(spacing: 14) {
                    Toggle("Include protected", isOn: $includeProtected)
                    Toggle("Force (SIGKILL)", isOn: $forceKill)
                    Spacer()
                }
                .toggleStyle(.checkbox)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Matches (\(matchingPorts.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if matchingPorts.isEmpty {
                    Text("No ports match the current rules.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 28)
                } else {
                    List(matchingPorts) { port in
                        HStack(spacing: 10) {
                            Text(":\(String(port.port))")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 70, alignment: .leading)
                            Text(port.processName)
                                .lineLimit(1)
                            if let project = port.projectName {
                                Text(project)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("PID \(String(port.pid))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }
            }

            Spacer()

            HStack {
                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Kill \(matchingPorts.count)") {
                    let (killable, supervised) = KillFlow.bulkTargets(matchingPorts, isProtected: portManager.isProtectedProcessName)
                    let count = killable.count
                    if count == 0 {
                        if !supervised.isEmpty {
                            KillConfirm.inform(title: "Nothing to Kill", message: KillFlow.skippedNote(supervised))
                        }
                        return
                    }

                    let listText = killable.prefix(12).map { "• \($0.processName) (:\($0.port))" }.joined(separator: "\n")
                    let suffix = count > 12 ? "\n\n…and \(count - 12) more." : ""
                    let agentNote = KillDecision.liveAgentNote(for: killable.map(\.agentOwner)).map { "\n\n\($0)" } ?? ""
                    let skipped = supervised.isEmpty ? "" : "\n\n" + KillFlow.skippedNote(supervised)

                    let confirmed = KillConfirm.run(
                        title: "Kill \(count) Process\(count == 1 ? "" : "es")?",
                        message: "This will terminate the following:\n\n\(listText)\(suffix)\(agentNote)\(skipped)\n\nAre you sure?"
                    )
                    if confirmed {
                        portManager.killPorts(killable, force: forceKill)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(matchingPorts.isEmpty || !isPortRangeValid)
            }
        }
        .padding()
        // Must fit inside the 500pt-wide popover window it's presented over
        .frame(width: 470, height: 560)
    }
}
