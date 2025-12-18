import Cocoa

struct Theme {
    // Soft, modern light theme palette
    static let background = NSColor.windowBackgroundColor
    static let text = NSColor.labelColor
    static let textSecondary = NSColor.secondaryLabelColor
    
    // Process Type Colors (Softer versions)
    static let nodejs = NSColor.systemGreen
    static let database = NSColor.systemYellow
    static let webserver = NSColor.systemOrange
    static let other = NSColor.systemGray
    
    // UI Elements
    static let selection = NSColor.selectedContentBackgroundColor
    static let separator = NSColor.separatorColor
    
    // Typography
    static func font(size: CGFloat = 13.0, bold: Bool = false) -> NSFont {
        return bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    }
    
    static func monoFont(size: CGFloat = 12.0) -> NSFont {
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
