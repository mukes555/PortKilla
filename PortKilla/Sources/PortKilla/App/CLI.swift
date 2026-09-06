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
        case .success(.help):
            print(CLIArguments.usage)
            return CLIExit.ok
        case .success(.version):
            print(UpdateChecker.currentVersion ?? "dev")
            return CLIExit.ok
        case .success(.agentDocs):
            print(agentDocs)
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
    /// against each target's owner.
    static func scan() -> Scan {
        let table = ProcessTable.capture()
        let ports = (try? PortScanner().scanActivePorts(processes: table)) ?? []
        let callerPid = Int(Foundation.ProcessInfo.processInfo.processIdentifier)
        let caller = AgentAttribution.callerOwner(callerPid: callerPid, in: table)
        return Scan(ports: ports, table: table, caller: caller)
    }

    static func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            printError("portkilla: could not encode output as JSON")
            return
        }
        print(text)
    }

    // MARK: - list

    private static func list(_ options: CLICommand.ListOptions) -> Int32 {
        let scan = scan()
        let ports = filtered(scan.ports, by: options, caller: scan.caller)

        if options.json {
            // The array shape is a stable contract (scripts and the Raycast
            // extension depend on it); new fields are only ever added.
            printJSON(ports)
            return CLIExit.ok
        }

        if ports.isEmpty {
            print(scan.ports.isEmpty ? "No listening ports found." : "No ports match that filter.")
            return CLIExit.ok
        }

        print("PORT   PROTO  PID     PROCESS               MEMORY    AGENT                 BIND")
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
            return ports.filter { port in
                guard let owner = port.agentOwner, owner.name == caller.name else { return false }
                // Same tool; a known-but-different session is not mine.
                if let mine = caller.sessionPid, let theirs = owner.sessionPid { return mine == theirs }
                return true
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

    /// Prints how the friendly-fire guard identifies the calling process, so
    /// an agent can check itself before a kill is refused.
    private static func whoami(json: Bool) -> Int32 {
        let table = ProcessTable.capture()
        let callerPid = Int(Foundation.ProcessInfo.processInfo.processIdentifier)
        let me = AgentAttribution.callerOwner(callerPid: callerPid, in: table)

        if json {
            printJSON(WhoAmI(detected: me != nil, owner: me))
            return CLIExit.ok
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

    // MARK: - agent-docs

    /// A snippet for CLAUDE.md / AGENTS.md. The guard only helps agents that
    /// call `portkilla kill` instead of reaching for lsof by reflex.
    static let agentDocs = """
    ## Freeing ports

    Use PortKilla to stop whatever is on a port. Never run `kill -9 $(lsof -ti:PORT)`:
    other AI agents may be using that port, and PortKilla knows who owns what.

    - `portkilla kill <port>` frees the port (SIGTERM, verified).
    - Exit code 3 means the port belongs to another agent's running session.
      Do not retry with `--force`; tell the user which agent owns it instead.
    - `portkilla list --json` lists every listener with its owning agent;
      `portkilla list --mine` shows only yours.
    - `portkilla whoami` shows how PortKilla identifies you. If it reports no
      agent, export `PORTKILLA_OWNER=<your name>` before starting servers.
    """
}
