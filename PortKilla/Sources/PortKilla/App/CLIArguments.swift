import Foundation

/// Exit codes are part of the CLI's contract with scripts and agents.
enum CLIExit {
    static let ok: Int32 = 0
    static let notFound: Int32 = 1
    static let usage: Int32 = 2
    static let refused: Int32 = 3
    static let killFailed: Int32 = 4
    static let stillRunning: Int32 = 5
    /// EX_SOFTWARE: PortKilla itself failed (e.g. could not encode JSON).
    static let internalError: Int32 = 70
}

enum CLICommand: Equatable {
    case list(ListOptions)
    case kill(KillOptions)
    case whoami(json: Bool)
    case wait(port: Int, timeout: TimeInterval, json: Bool)
    case open(port: Int)
    case history(HistoryOptions)
    case version(json: Bool)
    case help(topic: String?)
    case agentDocs(AgentDocsOptions)
    case doctor(json: Bool)
    case completions(shell: String)
    case mcp
    /// Print the registration for one agent (or all when nil).
    case mcpSetup(agent: String?)

    struct AgentDocsOptions: Equatable {
        /// Append the snippet to `file` (default CLAUDE.md) instead of printing it.
        var write = false
        var file = "CLAUDE.md"
        /// Print a Claude Code PreToolUse hook that redirects lsof-based kills.
        var claudeHook = false
    }

    struct HistoryOptions: Equatable {
        var json = false
        var port: Int?
        var limit = 20
    }

    struct ListOptions: Equatable {
        var json = false
        var mine = false
        var unowned = false
        var orphaned = false
        var agent: String?
    }

    struct KillOptions: Equatable {
        var port: Int?
        var pid: Int?
        var force = false
        var dryRun = false
        var json = false
        /// `free`: an already-free port is success, so `portkilla free 3000
        /// && npm run dev` works under `set -e`.
        var freeIsSuccess = false
    }
}

/// Strict argument parsing: an option the command doesn't know is an error,
/// never silently ignored. (`kill 3000 --dry-run` on an older build killed
/// for real because the flag was unknown.)
enum CLIArguments {

    enum ParseError: Error, Equatable {
        case unknownCommand(String)
        case unknownOption(String, command: String)
        case missingValue(String)
        case invalidNumber(String, option: String)
        case missingTarget
        case tooManyTargets
        case conflictingTargets

        var message: String {
            switch self {
            case .unknownCommand(let name): return "unknown command '\(name)'"
            case .unknownOption(let option, let command): return "unknown option '\(option)' for '\(command)'"
            case .missingValue(let option): return "'\(option)' needs a value"
            case .invalidNumber(let value, let option): return "'\(value)' is not a valid number for \(option)"
            case .missingTarget: return "kill needs a port number (or --pid <pid>)"
            case .tooManyTargets: return "kill takes one port number"
            case .conflictingTargets: return "use a port number or --pid, not both"
            }
        }
    }

    /// nil means "not a CLI invocation": launch the GUI. That is only the case
    /// for no arguments or system-injected launch flags (`-psn_…`), so a
    /// mistyped subcommand is reported instead of quietly opening a window.
    static func parse(_ arguments: [String]) -> Result<CLICommand, ParseError>? {
        guard let command = arguments.first else { return nil }
        if command.hasPrefix("-") && !["--help", "-h", "--version", "-v"].contains(command) {
            return nil
        }
        let rest = Array(arguments.dropFirst())
        // `portkilla kill --help` is the first thing people (and agents) try.
        if rest.contains("--help") || rest.contains("-h") {
            return .success(.help(topic: command))
        }

        switch command {
        case "list": return parseList(rest)
        case "kill": return parseKill(rest)
        case "free": return parseKill(rest, freeIsSuccess: true)
        case "wait": return parseWait(rest)
        case "open": return parseOpen(rest)
        case "history": return parseHistory(rest)
        case "whoami": return parseWhoami(rest)
        case "version", "--version", "-v":
            if rest.isEmpty { return .success(.version(json: false)) }
            return rest == ["--json"] ? .success(.version(json: true)) : .failure(.unknownOption(rest[0], command: "version"))
        case "help", "--help", "-h": return .success(.help(topic: rest.first))
        case "agent-docs": return parseAgentDocs(rest)
        case "mcp":
            if rest.isEmpty { return .success(.mcp) }
            guard rest.first == "--setup", rest.count <= 2 else { return .failure(.unknownOption(rest[0], command: "mcp")) }
            if let agent = rest.dropFirst().first, MCPSetup.agents[agent] == nil {
                return .failure(.unknownOption(agent, command: "mcp --setup"))
            }
            return .success(.mcpSetup(agent: rest.dropFirst().first))
        case "doctor":
            if rest.isEmpty { return .success(.doctor(json: false)) }
            return rest == ["--json"] ? .success(.doctor(json: true)) : .failure(.unknownOption(rest[0], command: "doctor"))
        case "completions":
            guard let shell = rest.first, rest.count == 1 else { return .failure(.missingValue("completions <zsh|bash|fish>")) }
            return CLICompletions.script(for: shell) == nil ? .failure(.unknownOption(shell, command: "completions")) : .success(.completions(shell: shell))
        default: return .failure(.unknownCommand(command))
        }
    }

    private static func parseList(_ args: [String]) -> Result<CLICommand, ParseError> {
        var options = CLICommand.ListOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--json": options.json = true
            case "--mine": options.mine = true
            case "--unowned": options.unowned = true
            case "--orphaned": options.orphaned = true
            case "--agent":
                guard index + 1 < args.count else { return .failure(.missingValue(arg)) }
                index += 1
                options.agent = args[index]
            default:
                if let value = valueOf(option: "--agent", in: arg) {
                    options.agent = value
                } else {
                    return .failure(.unknownOption(arg, command: "list"))
                }
            }
            index += 1
        }
        return .success(.list(options))
    }

    private static func parseKill(_ args: [String], freeIsSuccess: Bool = false) -> Result<CLICommand, ParseError> {
        var options = CLICommand.KillOptions()
        options.freeIsSuccess = freeIsSuccess
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--force", "-9": options.force = true
            case "--dry-run": options.dryRun = true
            case "--json": options.json = true
            case "--pid":
                guard index + 1 < args.count else { return .failure(.missingValue(arg)) }
                index += 1
                guard let pid = Int(args[index]) else { return .failure(.invalidNumber(args[index], option: "--pid")) }
                options.pid = pid
            default:
                if let value = valueOf(option: "--pid", in: arg) {
                    guard let pid = Int(value) else { return .failure(.invalidNumber(value, option: "--pid")) }
                    options.pid = pid
                } else if arg.hasPrefix("-") {
                    return .failure(.unknownOption(arg, command: "kill"))
                } else if let port = Int(arg) {
                    guard options.port == nil else { return .failure(.tooManyTargets) }
                    guard PortManager.isValidPortNumber(port) else { return .failure(.invalidNumber(arg, option: "port")) }
                    options.port = port
                } else {
                    return .failure(.invalidNumber(arg, option: "port"))
                }
            }
            index += 1
        }
        guard options.port != nil || options.pid != nil else { return .failure(.missingTarget) }
        guard options.port == nil || options.pid == nil else { return .failure(.conflictingTargets) }
        return .success(.kill(options))
    }

    private static func parseWait(_ args: [String]) -> Result<CLICommand, ParseError> {
        var port: Int?
        var timeout: TimeInterval = 30
        var json = false
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--json" {
                json = true
            } else if arg == "--timeout" {
                guard index + 1 < args.count else { return .failure(.missingValue(arg)) }
                index += 1
                guard let seconds = TimeInterval(args[index]), seconds >= 0 else { return .failure(.invalidNumber(args[index], option: "--timeout")) }
                timeout = seconds
            } else if let value = valueOf(option: "--timeout", in: arg) {
                guard let seconds = TimeInterval(value), seconds >= 0 else { return .failure(.invalidNumber(value, option: "--timeout")) }
                timeout = seconds
            } else if arg.hasPrefix("-") {
                return .failure(.unknownOption(arg, command: "wait"))
            } else if let number = Int(arg), PortManager.isValidPortNumber(number) {
                guard port == nil else { return .failure(.tooManyTargets) }
                port = number
            } else {
                return .failure(.invalidNumber(arg, option: "port"))
            }
            index += 1
        }
        guard let port else { return .failure(.missingTarget) }
        return .success(.wait(port: port, timeout: timeout, json: json))
    }

    private static func parseOpen(_ args: [String]) -> Result<CLICommand, ParseError> {
        guard let arg = args.first else { return .failure(.missingTarget) }
        guard args.count == 1 else { return .failure(.unknownOption(args[1], command: "open")) }
        guard let port = Int(arg), PortManager.isValidPortNumber(port) else { return .failure(.invalidNumber(arg, option: "port")) }
        return .success(.open(port: port))
    }

    private static func parseHistory(_ args: [String]) -> Result<CLICommand, ParseError> {
        var options = CLICommand.HistoryOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--json" {
                options.json = true
            } else if arg == "--port" || arg == "--limit" {
                guard index + 1 < args.count else { return .failure(.missingValue(arg)) }
                index += 1
                guard let number = Int(args[index]), number > 0 else { return .failure(.invalidNumber(args[index], option: arg)) }
                if arg == "--port" { options.port = number } else { options.limit = number }
            } else if let value = valueOf(option: "--port", in: arg) {
                guard let number = Int(value), number > 0 else { return .failure(.invalidNumber(value, option: "--port")) }
                options.port = number
            } else if let value = valueOf(option: "--limit", in: arg) {
                guard let number = Int(value), number > 0 else { return .failure(.invalidNumber(value, option: "--limit")) }
                options.limit = number
            } else {
                return .failure(.unknownOption(arg, command: "history"))
            }
            index += 1
        }
        return .success(.history(options))
    }

    private static func parseAgentDocs(_ args: [String]) -> Result<CLICommand, ParseError> {
        var options = CLICommand.AgentDocsOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--write" {
                options.write = true
            } else if arg == "--claude-hook" {
                options.claudeHook = true
            } else if arg == "--file" {
                guard index + 1 < args.count else { return .failure(.missingValue(arg)) }
                index += 1
                options.file = args[index]
            } else if let value = valueOf(option: "--file", in: arg) {
                options.file = value
            } else {
                return .failure(.unknownOption(arg, command: "agent-docs"))
            }
            index += 1
        }
        return .success(.agentDocs(options))
    }

    private static func parseWhoami(_ args: [String]) -> Result<CLICommand, ParseError> {
        var json = false
        for arg in args {
            guard arg == "--json" else { return .failure(.unknownOption(arg, command: "whoami")) }
            json = true
        }
        return .success(.whoami(json: json))
    }

    /// "--agent=Cursor" -> "Cursor"
    private static func valueOf(option: String, in arg: String) -> String? {
        guard arg.hasPrefix(option + "=") else { return nil }
        return String(arg.dropFirst(option.count + 1))
    }

    /// Per-command help; nil topic (or an unknown one) gives the overview.
    static func usage(for topic: String?) -> String {
        switch topic {
        case "list": return """
            portkilla list [--json] [--mine | --agent <name> | --unowned | --orphaned]

            Lists listening TCP ports and bound UDP sockets with process, memory,
            owning AI agent, and bind address. --json prints the same as an array
            (stable field names; new fields are only ever added). The header is
            omitted when stdout is not a terminal.
              --mine      ports kill would let you stop without --force
              --agent X   ports owned by that agent (names are case-insensitive)
              --unowned   ports with no known owner
              --orphaned  ports whose owning session has ended
            """
        case "kill", "free": return """
            portkilla kill <port> [--force|-9] [--dry-run] [--json]
            portkilla kill --pid <pid> [...]
            portkilla free <port> [...]

            Stops every process listening on the port (SIGTERM, verified; --force
            sends SIGKILL). Refuses (exit 3) when another AI agent's running
            session owns it, unless --force. --dry-run reports the decision
            without signalling. free is the same command with exit 0 when the
            port was already free, for `portkilla free 3000 && npm run dev`.

            Exit codes: 0 done, 1 nothing listening, 2 usage, 3 refused, 4 kill
            failed, 5 still running after the wait, 70 internal error.
            """
        case "wait": return """
            portkilla wait <port> [--timeout 30] [--json]

            Blocks until nothing listens on the port. Exit 0 when free, 5 on timeout.
            """
        case "history": return """
            portkilla history [--json] [--port <port>] [--limit 20]

            Recent kills from the app and the CLI, newest first, with who started
            and who stopped each process.
            """
        case "whoami": return """
            portkilla whoami [--json]

            How the friendly-fire guard identifies the calling process: agent name,
            session, and whether it was detected from the process tree, the
            environment, or declared via PORTKILLA_OWNER.
            """
        case "agent-docs": return """
            portkilla agent-docs [--write [--file <path>]] [--claude-hook]

            Prints the snippet that tells AI agents to free ports through PortKilla.
            --write appends it to CLAUDE.md (or --file) between markers, once; run
            again to update it. --claude-hook prints a Claude Code PreToolUse hook
            for settings.json that turns `kill -9 $(lsof -ti:PORT)` into a nudge.
            """
        case "mcp": return """
            portkilla mcp
            portkilla mcp --setup [claude|cursor|codex]

            Runs a Model Context Protocol server over stdin/stdout with the tools
            list_ports, kill_port (dry-run by default), whoami, and
            wait_for_port_free. It is not a background service: each agent starts
            its own copy when it needs one and stops it afterwards, so register it
            once and forget it. `--setup` prints the registration (the exact
            `claude mcp add` command, Cursor's mcp.json, Codex's config.toml).
            Run by hand it waits silently for requests; Ctrl-C stops it.
            """
        case "doctor": return """
            portkilla doctor [--json]

            Version, macOS, architecture, install source, quarantine state, which
            scanner is in use and how long a scan takes, PATH resolution, and login
            item status. Paste it into bug reports.
            """
        default: return usage
        }
    }

    static let usage = """
    PortKilla — macOS port manager

    Usage:
      portkilla list [--json] [--mine | --agent <name> | --unowned | --orphaned]
      portkilla kill <port> [--force|-9] [--dry-run] [--json]
      portkilla kill --pid <pid> [--force|-9] [--dry-run] [--json]
      portkilla free <port> [...]        like kill, but exit 0 if already free
      portkilla wait <port> [--timeout 30] [--json]
      portkilla open <port>
      portkilla history [--json] [--port <port>] [--limit 20]
      portkilla whoami [--json]
      portkilla doctor [--json]
      portkilla agent-docs [--write [--file CLAUDE.md]] [--claude-hook]
      portkilla mcp                      MCP server over stdio (for agents)
      portkilla mcp --setup [claude|cursor|codex]   how to register it
      portkilla completions <zsh|bash|fish>
      portkilla version [--json]
      portkilla help [command]

    kill stops every process listening on the port (use --pid for one of
    them). --dry-run reports what would happen without signalling anything.
    free is kill for scripts: `portkilla free 3000 && npm run dev`. wait
    blocks until the port is free (exit 5 on timeout). history lists recent
    kills from the app and the CLI, with who started and who stopped each.

    Friendly-fire guard: kill refuses to stop a port owned by a different AI
    agent session unless --force. Owners are detected from the process tree
    and from the environment agents leave on their children; export
    PORTKILLA_OWNER=<name> to declare who you are (and to label what you start).

    Exit codes: 0 done, 1 nothing listening, 2 usage, 3 refused (another
    agent's live session owns it), 4 kill failed, 5 still running after the
    wait, 70 internal error. --dry-run exits 0 when it would kill and 3 when
    it would refuse. `portkilla help <command>` or `<command> --help` for more.

    The GUI launches when run with no arguments.
    """
}
