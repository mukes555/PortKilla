import Cocoa

class PreferencesWindow: NSWindowController {
    
    private var refreshSlider: NSSlider!
    private var refreshLabel: NSTextField!
    private var notificationCheckbox: NSButton!
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        self.init(window: window)
        setupUI()
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // Refresh Interval
        let label = NSTextField(labelWithString: "Refresh Interval:")
        label.frame = NSRect(x: 20, y: 140, width: 120, height: 20)
        contentView.addSubview(label)
        
        refreshSlider = NSSlider(value: UserPreferences.shared.refreshInterval, minValue: 1.0, maxValue: 10.0, target: self, action: #selector(sliderChanged(_:)))
        refreshSlider.frame = NSRect(x: 140, y: 140, width: 100, height: 20)
        contentView.addSubview(refreshSlider)
        
        refreshLabel = NSTextField(labelWithString: String(format: "%.1fs", UserPreferences.shared.refreshInterval))
        refreshLabel.frame = NSRect(x: 250, y: 140, width: 40, height: 20)
        contentView.addSubview(refreshLabel)
        
        // Notifications
        notificationCheckbox = NSButton(checkboxWithTitle: "Show Notifications", target: self, action: #selector(checkboxChanged(_:)))
        notificationCheckbox.state = UserPreferences.shared.showNotifications ? .on : .off
        notificationCheckbox.frame = NSRect(x: 20, y: 100, width: 200, height: 20)
        contentView.addSubview(notificationCheckbox)
        
        // Version
        let versionLabel = NSTextField(labelWithString: "v1.0.0")
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.frame = NSRect(x: 20, y: 20, width: 100, height: 20)
        contentView.addSubview(versionLabel)
    }
    
    @objc func sliderChanged(_ sender: NSSlider) {
        let value = round(sender.doubleValue * 10) / 10.0
        refreshLabel.stringValue = String(format: "%.1fs", value)
        UserPreferences.shared.refreshInterval = value
        
        // Notify PortManager to update (we'll need a way to do this, 
        // maybe NotificationCenter or direct access if singleton/shared)
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }
    
    @objc func checkboxChanged(_ sender: NSButton) {
        UserPreferences.shared.showNotifications = sender.state == .on
    }
}

extension Notification.Name {
    static let preferencesChanged = Notification.Name("PreferencesChanged")
}
