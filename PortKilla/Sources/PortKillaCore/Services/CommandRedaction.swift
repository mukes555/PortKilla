import Foundation

/// Command lines are attacker-influenced *and* secret-bearing: dev servers
/// are routinely started with `--token=…`, `DATABASE_URL=postgres://u:p@…`,
/// or `Authorization: Bearer …` in their arguments. Anything PortKilla shows,
/// exports, or hands to an agent goes through here first.
public enum CommandRedaction {
    static let mask = "[redacted]"

    private static let sensitiveNames = "(?:token|secret|passw(?:or)?d|api[-_]?key|apikey|auth|credential|private[-_]?key|access[-_]?key)"

    /// A value runs to whitespace or a quote, so `--token='abc'` keeps its
    /// quotes around the mask.
    private static let value = "(['\"]?)([^\\s'\"]+)"

    private static let flagValue = try! NSRegularExpression(pattern: "(?i)(--?[\\w.-]*" + sensitiveNames + "[\\w.-]*)(=|\\s+)" + value)
    private static let envValue = try! NSRegularExpression(pattern: "(?i)\\b([A-Z_]*" + sensitiveNames + "[A-Z_]*)(=)" + value)
    private static let urlPassword = try! NSRegularExpression(pattern: "(://[^/\\s:@]+:)([^@\\s]+)(@)")
    private static let bearer = try! NSRegularExpression(pattern: "(?i)(bearer\\s+)" + value)

    public static func redact(_ command: String) -> String {
        var text = command
        text = replace(flagValue, in: text, with: "$1$2$3" + mask)
        text = replace(envValue, in: text, with: "$1$2$3" + mask)
        text = replace(urlPassword, in: text, with: "$1" + mask + "$3")
        text = replace(bearer, in: text, with: "$1$2" + mask)
        return text
    }

    private static func replace(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
