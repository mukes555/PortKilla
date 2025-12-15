import Foundation

struct PortHistoryItem: Identifiable, Codable {
    let id: UUID
    let port: Int
    let processName: String
    let timestamp: Date
    let action: HistoryAction
    
    enum HistoryAction: String, Codable {
        case detected = "Detected"
        case killed = "Killed"
    }
    
    init(port: Int, processName: String, action: HistoryAction) {
        self.id = UUID()
        self.port = port
        self.processName = processName
        self.timestamp = Date()
        self.action = action
    }
}

class HistoryManager {
    static let shared = HistoryManager()
    
    private let kHistoryKey = "portHistory"
    private let maxHistoryItems = 50
    
    private(set) var history: [PortHistoryItem] = []
    
    private init() {
        loadHistory()
    }
    
    func addEntry(port: Int, processName: String, action: PortHistoryItem.HistoryAction) {
        let item = PortHistoryItem(port: port, processName: processName, action: action)
        history.insert(item, at: 0)
        
        if history.count > maxHistoryItems {
            history = Array(history.prefix(maxHistoryItems))
        }
        
        saveHistory()
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: kHistoryKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: kHistoryKey),
           let items = try? JSONDecoder().decode([PortHistoryItem].self, from: data) {
            history = items
        }
    }
    
    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: kHistoryKey)
    }
}
