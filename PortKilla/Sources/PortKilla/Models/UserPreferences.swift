import Foundation

class UserPreferences {
    static let shared = UserPreferences()
    
    private let defaults = UserDefaults.standard
    
    // Keys
    private let kRefreshInterval = "refreshInterval"
    private let kShowNotifications = "showNotifications"
    
    var refreshInterval: TimeInterval {
        get {
            let val = defaults.double(forKey: kRefreshInterval)
            return val > 0 ? val : 2.0 // Default to 2.0 seconds
        }
        set {
            defaults.set(newValue, forKey: kRefreshInterval)
        }
    }
    
    var showNotifications: Bool {
        get {
            // Default to true if not set
            return defaults.object(forKey: kShowNotifications) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: kShowNotifications)
        }
    }
}
