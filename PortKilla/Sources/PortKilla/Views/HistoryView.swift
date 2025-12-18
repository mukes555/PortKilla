import SwiftUI

struct HistoryView: View {
    @State private var historyItems: [PortHistoryItem] = []

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
                    .frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if historyItems.isEmpty {
                VStack {
                    Spacer()
                    Text("No history yet")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(historyItems) { item in
                        HStack {
                            Text(formatDate(item.timestamp))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .leading)

                            Text(":\(String(item.port))")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 50, alignment: .leading)

                            Text(item.processName)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(item.action.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(item.action == .killed ? .red : .green)
                                .frame(width: 60, alignment: .trailing)
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
                    loadHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 350, height: 400)
        .onAppear {
            loadHistory()
        }
    }

    private func loadHistory() {
        historyItems = HistoryManager.shared.history
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "PortKilla_History_\(Int(Date().timeIntervalSince1970)).csv"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let csvContent = generateCSV()
                do {
                    try csvContent.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save history: \(error)")
                }
            }
        }
    }
    
    private func generateCSV() -> String {
        var csv = "Timestamp,Port,Process,Action\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        for item in historyItems {
            let line = "\(formatter.string(from: item.timestamp)),\(item.port),\(item.processName),\(item.action.rawValue)\n"
            csv.append(line)
        }
        return csv
    }
}
