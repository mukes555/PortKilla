import Foundation

/// Command lines are attacker-influenced *and* secret-bearing: dev servers
/// are routinely started with `--token=…`, `DATABASE_URL=postgres://u:p@…`,
/// or `Authorization: Bearer …` in their arguments. Anything PortNanny shows,
/// exports, or hands to an agent goes through here first.
public enum CommandRedaction {
    static let mask = "[redacted]"

    private static let sensitiveNames = "(?:token|secret|passw(?:or)?d|api[-_]?key|apikey|auth|credential|private[-_]?key|access[-_]?key)"

    /// A value runs to whitespace or a quote, so `--token='abc'` keeps its
    /// quotes around the mask.
    private static let value = "(['\"]?)([^\\s'\"]+)"

    private static let flagValue = try! NSRegularExpression(pattern: "(?i)(--?[\\w.-]*" + sensitiveNames + "[\\w.-]*)(=|\\s+)" + value)
    private static let envValue = try! NSRegularExpression(pattern: "(?i)\\b([A-Z0-9_]*" + sensitiveNames + "[A-Z0-9_]*)(=)" + value)
    /// A JSON secret: `"token": "abc"`. The value runs to the closing
    /// quote so the mask keeps the quotes.
    private static let quotedValue = try! NSRegularExpression(pattern: "(?i)([\"\']?[\\w.-]*" + sensitiveNames + "[\\w.-]*[\"\']?\\s*:\\s*)([\"\'])([^\"\']+)([\"\'])")
    /// A header secret: `X-API-Key: abc`. "Bearer" is skipped so the token
    /// after it, not the word, is what gets masked.
    private static let headerValue = try! NSRegularExpression(pattern: "(?i)\\b([\\w.-]*" + sensitiveNames + "[\\w.-]*:\\s*)(?!bearer\\b)" + value)
    private static let urlPassword = try! NSRegularExpression(pattern: "(://[^/\\s:@]+:)([^@\\s]+)(@)")
    private static let bearer = try! NSRegularExpression(pattern: "(?i)(bearer\\s+)" + value)

    /// Most command lines carry nothing sensitive; one scan decides that
    /// before the four replacements run on every listener, every refresh.
    private static let anySensitive = try! NSRegularExpression(pattern: "(?i)" + sensitiveNames + "|bearer\\s|://[^/\\s:@]+:[^@\\s]+@")

    /// A control character or C1 escape can hide or spoof terminal output;
    /// process names, paths, and reasons pass through here before printing.
    public static func printable(_ text: String) -> String {
        String(String(text.prefix(4096)).map { ch in
            guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return ch }
            let v = scalar.value
            let isControl = v < 0x20 || (v >= 0x7F && v <= 0x9F)
            return isControl && ch != "\t" ? "\u{FFFD}" : ch
        })
    }

    public static func redact(_ command: String) -> String {
        guard anySensitive.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil else { return command }
        var text = command
        text = replace(flagValue, in: text, with: "$1$2$3" + mask)
        text = replace(envValue, in: text, with: "$1$2$3" + mask)
        text = replace(quotedValue, in: text, with: "$1$2" + mask + "$4")
        text = replace(headerValue, in: text, with: "$1$2" + mask)
        text = replace(urlPassword, in: text, with: "$1" + mask + "$3")
        text = replace(bearer, in: text, with: "$1$2" + mask)
        return text
    }

    private static func replace(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
