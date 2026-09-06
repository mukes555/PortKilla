import Foundation

struct PortHistoryItem: Identifiable, Codable {
    let id: UUID
    let port: Int
    let processName: String
    let timestamp: Date
    let action: HistoryAction
    /// Agent that had started the process, and who stopped it ("you", "port
    /// guard", "link"). Optional so entries from older versions still decode.
    let owner: String?
    let killedBy: String?

    enum HistoryAction: String, Codable {
        case detected = "Detected"
        case killed = "Killed"
    }

    init(port: Int, processName: String, action: HistoryAction, owner: String? = nil, killedBy: String? = nil) {
        self.id = UUID()
        self.port = port
        self.processName = processName
        self.timestamp = Date()
        self.action = action
        self.owner = owner
        self.killedBy = killedBy
    }
}

enum CSV {
    /// The History export, one row per entry. Every column goes through
    /// `field` so a future column can't silently bypass the defence.
    static func historyDocument(_ items: [PortHistoryItem], formatter: DateFormatter) -> String {
        var csv = "Timestamp,Port,Process,Action,Owner,Killed By\n"
        for item in items {
            let fields = [
                formatter.string(from: item.timestamp),
                "\(item.port)",
                item.processName,
                item.action.rawValue,
                item.owner ?? "",
                item.killedBy ?? ""
            ].map(field)
            csv.append(fields.joined(separator: ",") + "\n")
        }
        return csv
    }

    /// Escapes a value for a CSV cell, defusing spreadsheet formula injection
    /// (process names are attacker-influenced: a name like "=cmd|..." would
    /// otherwise execute when the export is opened in Excel).
    static func field(_ raw: String) -> String {
        var value = raw
        // Tab and carriage return are formula lead-ins for Excel as well.
        if let first = value.first, "=+-@\t\r".contains(first) {
            value = "'" + value
        }

        let needsQuoting = value.contains(",") || value.contains("\"")
            || value.contains("\n") || value.contains("\r")
        if needsQuoting {
            value = "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

/// Kill history, newest first, capped by the History preference. Observable
/// so the History window updates while it is open; `defaults` is injectable
/// so tests never touch the user's real history.
final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var history: [PortHistoryItem] = []
    private let defaults: UserDefaults

    /// Set from the History preference; trimming applies immediately.
    var maxHistoryItems = 50 {
        didSet { trimAndSave() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadHistory()
    }

    func addEntry(port: Int, processName: String, action: PortHistoryItem.HistoryAction,
                  owner: String? = nil, killedBy: String? = nil) {
        let item = PortHistoryItem(port: port, processName: processName, action: action, owner: owner, killedBy: killedBy)
        history.insert(item, at: 0)
        trimAndSave()
    }

    private func trimAndSave() {
        if history.count > maxHistoryItems {
            history = Array(history.prefix(maxHistoryItems))
        }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: DefaultsKey.history)
        }
    }

    private func loadHistory() {
        if let data = defaults.data(forKey: DefaultsKey.history),
           let items = try? JSONDecoder().decode([PortHistoryItem].self, from: data) {
            history = items
        }
    }

    func clearHistory() {
        history.removeAll()
        defaults.removeObject(forKey: DefaultsKey.history)
    }
}
