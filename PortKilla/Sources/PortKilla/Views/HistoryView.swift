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
}
