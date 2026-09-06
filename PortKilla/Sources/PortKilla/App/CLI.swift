import Foundation

/// Command-line mode: the same binary doubles as a CLI when invoked with a
/// known subcommand, e.g.
///
///   PortKilla.app/Contents/MacOS/PortKilla list
///   PortKilla.app/Contents/MacOS/PortKilla list --json
///   PortKilla.app/Contents/MacOS/PortKilla kill 3000 [--force]
///
/// Symlink the binary as `portkilla` somewhere on PATH for daily use.
enum PortKillaCLI {

    /// Returns an exit code when the arguments were a CLI invocation,
    /// or nil to continue launching the GUI.
    static func run(_ arguments: [String]) -> Int32? {
        guard let command = arguments.first, !command.hasPrefix("-psn") else { return nil }

        switch command {
        case "list":
            return list(json: arguments.contains("--json"))
        case "kill":
            return kill(arguments: Array(arguments.dropFirst()))
        case "whoami":
            return whoami()
        case "help", "--help", "-h":
            printUsage()
            return 0
        case "version", "--version":
            print(UpdateChecker.currentVersion ?? "dev")
            return 0
        default:
            // Unknown args (e.g. system-injected launch flags) -> GUI
            return nil
        }
    }

    private static func scan() -> [PortInfo] {
        scanWithTable().ports
    }

    /// Scan plus the underlying process snapshot (needed to attribute the
    /// caller's own agent for the friendly-fire guard).
    private static func scanWithTable() -> (ports: [PortInfo], table: ProcessTable) {
        let table = ProcessTable.capture()
        let ports = (try? PortScanner().scanActivePorts(processes: table)) ?? []
        return (ports, table)
    }

    private static func list(json: Bool) -> Int32 {
        let ports = scan()

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(ports), let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return 0
        }

        if ports.isEmpty {
            print("No listening TCP ports found.")
            return 0
        }

        print("PORT   PROTO  PID     PROCESS               MEMORY    AGENT         BIND")
        for port in ports {
            let line = [
                ":\(port.port)".padding(toLength: 7, withPad: " ", startingAt: 0),
                port.proto.padding(toLength: 7, withPad: " ", startingAt: 0),
                "\(port.pid)".padding(toLength: 8, withPad: " ", startingAt: 0),
                port.processName.padding(toLength: 22, withPad: " ", startingAt: 0),
                port.memoryUsage.padding(toLength: 10, withPad: " ", startingAt: 0),
                (port.agentOwner?.name ?? "—").padding(toLength: 14, withPad: " ", startingAt: 0),
                port.bindAddress ?? ""
            ].joined()
            print(line)
        }
        return 0
    }

    private static func kill(arguments: [String]) -> Int32 {
        let force = arguments.contains("--force") || arguments.contains("-9")

        guard let portArg = arguments.first(where: { !$0.hasPrefix("-") }),
              let portNumber = Int(portArg) else {
            print("Usage: portkilla kill <port> [--force]")
            return 2
        }

        let (ports, table) = scanWithTable()
        guard let target = ports.first(where: { $0.port == portNumber }) else {
            print("Nothing is listening on :\(portNumber).")
            return 1
        }

        // Friendly-fire guard: refuse to kill a port owned by a different agent
        // session unless --force. Prevents AI agents from killing each other's
        // dev servers. (Set PORTKILLA_OWNER to declare the caller's identity.)
        let callerPid = Int(Foundation.ProcessInfo.processInfo.processIdentifier)
        let caller = AgentAttribution.callerOwner(callerPid: callerPid, in: table)
        if !force, AgentAttribution.isFriendlyFire(caller: caller, target: target.agentOwner) {
            let owner = target.agentOwner.map(describe) ?? "another agent"
            let you = caller.map(describe) ?? "you"
            FileHandle.standardError.write(Data("""
                :\(portNumber) is owned by \(owner), not \(you). Refusing to kill another agent's server.
                Pass --force to override, or run `portkilla whoami` to check how you are identified.

                """.utf8))
            return 3
        }

        let killer = ProcessKiller()
        do {
            try killer.killProcess(
                pid: target.pid, force: force, expectedName: target.processName
            )
        } catch {
            print("Failed to kill \(target.processName) (PID \(target.pid)): \(error.localizedDescription)")
            return 1
        }

        // Give it up to a second to actually exit
        for _ in 0..<10 {
            if !killer.isProcessRunning(target.pid) {
                print("Killed \(target.processName) (PID \(target.pid)) on :\(portNumber).")
                return 0
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        print("\(target.processName) (PID \(target.pid)) did not terminate. Try --force.")
        return 1
    }

    /// Prints how the friendly-fire guard identifies the calling process, so
    /// an agent can check itself before a kill is refused.
    private static func whoami() -> Int32 {
        let table = ProcessTable.capture()
        let callerPid = Int(Foundation.ProcessInfo.processInfo.processIdentifier)
        guard let me = AgentAttribution.callerOwner(callerPid: callerPid, in: table) else {
            print("Not running under a known AI agent. Set PORTKILLA_OWNER=<name> to declare one.")
            return 0
        }
        let how = me.source == .declared ? "declared via PORTKILLA_OWNER" : "detected from \(me.source.rawValue)"
        print("\(describe(me)), \(how)")
        return 0
    }

    /// "Claude Code (session 845)" or just the name when the session is unknown.
    private static func describe(_ owner: AgentOwner) -> String {
        owner.sessionPid.map { "\(owner.name) (session \($0))" } ?? owner.name
    }

    private static func printUsage() {
        print("""
        PortKilla — macOS port manager

        Usage:
          portkilla list [--json]          List listening ports (with owning agent)
          portkilla kill <port> [--force]  Kill the process on a port
          portkilla whoami                 Show which AI agent you are seen as
          portkilla version                Print version
          portkilla help                   Show this help

        Friendly-fire guard: `kill` refuses to stop a port owned by a different
        AI-agent session unless --force (exit code 3). Owners are detected from
        the process tree and from the environment agents leave on their
        children; set PORTKILLA_OWNER to declare who you are instead.

        The GUI launches when run with no arguments.
        """)
    }
}
