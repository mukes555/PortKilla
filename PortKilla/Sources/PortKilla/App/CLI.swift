import Foundation

/// Command-line mode: the same binary doubles as a CLI when invoked with a
/// known subcommand. Homebrew links it as `portkilla`; otherwise symlink
/// PortKilla.app/Contents/MacOS/PortKilla somewhere on PATH.
enum PortKillaCLI {

    /// Returns an exit code when the arguments were a CLI invocation,
    /// or nil to continue launching the GUI.
    static func run(_ arguments: [String]) -> Int32? {
        guard let parsed = CLIArguments.parse(arguments) else { return nil }

        switch parsed {
        case .failure(let error):
            printError("portkilla: \(error.message)\nRun `portkilla help` for usage.")
            return CLIExit.usage
        case .success(.list(let options)):
            return list(options)
        case .success(.kill(let options)):
            return CLIKill.run(options)
        case .success(.whoami(let json)):
            return whoami(json: json)
        case .success(.wait(let port, let timeout, let json)):
            return wait(port: port, timeout: timeout, json: json)
        case .success(.open(let port)):
            Browser.openLocalhost(port: port)
            return CLIExit.ok
        case .success(.history(let options)):
            return history(options)
        case .success(.help(let topic)):
            print(CLIArguments.usage(for: topic))
            return CLIExit.ok
        case .success(.version(let json)):
            return version(json: json)
        case .success(.agentDocs(let options)):
            return AgentDocsInstaller.run(options)
        case .success(.mcp):
            return MCPServer().serve()
        case .success(.mcpSetup(let agent)):
            print(MCPSetup.instructions(for: agent))
            return CLIExit.ok
        case .success(.doctor(let json)):
            return doctor(json: json)
        case .success(.completions(let shell)):
            print(CLICompletions.script(for: shell) ?? "")
            return CLIExit.ok
        }
    }

    // MARK: - Shared helpers

    struct Scan {
        let ports: [PortInfo]
        let table: ProcessTable
        let caller: AgentOwner?
    }

    /// One scan plus the caller's own identity, which the guard compares
    /// against each target's owner. Container names come from a synchronous
    /// `docker ps` only when asked: `list` prints them, `kill` doesn't need them.
    static func scan(refreshDocker: Bool) -> Scan {
        let table = ProcessTable.capture()
        if refreshDocker {
            let listeningPids = Set(table.listeners?.map(\.pid) ?? [])
            let dockerPresent = listeningPids.contains { table.name(for: $0)?.lowercased().contains("docker") == true }
            DockerService.shared.refreshNow(dockerPresent: dockerPresent)
        }
        let ports = (try? PortScanner().scanActivePorts(processes: table)) ?? []
        let callerPid = Int(Foundation.ProcessInfo.processInfo.processIdentifier)
        let caller = AgentAttribution.callerOwner(callerPid: callerPid, in: table)
        return Scan(ports: ports, table: table, caller: caller)
    }

    static func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    /// False when encoding failed: a JSON consumer must never see exit 0 with
    /// empty output.
    @discardableResult
    static func printJSON<T: Encodable>(_ value: T) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            printError("portkilla: could not encode output as JSON")
            return false
        }
        print(text)
        return true
    }

    static var stdoutIsTerminal: Bool { isatty(1) != 0 }

    struct VersionReport: Encodable {
        let schema = 1
        let version: String
        let bundleIdentifier = "com.mukes555.PortKilla"
        let installSource: String
        let architecture: String
    }

    private static func version(json: Bool) -> Int32 {
        let version = UpdateChecker.currentVersion ?? "dev"
        guard json else {
            print(version)
            return CLIExit.ok
        }
        let arch = Diagnostics.report().first { $0.label == "Architecture" }?.value ?? "unknown"
        let report = VersionReport(version: version, installSource: InstallSource.detect().rawValue, architecture: arch)
        return printJSON(report) ? CLIExit.ok : CLIExit.internalError
    }

    // MARK: - doctor

    private static func doctor(json: Bool) -> Int32 {
        let lines = Diagnostics.report()
        if json {
            let object = Dictionary(uniqueKeysWithValues: lines.map { ($0.label, $0.value) })
            return printJSON(object) ? CLIExit.ok : CLIExit.internalError
        }
        for line in lines {
            print("\(line.label.padding(toLength: 18, withPad: " ", startingAt: 0)) \(line.value)")
        }
        return CLIExit.ok
    }

    // MARK: - list

    private static func list(_ options: CLICommand.ListOptions) -> Int32 {
        let scan = scan(refreshDocker: true)
        if options.mine && scan.caller == nil {
            // An empty list would read as "no servers"; the truth is "not identified".
            printError("portkilla: you are not identified as an AI agent, so nothing can be \"mine\". Run `portkilla whoami`, or export PORTKILLA_OWNER=<name>.")
            if options.json { print("[]") }
            return CLIExit.notFound
        }
        let ports = filtered(scan.ports, by: options, caller: scan.caller)

        if options.json {
            // The array shape is a stable contract (scripts and the Raycast
            // extension depend on it); new fields are only ever added.
            return printJSON(ports) ? CLIExit.ok : CLIExit.internalError
        }

        if ports.isEmpty {
            print(scan.ports.isEmpty ? "No listening ports found." : "No ports match that filter.")
            return CLIExit.ok
        }

        // Piped output gets rows only, so `portkilla list | grep 3000` is clean.
        if stdoutIsTerminal {
            print("PORT   PROTO  PID     PROCESS               MEMORY    AGENT                 BIND")
        }
        for port in ports {
            let line = [
                ":\(port.port)".padding(toLength: 7, withPad: " ", startingAt: 0),
                port.proto.padding(toLength: 7, withPad: " ", startingAt: 0),
                "\(port.pid)".padding(toLength: 8, withPad: " ", startingAt: 0),
                port.processName.padding(toLength: 22, withPad: " ", startingAt: 0),
                port.memoryUsage.padding(toLength: 10, withPad: " ", startingAt: 0),
                (port.agentOwner?.label ?? "—").padding(toLength: 22, withPad: " ", startingAt: 0),
                port.bindAddress ?? ""
            ].joined()
            print(line)
        }
        return CLIExit.ok
    }

    static func filtered(_ ports: [PortInfo], by options: CLICommand.ListOptions, caller: AgentOwner?) -> [PortInfo] {
        if options.unowned {
            return ports.filter { $0.agentOwner == nil }
        }
        if options.orphaned {
            return ports.filter { $0.agentOwner?.sessionEnded == true }
        }
        if let agent = options.agent {
            let wanted = AgentSignatures.canonicalName(agent)
            return ports.filter { $0.agentOwner?.name == wanted }
        }
        if options.mine {
            guard let caller else { return [] }
            // "Mine" means exactly what kill would let me stop without --force.
            return ports.filter { port in
                guard let owner = port.agentOwner, owner.name == caller.name else { return false }
                return KillDecision.forAgent(caller: caller, target: owner) == .allow
            }
        }
        return ports
    }

    // MARK: - whoami

    struct WhoAmI: Encodable {
        let schema = 1
        let detected: Bool
        let owner: AgentOwner?
    }

    /// How the friendly-fire guard identifies this process. Only the ancestor
    /// chain matters (plus the session pid a marker may name), not the whole
    /// process table.
    static func callerIdentity() -> AgentOwner? {
        let callerPid = Int(Foundation.ProcessInfo.processInfo.processIdentifier)
        let environment = Foundation.ProcessInfo.processInfo.environment
        let sessionPid = environment[AgentSignatures.claudeSessionKey].flatMap(Int.init)
        let table = ProcessTable.ancestry(of: callerPid, including: sessionPid.map { [$0] } ?? [])
        return AgentAttribution.callerOwner(callerPid: callerPid, in: table, environment: environment)
    }

    /// Prints how the friendly-fire guard identifies the calling process, so
    /// an agent can check itself before a kill is refused.
    private static func whoami(json: Bool) -> Int32 {
        let me = callerIdentity()

        if json {
            return printJSON(WhoAmI(detected: me != nil, owner: me)) ? CLIExit.ok : CLIExit.internalError
        }
        guard let me else {
            print("Not running under a known AI agent. Export PORTKILLA_OWNER=<name> to declare one.")
            return CLIExit.ok
        }
        let how = me.source == .declared ? "declared via PORTKILLA_OWNER" : "detected from \(me.source.rawValue)"
        let kind = me.confidence == .editorTerminal ? " (editor terminal, not treated as an agent)" : ""
        print("\(me.described), \(how)\(kind)")
        return CLIExit.ok
    }

    // MARK: - wait

    struct WaitReport: Encodable {
        let schema = 1
        let port: Int
        let free: Bool
        let waitedSeconds: Double
        let exitCode: Int32
    }

    /// Blocks until nothing listens on the port, polling the native scanner.
    /// The CLI half of the app's "notify me when this frees up".
    static func waitUntilFree(port: Int, timeout: TimeInterval) -> WaitReport {
        let start = Date()
        var isFree = false
        while true {
            let listeners = NativeScanner.allListeners() ?? []
            isFree = !listeners.contains { $0.port == port }
            if isFree || Date().timeIntervalSince(start) >= timeout { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        let waited = Date().timeIntervalSince(start)
        return WaitReport(port: port, free: isFree, waitedSeconds: (waited * 100).rounded() / 100,
                          exitCode: isFree ? CLIExit.ok : CLIExit.stillRunning)
    }

    private static func wait(port: Int, timeout: TimeInterval, json: Bool) -> Int32 {
        let report = waitUntilFree(port: port, timeout: timeout)
        if json {
            return printJSON(report) ? report.exitCode : CLIExit.internalError
        } else if report.free {
            print(":\(port) is free.")
        } else {
            printError(":\(port) is still in use after \(Int(timeout))s.")
        }
        return report.exitCode
    }

    // MARK: - history

    /// Kills recorded by the app and the CLI, newest first. This is how an
    /// agent finds out what happened to a server that vanished.
    private static func history(_ options: CLICommand.HistoryOptions) -> Int32 {
        let store = HistoryManager.appStore()
        var items = store.history
        if let port = options.port {
            items = items.filter { $0.port == port }
        }
        items = Array(items.prefix(options.limit))

        if options.json {
            return printJSON(items) ? CLIExit.ok : CLIExit.internalError
        }
        if items.isEmpty {
            print(options.port.map { "No recorded kills on :\($0)." } ?? "No recorded kills.")
            return CLIExit.ok
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if stdoutIsTerminal {
            print("WHEN                 PORT   PROCESS               STARTED BY            KILLED BY")
        }
        for item in items {
            let line = [
                formatter.string(from: item.timestamp).padding(toLength: 21, withPad: " ", startingAt: 0),
                ":\(item.port)".padding(toLength: 7, withPad: " ", startingAt: 0),
                item.processName.padding(toLength: 22, withPad: " ", startingAt: 0),
                (item.owner ?? "—").padding(toLength: 22, withPad: " ", startingAt: 0),
                item.killedBy ?? "—"
            ].joined()
            print(line)
        }
        return CLIExit.ok
    }

    // MARK: - agent-docs

    /// A snippet for CLAUDE.md / AGENTS.md. The guard only helps agents that
    /// call `portkilla kill` instead of reaching for lsof by reflex.
    static let agentDocs = """
    ## Freeing ports

    Use PortKilla to stop whatever is on a port. Never run `kill -9 $(lsof -ti:PORT)`:
    other AI agents may be using that port, and PortKilla knows who owns what.

    - `portkilla free <port>` frees the port (SIGTERM, verified; exit 0 if it was
      already free). `portkilla kill <port> --dry-run` shows what would happen first.
    - Exit code 3 means the port belongs to another agent's running session (the
      refusal is printed on stderr). Do not retry with `--force`; tell the user which
      agent owns it, or pick another port. "Another Claude Code session" is still
      another session: it is not you.
    - `portkilla wait <port> --timeout 30` blocks until the port is free.
    - `portkilla list --json` lists every listener with its owning agent;
      `portkilla list --mine` shows only the ones you may stop. Use `--pid` when two
      processes share a port.
    - `portkilla history --port <port>` shows who started and who stopped a server
      that has vanished.
    - `portkilla whoami` shows how PortKilla identifies you. Codex, Windsurf and Trae
      leave no reliable marker: export `PORTKILLA_OWNER=<your name>` before starting
      servers so they are attributed to you.
    """
}
