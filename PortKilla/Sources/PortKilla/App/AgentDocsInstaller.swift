import Foundation

/// `portkilla agent-docs`: the snippet agents need, and the two ways to put
/// it in front of them. Writing into the user's repo is opt-in (`--write`),
/// delimited by markers so it can be updated or removed, and never done by
/// any other command.
enum AgentDocsInstaller {
    static let beginMarker = "<!-- portkilla:begin -->"
    static let endMarker = "<!-- portkilla:end -->"

    static func run(_ options: CLICommand.AgentDocsOptions) -> Int32 {
        if options.claudeHook {
            print(claudeHook)
            return CLIExit.ok
        }
        guard options.write else {
            print(PortKillaCLI.agentDocs)
            return CLIExit.ok
        }
        do {
            let result = try install(into: URL(fileURLWithPath: options.file))
            print("\(result.rawValue) \(options.file)")
            return CLIExit.ok
        } catch {
            PortKillaCLI.printError("portkilla: could not write \(options.file): \(error.localizedDescription)")
            return CLIExit.killFailed
        }
    }

    enum Result: String {
        case added = "Added the PortKilla section to"
        case updated = "Updated the PortKilla section in"
        case unchanged = "PortKilla section already current in"
    }

    static func block() -> String {
        "\(beginMarker)\n\(PortKillaCLI.agentDocs)\n\(endMarker)\n"
    }

    /// Appends the block, or replaces an existing one in place.
    static func install(into file: URL) throws -> Result {
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let fresh = block()

        if let start = existing.range(of: beginMarker), let end = existing.range(of: endMarker) {
            let current = String(existing[start.lowerBound..<end.upperBound]) + "\n"
            if current == fresh { return .unchanged }
            let replaced = existing.replacingCharacters(in: start.lowerBound..<end.upperBound, with: fresh.trimmingCharacters(in: .newlines))
            try replaced.write(to: file, atomically: true, encoding: .utf8)
            return .updated
        }

        let separator = existing.isEmpty || existing.hasSuffix("\n\n") ? "" : (existing.hasSuffix("\n") ? "\n" : "\n\n")
        try (existing + separator + fresh).write(to: file, atomically: true, encoding: .utf8)
        return .added
    }

    /// A Claude Code PreToolUse hook: the habit is intercepted at the point
    /// of the habit. Pure configuration; no daemon.
    static let claudeHook = """
    Add to .claude/settings.json (project) or ~/.claude/settings.json:

    {
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Bash",
            "hooks": [
              {
                "type": "command",
                "command": "jq -r '.tool_input.command' | grep -Eq 'lsof -t?i[:=]?[0-9]+|fuser -k|kill -9 \\\\$\\\\(lsof' && { echo 'Use `portkilla free <port>` instead of lsof/kill: another agent may own that port (exit 3 = do not force).' >&2; exit 2; } || exit 0"
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
