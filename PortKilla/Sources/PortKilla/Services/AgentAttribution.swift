import Foundation

/// Which AI coding agent a process belongs to, and the specific session
/// (agent process) it came from. Two windows of the same tool are distinct
/// sessions; `sessionPid` is nil when the session could not be pinned down.
struct AgentOwner: Codable, Equatable {
    enum Source: String, Codable {
        case processTree = "process tree"
        case environment
        case declared
    }

    let name: String
    var sessionPid: Int?
    var source: Source

    /// Stable identity string, e.g. "Claude Code#845" or "Claude Code".
    var sessionId: String {
        sessionPid.map { "\(name)#\($0)" } ?? name
    }
}

/// Attributes a listening process to the AI agent that spawned it, using two
/// passive signals and never a launcher or registry:
///
/// 1. Process ancestry (server -> shell -> agent). Precise about the session,
///    but the link breaks when the server is reparented to launchd (nohup,
///    pm2, or a tool shell that exited after backgrounding it), which is how
///    most agents start dev servers.
/// 2. Environment markers. Agents stamp their child processes (Claude Code
///    sets CLAUDECODE=1, Cursor sets CURSOR_TRACE_ID, ...); the environment is
///    inherited at spawn and survives reparenting, so the server carries its
///    birth certificate with it.
///
/// Unknown stays unknown: we never guess an owner.
enum AgentAttribution {

    typealias EnvironmentLookup = (_ pid: Int) -> [String: String]

    // MARK: - Fingerprints

    /// Matches an ancestor process. App-bundle agents match on the distinctive
    /// `.app/` path anywhere in the (lowercased) command. Bare-binary agents
    /// match on the exact executable name, never on arguments, so a project
    /// folder named "claude-code" is not mistaken for the binary. The name is
    /// case-sensitive on purpose: `claude` is the Claude Code CLI, `Claude` is
    /// the desktop app it may be running inside.
    private struct TreeSignature {
        let name: String
        let matches: (_ commandLower: String, _ executableName: String) -> Bool
    }

    private static let treeSignatures: [TreeSignature] = [
        TreeSignature(name: "Claude Code") { _, base in base == "claude" },
        TreeSignature(name: "Codex CLI")   { _, base in base == "codex" },
        TreeSignature(name: "Gemini CLI")  { _, base in base == "gemini" },
        TreeSignature(name: "Copilot CLI") { _, base in base == "copilot" },
        TreeSignature(name: "OpenCode")    { _, base in base == "opencode" },
        TreeSignature(name: "Aider")       { _, base in base == "aider" },
        TreeSignature(name: "Cursor")      { cmd, _ in cmd.contains("/cursor.app/") },
        TreeSignature(name: "VS Code")     { cmd, _ in cmd.contains("/visual studio code.app/") },
        TreeSignature(name: "Windsurf")    { cmd, _ in cmd.contains("/windsurf.app/") },
        TreeSignature(name: "Zed")         { cmd, base in cmd.contains("/zed.app/") || base == "zed" },
        TreeSignature(name: "Trae")        { cmd, _ in cmd.contains("/trae.app/") },
    ]

    /// An environment variable an agent leaves on its children. `value` nil
    /// means any value counts. Order is precedence: terminal agents come before
    /// editors, so Claude Code running inside a Cursor terminal is Claude Code.
    private struct EnvMarker {
        let name: String
        let key: String
        let value: String?
    }

    private static let envMarkers: [EnvMarker] = [
        EnvMarker(name: "Claude Code", key: "CLAUDECODE", value: nil),
        EnvMarker(name: "Gemini CLI", key: "GEMINI_CLI", value: nil),
        EnvMarker(name: "Cursor", key: "CURSOR_TRACE_ID", value: nil),
        EnvMarker(name: "VS Code", key: "TERM_PROGRAM", value: "vscode"),
    ]

    /// Names the agent's own process; used to recover the session when the
    /// tree link is gone. Only trusted where it is known to equal the pid the
    /// ancestry walk would find.
    private static let sessionPidKeys: [String: String] = ["Claude Code": "CLAUDE_PID"]

    /// The only environment keys ever read from another process.
    static let markerKeys: Set<String> = Set(envMarkers.map(\.key) + sessionPidKeys.values)

    /// Deepest ancestor we'll walk before giving up (guards against cycles).
    private static let maxDepth = 24

    // MARK: - Attribution

    static func liveEnvironment(pid: Int) -> [String: String] {
        NativeScanner.environmentMarkers(Int32(pid), keys: markerKeys)
    }

    /// The agent that owns `pid`: by ancestry first (session-precise), then by
    /// the markers in its environment. Nil when neither says anything.
    static func owner(ofPid pid: Int, in processes: ProcessTable,
                      environmentOf: EnvironmentLookup = liveEnvironment) -> AgentOwner? {
        if let fromTree = ownerFromAncestry(ofPid: pid, in: processes) {
            return fromTree
        }
        guard var fromEnvironment = ownerFromEnvironment(environmentOf(pid)) else { return nil }
        // A marker outlives the session that set it (a restarted agent, or
        // Docker launched from an agent shell weeks ago). There is no live
        // session to protect then, so keep the name but drop the session:
        // the same tool may kill it again without --force.
        let sessionIsAlive = fromEnvironment.sessionPid.map { isAgentProcess($0, in: processes) } ?? false
        if !sessionIsAlive { fromEnvironment.sessionPid = nil }
        return fromEnvironment
    }

    /// The agent invoking the CLI: `PORTKILLA_OWNER` if set, else detected
    /// from the caller's own ancestry, else from the caller's own environment.
    static func callerOwner(callerPid: Int, in processes: ProcessTable,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> AgentOwner? {
        if let declared = environment["PORTKILLA_OWNER"]?.trimmingCharacters(in: .whitespaces),
           !declared.isEmpty {
            return AgentOwner(name: declared, sessionPid: nil, source: .declared)
        }
        if let fromTree = ownerFromAncestry(ofPid: callerPid, in: processes) {
            return fromTree
        }
        return ownerFromEnvironment(environment)
    }

    /// True when `pid` is running and still an agent (guards against the pid
    /// having been reused by an unrelated process).
    private static func isAgentProcess(_ pid: Int, in processes: ProcessTable) -> Bool {
        guard let command = processes.command(for: pid) else { return false }
        return match(command: command, executableName: processes.name(for: pid)) != nil
    }

    static func ownerFromAncestry(ofPid pid: Int, in processes: ProcessTable) -> AgentOwner? {
        var current = pid
        var seen = Set<Int>()

        for _ in 0..<maxDepth {
            if current <= 1 || seen.contains(current) { break }
            seen.insert(current)

            if let command = processes.command(for: current),
               let name = match(command: command, executableName: processes.name(for: current)) {
                return AgentOwner(name: name, sessionPid: current, source: .processTree)
            }

            guard let parent = processes.ppid(for: current) else { break }
            current = parent
        }
        return nil
    }

    static func ownerFromEnvironment(_ environment: [String: String]) -> AgentOwner? {
        let marker = envMarkers.first { marker in
            guard let actual = environment[marker.key] else { return false }
            return marker.value.map { $0 == actual.lowercased() } ?? true
        }
        guard let marker else { return nil }

        let sessionPid = sessionPidKeys[marker.name].flatMap { environment[$0] }.flatMap(Int.init)
        return AgentOwner(name: marker.name, sessionPid: sessionPid, source: .environment)
    }

    /// Match a process against the known tree signatures. `executableName` is
    /// the kernel-reported binary name when available; it is authoritative
    /// because an executable path can contain spaces ("Application Support"),
    /// which makes the first-token fallback unreliable.
    static func match(command: String, executableName: String? = nil) -> String? {
        let commandLower = command.lowercased()
        let firstToken = command.split(separator: " ").first.map(String.init) ?? command
        let basename = executableName ?? (firstToken as NSString).lastPathComponent
        return treeSignatures.first { $0.matches(commandLower, basename) }?.name
    }

    // MARK: - Decision

    /// Whether `caller` killing `target` would be friendly fire (a different
    /// agent, or a different session of the same agent). Unknown owner on
    /// either side means not blocked: we never refuse on a guess.
    static func isFriendlyFire(caller: AgentOwner?, target: AgentOwner?) -> Bool {
        guard let caller, let target else { return false }
        if caller.name != target.name { return true }
        // Same tool: block only when both sessions are known and differ.
        if let c = caller.sessionPid, let t = target.sessionPid, c != t { return true }
        return false
    }
}
