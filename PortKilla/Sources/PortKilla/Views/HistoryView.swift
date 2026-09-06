import SwiftUI

struct HistoryView: View {
    @ObservedObject var portManager: PortManager
    @ObservedObject private var history = HistoryManager.shared

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let exportFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Time")
                    .frame(width: 60, alignment: .leading)
                Text("Port")
                    .frame(width: 50, alignment: .leading)
                Text("Process")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Action")
                    .frame(width: 100, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if history.history.isEmpty {
                VStack {
                    Spacer()
                    Text("No history yet")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(history.history) { item in
                        HStack {
                            Text(formatDate(item.timestamp))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .leading)

                            Text(":\(String(item.port))")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 50, alignment: .leading)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.processName)
                                    .font(.system(size: 12))
                                if let provenance = provenance(of: item) {
                                    Text(provenance)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 6) {
                                Spacer()
                                Text(item.action.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.red)

                                // The same server tends to come back — offer a re-kill
                                if isPortActiveAgain(item.port) {
                                    Button("Kill again") {
                                        killAgain(item)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .help("Port :\(String(item.port)) is occupied again")
                                }
                            }
                            .frame(width: 100, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Button("Export CSV") {
                    exportHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Clear History") {
                    HistoryManager.shared.clearHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 430, height: 400)
    }


    private func isPortActiveAgain(_ port: Int) -> Bool {
        portManager.activePorts.contains { $0.port == port }
    }

    /// "started by Claude Code · killed by port guard"
    private func provenance(of item: PortHistoryItem) -> String? {
        var parts: [String] = []
        if let owner = item.owner { parts.append("started by \(owner)") }
        if let killedBy = item.killedBy, killedBy != KillInitiator.user.rawValue { parts.append("killed by \(killedBy)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func killAgain(_ item: PortHistoryItem) {
        guard let target = portManager.activePorts.first(where: { $0.port == item.port }) else { return }

        var message = "This will terminate '\(target.processName)' (PID \(target.pid))."
        if case .warn(let reason) = KillDecision.forHuman(target: target.agentOwner) {
            message += "\n\n\(reason)"
        }
        let confirmed = KillConfirm.run(title: "Kill Process on :\(target.port)?", message: message)
        if confirmed {
            portManager.killPort(target)
        }
    }

    private func formatDate(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
    
    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "PortKilla_History_\(Int(Date().timeIntervalSince1970)).csv"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let csvContent = CSV.historyDocument(history.history, formatter: Self.exportFormatter)
                do {
                    try csvContent.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }
    
}
