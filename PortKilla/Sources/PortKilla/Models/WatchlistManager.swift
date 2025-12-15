import Foundation

class WatchlistManager: ObservableObject {
    static let shared = WatchlistManager()
    
    private let kWatchlistKey = "portWatchlist"
    
    @Published var watchedPorts: Set<Int> = []
    
    private init() {
        loadWatchlist()
    }
    
    func toggleWatch(_ port: Int) {
        if watchedPorts.contains(port) {
            watchedPorts.remove(port)
        } else {
            watchedPorts.insert(port)
        }
        saveWatchlist()
    }
    
    func isWatched(_ port: Int) -> Bool {
        return watchedPorts.contains(port)
    }
    
    private func saveWatchlist() {
        if let data = try? JSONEncoder().encode(watchedPorts) {
            UserDefaults.standard.set(data, forKey: kWatchlistKey)
        }
    }
    
    private func loadWatchlist() {
        if let data = UserDefaults.standard.data(forKey: kWatchlistKey),
           let items = try? JSONDecoder().decode(Set<Int>.self, from: data) {
            watchedPorts = items
        }
    }
}
