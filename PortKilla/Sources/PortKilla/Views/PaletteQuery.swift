import Foundation
import PortKillaCore

/// What the search field understood: a filter for the rows and, maybe, a
/// verb to run on Return. "kill 3000" filters to :3000 and offers the kill;
/// "open 5173" opens the browser; "free port" finds one; ">" lists commands.
struct PaletteQuery: Equatable {
    enum Verb: String, CaseIterable {
        case kill, free, stop, open, watch, `guard`

        static let aliases: [String: Verb] = ["k": .kill, "o": .open, "w": .watch, "g": .guard, "unwatch": .watch, "unguard": .guard]

        static func named(_ word: String) -> Verb? {
            Verb(rawValue: word) ?? aliases[word]
        }
    }

    enum Command: String, CaseIterable, Identifiable {
        case refresh = "Refresh"
        case bulkKill = "Bulk Kill…"
        case pin = "Pin as Floating Window"
        case workbench = "Open Workbench"
        case history = "Show History"
        case freePort = "Find a Free Port"
        case settings = "Settings…"
        case tour = "Welcome Tour"
        case quit = "Quit PortKilla"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .refresh: return "arrow.clockwise"
            case .bulkKill: return "trash"
            case .pin: return "pin"
            case .workbench: return "macwindow"
            case .history: return "clock"
            case .freePort: return "number"
            case .settings: return "gearshape"
            case .tour: return "hand.wave"
            case .quit: return "power"
            }
        }
    }

    enum Intent: Equatable {
        case none
        case verb(Verb, port: Int)
        case commands(String)
        case freePort(near: Int)
    }

    let intent: Intent
    /// What the rows are filtered by: "3000" for "kill 3000", the raw text otherwise.
    let rowFilter: String

    var commandMatches: [Command] {
        guard case .commands(let needle) = intent else { return [] }
        guard !needle.isEmpty else { return Command.allCases }
        return Command.allCases.filter { $0.rawValue.lowercased().contains(needle) }
    }

    static func parse(_ text: String) -> PaletteQuery {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return PaletteQuery(intent: .none, rowFilter: "") }

        if trimmed.hasPrefix(">") {
            let needle = trimmed.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
            return PaletteQuery(intent: .commands(needle), rowFilter: "")
        }

        let words = trimmed.split(separator: " ", omittingEmptySubsequences: true).map { $0.lowercased() }
        if let near = freePortRequest(words) {
            return PaletteQuery(intent: .freePort(near: near), rowFilter: "")
        }
        if words.count == 2, let verb = Verb.named(words[0]), let port = portNumber(words[1]) {
            return PaletteQuery(intent: .verb(verb, port: port), rowFilter: String(port))
        }
        return PaletteQuery(intent: .none, rowFilter: trimmed)
    }

    /// "free port", "free-port 8000", "freeport"
    private static func freePortRequest(_ words: [String]) -> Int? {
        let joined = words.joined(separator: " ")
        let forms = ["free port", "free-port", "freeport"]
        guard let form = forms.first(where: { joined == $0 || joined.hasPrefix($0 + " ") }) else { return nil }
        let rest = joined.dropFirst(form.count).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return 3000 }
        return portNumber(rest)
    }

    private static func portNumber(_ word: String) -> Int? {
        let digits = word.hasPrefix(":") ? String(word.dropFirst()) : word
        guard let port = Int(digits), PortManager.isValidPortNumber(port) else { return nil }
        return port
    }
}

/// One matcher for the popover and the Workbench, so a search finds the
/// same rows in both.
enum PortSearch {
    static func matches(_ port: PortInfo, _ needle: String) -> Bool {
        // Plain case-insensitive matching: the locale-aware variant is an
        // ICU call per field per port per keystroke.
        func contains(_ text: String?) -> Bool {
            text?.range(of: needle, options: .caseInsensitive) != nil
        }
        return String(port.port).contains(needle)
            || contains(port.processName)
            || contains(port.command)
            || contains(port.projectName)
            || contains(port.containerName)
            || contains(port.agentOwner?.name)
            || contains(port.managedBy?.name)
            || contains(port.reservation?.owner)
    }
}
