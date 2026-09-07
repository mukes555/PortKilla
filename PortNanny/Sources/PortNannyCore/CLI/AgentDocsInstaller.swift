import Foundation

/// `portnanny agent-docs`: the snippet agents need, and the two ways to put
/// it in front of them. Writing into the user's repo is opt-in (`--write`),
/// delimited by markers so it can be updated or removed, and never done by
/// any other command.
public enum AgentDocsInstaller {
    public static let beginMarker = "<!-- portnanny:begin -->"
    public static let endMarker = "<!-- portnanny:end -->"

    public static func run(_ options: CLICommand.AgentDocsOptions) -> Int32 {
        if options.claudeHook {
            print(claudeHook)
            return CLIExit.ok
        }
        guard options.write else {
            print(PortNannyCLI.agentDocs)
            return CLIExit.ok
        }
        do {
            let result = try install(into: URL(fileURLWithPath: options.file))
            print("\(result.rawValue) \(options.file)")
            return CLIExit.ok
        } catch {
            PortNannyCLI.printError("portnanny: could not write \(options.file): \(error.localizedDescription)")
            return CLIExit.killFailed
        }
    }

    public enum Result: String {
        case added = "Added the PortNanny section to"
        case updated = "Updated the PortNanny section in"
        case unchanged = "PortNanny section already current in"
    }

    public static func block() -> String {
        "\(beginMarker)\n\(PortNannyCLI.agentDocs)\n\(endMarker)\n"
    }

    /// What a fresh rule file starts with, so the tool applies it always.
    static func frontmatter(for file: URL) -> String {
        let path = file.path
        if path.hasSuffix(".mdc") {
            return "---\ndescription: Free ports through PortNanny, which knows which AI agent owns each server\nalwaysApply: true\n---\n\n"
        }
        if path.contains("/.windsurf/rules/") {
            return "---\ntrigger: always_on\n---\n\n"
        }
        return ""
    }

    /// Appends the block, or replaces an existing one in place. Creates the
    /// file (and its folders) with the tool's frontmatter when it is new.
    public enum InstallError: LocalizedError {
        case unreadable(String)
        case markersOutOfOrder(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let path): return "\(path) exists but is not readable as UTF-8 text; nothing was written"
            case .markersOutOfOrder(let path): return "\(path) has a portnanny:end marker before its portnanny:begin marker; fix the markers by hand"
            }
        }
    }

    public static func install(into file: URL) throws -> Result {
        // A file that exists but cannot be read must not be replaced by the block alone.
        var existing = ""
        if FileManager.default.fileExists(atPath: file.path) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { throw InstallError.unreadable(file.path) }
            existing = text
        }
        let fresh = block()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let start = existing.range(of: beginMarker), let end = existing.range(of: endMarker) {
            guard start.lowerBound < end.upperBound else { throw InstallError.markersOutOfOrder(file.path) }
            let current = String(existing[start.lowerBound..<end.upperBound]) + "\n"
            if current == fresh { return .unchanged }
            let replaced = existing.replacingCharacters(in: start.lowerBound..<end.upperBound, with: fresh.trimmingCharacters(in: .newlines))
            try replaced.write(to: file, atomically: true, encoding: .utf8)
            return .updated
        }

        let separator = existing.isEmpty || existing.hasSuffix("\n\n") ? "" : (existing.hasSuffix("\n") ? "\n" : "\n\n")
        let head = existing.isEmpty ? frontmatter(for: file) : ""
        try (existing + separator + head + fresh).write(to: file, atomically: true, encoding: .utf8)
        return .added
    }

    /// A Claude Code PreToolUse hook: the habit is intercepted at the point
    /// of the habit. Pure configuration; no daemon.
    public static let claudeHook = """
    Add to .claude/settings.json (project) or ~/.claude/settings.json:

    {
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Bash",
            "hooks": [
              {
                "type": "command",
                "command": "jq -r '.tool_input.command' | grep -Eq 'lsof -t?i[:=]?[0-9]+|fuser -k|kill -9 \\\\$\\\\(lsof' && { echo 'Use `portnanny free <port>` instead of lsof/kill: another agent may own that port (exit 3 = do not force).' >&2; exit 2; } || exit 0"
              }
            ]
          }
        ]
      }
    }

    Exit 2 blocks the command and shows the message to the agent; anything
    else lets it through.
    """
}
