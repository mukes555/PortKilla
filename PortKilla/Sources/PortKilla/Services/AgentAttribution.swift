import Foundation

/// Which AI coding agent a process belongs to, and the specific session
/// (agent process) it came from. Two windows of the same tool are distinct
/// sessions; `sessionPid` is nil when the owner was declared via
/// `PORTKILLA_OWNER` rather than detected from the process tree.
struct AgentOwner: Codable, Equatable {
    let name: String
    var sessionPid: Int?

    /// Stable identity string, e.g. "Claude Code#845" or "Claude Code".
    var sessionId: String {
        sessionPid.map { "\(name)#\($0)" } ?? name
    }
}

/// Attributes a listening process to the AI agent that spawned it by walking
/// the process ancestry (agent → shell → dev server) until it hits a known
/// agent. Best-effort: a detached server (double-fork / nohup / pm2) loses the
/// ancestry link and reports no owner rather than guessing.
enum AgentAttribution {

    /// One agent's fingerprint. App-bundle agents match on the distinctive
    /// `.app/` path anywhere in the command (their executables contain spaces,
    /// so first-token splitting is unreliable). Bare-binary agents match on the
    /// executable basename — never on arguments, so a project folder named
    /// "claude-code" is not mistaken for the Claude Code binary.
    private struct Signature {
        let name: String
        let matches: (_ commandLower: String, _ execBasename: String) -> Bool
    }

    private static let signatures: [Signature] = [
        Signature(name: "Claude Code") { _, base in base == "claude" },
        Signature(name: "Aider")       { _, base in base == "aider" },
        Signature(name: "Cursor")      { cmd, _ in cmd.contains("/cursor.app/") },
        Signature(name: "VS Code")     { cmd, _ in cmd.contains("/visual studio code.app/") },
        Signature(name: "Windsurf")    { cmd, _ in cmd.contains("/windsurf.app/") },
        Signature(name: "Zed")         { cmd, base in cmd.contains("/zed.app/") || base == "zed" },
        Signature(name: "Trae")        { cmd, _ in cmd.contains("/trae.app/") },
    ]

    /// Deepest ancestor we'll walk before giving up (guards against cycles).
    private static let maxDepth = 24

    /// The agent that owns `pid`, walking up via `processes`, or nil.
    static func owner(ofPid pid: Int, in processes: ProcessTable) -> AgentOwner? {
        var current = pid
        var seen = Set<Int>()

        for _ in 0..<maxDepth {
            if current <= 1 || seen.contains(current) { break }
            seen.insert(current)

            if let command = processes.command(for: current),
               let name = match(command: command) {
                return AgentOwner(name: name, sessionPid: current)
            }

            guard let parent = processes.ppid(for: current) else { break }
            current = parent
        }
        return nil
    }

    /// The agent invoking the CLI: `PORTKILLA_OWNER` if set, else detected from
    /// the caller's own process ancestry.
    static func callerOwner(callerPid: Int, in processes: ProcessTable,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> AgentOwner? {
        if let declared = environment["PORTKILLA_OWNER"]?.trimmingCharacters(in: .whitespaces),
           !declared.isEmpty {
            return AgentOwner(name: declared, sessionPid: nil)
        }
        return owner(ofPid: callerPid, in: processes)
    }

    /// Match a command against the known signatures.
    static func match(command: String) -> String? {
        let commandLower = command.lowercased()
        // Basename of the first token — reliable for space-free executables
        // (claude, aider, zed), which is all the basename signatures use.
        let firstToken = command.split(separator: " ").first.map(String.init) ?? command
        let basename = (firstToken as NSString).lastPathComponent.lowercased()
        return signatures.first { $0.matches(commandLower, basename) }?.name
    }

    /// Whether `caller` killing `target` would be friendly fire (a different
    /// agent, or a different session of the same agent). Unknown owner on
    /// either side → not blocked (we never refuse on a guess).
    static func isFriendlyFire(caller: AgentOwner?, target: AgentOwner?) -> Bool {
        guard let caller, let target else { return false }
        if caller.name != target.name { return true }
        // Same tool: block only when both sessions are known and differ.
        if let c = caller.sessionPid, let t = target.sessionPid, c != t { return true }
        return false
    }
}
