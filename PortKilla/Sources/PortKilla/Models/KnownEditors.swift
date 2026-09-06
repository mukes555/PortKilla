import Foundation

/// Editors and desktop tools, matched as lowercase substrings of a process
/// name. One list serves two purposes that must never drift apart: these are
/// classified as "IDE & Tools" in the list, and they are protected from bulk
/// kills and port guards by default.
enum KnownEditors {
    static let substrings: [String] = [
        "code helper", // VS Code
        "cursor", "trae", "windsurf", "zed", "fleet",
        "xcode", "antigravi", // Google's internal tool
        "intellij", "idea", "pycharm", "webstorm", "phpstorm", "goland", "rider", "rubymine",
        "datagrip", "appcode", "clion", "android studio",
        "sublime text", "atom", "nova", "bbedit", "coteditor", "textmate",
        "google chrome", "slack", "electron",
    ]

    static func matches(_ processName: String) -> Bool {
        let lower = processName.lowercased()
        return substrings.contains { lower.contains($0) }
    }
}
