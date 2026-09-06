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

    /// How sure we are that an agent, rather than a person, started this.
    /// An editor spawns shells for both, so an editor signal alone is only
    /// "started from inside the editor" and never a reason to refuse a kill.
    enum Confidence: String, Codable {
        case agent
        case editorTerminal = "editor terminal"
    }

    let name: String
    var sessionPid: Int?
    var source: Source
    var confidence: Confidence
    /// The session that started this process has exited: nothing is watching
    /// the server any more, so anyone may stop it.
    var sessionEnded: Bool

    init(name: String, sessionPid: Int? = nil, source: Source, confidence: Confidence = .agent, sessionEnded: Bool = false) {
        self.name = name
        self.sessionPid = sessionPid
        self.source = source
        self.confidence = confidence
        self.sessionEnded = sessionEnded
    }

    /// Stable identity string, e.g. "Claude Code#845" or "Claude Code".
    var sessionId: String {
        sessionPid.map { "\(name)#\($0)" } ?? name
    }

    /// An agent session that is still running: the case the guard protects.
    var isLiveAgentSession: Bool {
        confidence == .agent && !sessionEnded
    }

    /// Short form for tables and chips: "Claude Code", "Claude Code (ended)".
    var label: String {
        sessionEnded ? "\(name) (ended)" : name
    }

    /// "Claude Code (session 845)" or just the name.
    var described: String {
        sessionPid.map { "\(name) (session \($0))" } ?? name
    }

    /// One line for detail views and tooltips.
    var detail: String {
        if confidence == .editorTerminal {
            return "Started from a \(name) terminal (by you or an agent inside it)"
        }
        if sessionEnded {
            return "Started by \(name); that session has ended, so nothing is watching this server"
        }
        let session = sessionPid.map { "session \($0), " } ?? ""
        let how = source == .declared ? "declared" : "from \(source.rawValue)"
        return "Started by \(name) (\(session)\(how))"
    }
}

/// Attributes a process to the AI agent that spawned it, using two passive
/// signals and never a launcher or registry:
///
/// 1. Process ancestry (server -> shell -> agent). Precise about the session,
///    but the link breaks when the server is reparented to launchd (nohup,
///    pm2, or a tool shell that exited after backgrounding it), which is how
///    most agents start dev servers.
/// 2. Environment markers. Agents stamp their child processes (Claude Code
///    sets CLAUDECODE=1, Cursor sets CURSOR_TRACE_ID, ...); the environment
///    is inherited at spawn and survives reparenting, so the server carries
///    its birth certificate with it.
///
/// Unknown stays unknown: we never guess an owner.
enum AgentAttribution {

    typealias EnvironmentLookup = (_ pid: Int) -> [String: String]

    /// Deepest ancestor we'll walk before giving up (guards against cycles).
    private static let maxDepth = 24

    static func liveEnvironment(pid: Int) -> [String: String] {
        NativeScanner.environmentMarkers(Int32(pid), keys: AgentSignatures.markerKeys)
    }

    /// The agent that owns `pid`: by ancestry first (session-precise), then by
    /// the markers in its environment. Nil when neither says anything.
    static func owner(ofPid pid: Int, in processes: ProcessTable,
                      environmentOf: EnvironmentLookup = liveEnvironment) -> AgentOwner? {
        if let fromTree = ownerFromAncestry(ofPid: pid, in: processes) {
            return fromTree
        }
        return ownerFromEnvironment(environmentOf(pid), in: processes)
    }

    /// The agent invoking the CLI: `PORTKILLA_OWNER` if set, else detected
    /// from the caller's own ancestry, else from the caller's own environment.
    static func callerOwner(callerPid: Int, in processes: ProcessTable,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> AgentOwner? {
        if let declared = declaredOwner(in: environment) {
            return declared
        }
        if let fromTree = ownerFromAncestry(ofPid: callerPid, in: processes) {
            return fromTree
        }
        return ownerFromEnvironment(environment, in: processes)
    }

    /// Walks up from the parent of `pid`. The process itself is never the
    /// agent: an editor's own helper that happens to listen must resolve to
    /// the editor, not to a "session" of one.
    static func ownerFromAncestry(ofPid pid: Int, in processes: ProcessTable) -> AgentOwner? {
        var current = processes.ppid(for: pid)
        var seen = Set<Int>()

        for _ in 0..<maxDepth {
            guard let pid = current, pid > 1, !seen.contains(pid) else { break }
            seen.insert(pid)

            if let command = processes.command(for: pid),
               let signature = match(command: command, executableName: processes.name(for: pid)) {
                return AgentOwner(name: signature.name, sessionPid: pid, source: .processTree, confidence: signature.confidence)
            }
            current = processes.ppid(for: pid)
        }
        return nil
    }

    /// Owner from environment markers. A Claude Code session pid is only
    /// trusted while that process is alive and still an agent; otherwise the
    /// name is kept and the session reported as ended.
    static func ownerFromEnvironment(_ environment: [String: String], in processes: ProcessTable) -> AgentOwner? {
        if let declared = declaredOwner(in: environment) {
            return declared
        }

        let marker = AgentSignatures.envMarkers.first { marker in
            guard let actual = environment[marker.key] else { return false }
            return marker.value.map { $0 == actual.lowercased() } ?? true
        }
        guard let marker else { return nil }

        var owner = AgentOwner(name: marker.name, source: .environment, confidence: marker.confidence)
        if marker.key == "TERM_PROGRAM", let fork = vscodeFork(in: environment) {
            owner = AgentOwner(name: fork, source: .environment, confidence: .editorTerminal)
        }
        if marker.name == "Claude Code", let session = environment[AgentSignatures.claudeSessionKey].flatMap(Int.init) {
            if isAgentProcess(session, in: processes) {
                owner.sessionPid = session
            } else {
                owner.sessionEnded = true
            }
        }
        return owner
    }

    private static func declaredOwner(in environment: [String: String]) -> AgentOwner? {
        guard let raw = environment[AgentSignatures.declaredOwnerKey] else { return nil }
        let name = AgentSignatures.canonicalName(raw)
        guard !name.isEmpty else { return nil }
        return AgentOwner(name: name, source: .declared)
    }

    private static func vscodeFork(in environment: [String: String]) -> String? {
        for key in AgentSignatures.vscodeForkHintKeys {
            if let path = environment[key], let name = AgentSignatures.bundleName(inPath: path) {
                return name
            }
        }
        return nil
    }

    /// True when `pid` is running and still an agent (guards against the pid
    /// having been reused by an unrelated process).
    private static func isAgentProcess(_ pid: Int, in processes: ProcessTable) -> Bool {
        guard let command = processes.command(for: pid) else { return false }
        return match(command: command, executableName: processes.name(for: pid)) != nil
    }

    /// Match a process against the known tree signatures. `executableName` is
    /// the kernel-reported binary name when available; it is authoritative
    /// because an executable path can contain spaces ("Application Support"),
    /// which makes the first-token fallback unreliable.
    static func match(command: String, executableName: String? = nil) -> AgentSignatures.TreeSignature? {
        let commandLower = command.lowercased()
        let firstToken = command.split(separator: " ").first.map(String.init) ?? command
        let basename = executableName ?? (firstToken as NSString).lastPathComponent
        return AgentSignatures.treeSignatures.first { $0.matches(commandLower, basename) }
    }
}
