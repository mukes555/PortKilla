import Foundation

/// Exit codes are part of the CLI's contract with scripts and agents.
public enum CLIExit {
    public static let ok: Int32 = 0
    public static let notFound: Int32 = 1
    public static let usage: Int32 = 2
    public static let refused: Int32 = 3
    public static let killFailed: Int32 = 4
    public static let stillRunning: Int32 = 5
    /// A supervisor would undo the kill; the stop command was printed instead.
    public static let managed: Int32 = 6
    /// EX_SOFTWARE: PortKilla itself failed (e.g. could not encode JSON).
    public static let internalError: Int32 = 70
}

public enum CLICommand: Equatable {
    case list(ListOptions)
    case kill(KillOptions)
    case whoami(json: Bool)
    case wait(port: Int, timeout: TimeInterval, json: Bool)
    case open(port: Int)
    case history(HistoryOptions)
    case version(json: Bool)
    case help(topic: String?)
    case agentDocs(AgentDocsOptions)
    case doctor(json: Bool, agents: Bool)
    case whois(WhoisOptions)
    case completions(shell: String)
    case mcp
    case freePort(prefer: Int, range: ClosedRange<Int>, json: Bool)
    case schema(command: String?)
    /// Debug builds only: listen on a port until killed, so tests can spawn a
    /// real, attributable server with chosen environment markers.
    case serve(port: Int)
    /// Print the registration for one agent (or all when nil).
    case mcpSetup(agent: String?)

    public struct AgentDocsOptions: Equatable {
        /// Append the snippet to `file` (default CLAUDE.md) instead of printing it.
        var write = false
        var file = "CLAUDE.md"
        /// Print a Claude Code PreToolUse hook that redirects lsof-based kills.
        var claudeHook = false
    }

    public struct WhoisOptions: Equatable {
        var port: Int?
        var pid: Int?
        var json = false
    }

    public struct HistoryOptions: Equatable {
        var json = false
        var port: Int?
        var limit = 20
    }

    public struct ListOptions: Equatable {
        var json = false
        var mine = false
        var unowned = false
        var orphaned = false
        var agent: String?
    }

    public struct KillOptions: Equatable {
        var port: Int?
        var pid: Int?
        var force = false
        var dryRun = false
        var json = false
        /// `free`: an already-free port is success, so `portkilla free 3000
        /// && npm run dev` works under `set -e`.
        var freeIsSuccess = false
        /// Every server whose agent session has ended, instead of a port.
        var orphaned = false
    }
}

/// Strict argument parsing: an option the command doesn't know is an error,
/// never silently ignored. (`kill 3000 --dry-run` on an older build killed
/// for real because the flag was unknown.)
public enum CLIArguments {

    public enum ParseError: Error, Equatable {
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
            case .missingTarget: return "a port number (or --pid <pid>) is required"
            case .tooManyTargets: return "one port number at a time"
            case .conflictingTargets: return "use one of: a port number, --pid, --orphaned"
            }
        }
    }

    /// nil means "not a CLI invocation": launch the GUI. That is only the case
    /// for no arguments or system-injected launch flags (`-psn_…`), so a
    /// mistyped subcommand is reported instead of quietly opening a window.
    public static func parse(_ arguments: [String]) -> Result<CLICommand, ParseError>? {
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
        case "whois": return parseWhois(rest)
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
        case "free-port": return parseFreePort(rest)
        case "schema": return rest.count <= 1 ? .success(.schema(command: rest.first)) : .failure(.unknownOption(rest[1], command: "schema"))
        #if DEBUG
        case "__serve":
            guard let port = rest.first.flatMap(Int.init), PortManager.isValidPortNumber(port), rest.count == 1 else {
                return .failure(.missingTarget)
            }
            return .success(.serve(port: port))
        #endif
        case "doctor": return parseDoctor(rest)
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
            case "--orphaned": options.orphaned = true
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
        if options.orphaned {
            guard options.port == nil, options.pid == nil else { return .failure(.conflictingTargets) }
            return .success(.kill(options))
        }
        guard options.port != nil || options.pid != nil else { return .failure(.missingTarget) }
        guard options.port == nil || options.pid == nil else { return .failure(.conflictingTargets) }
        return .success(.kill(options))
    }

    private static func parseWhois(_ args: [String]) -> Result<CLICommand, ParseError> {
        var options = CLICommand.WhoisOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--json" {
                options.json = true
            } else if arg == "--pid" {
                guard index + 1 < args.count else { return .failure(.missingValue(arg)) }
                index += 1
                guard let pid = Int(args[index]) else { return .failure(.invalidNumber(args[index], option: "--pid")) }
                options.pid = pid
            } else if let value = valueOf(option: "--pid", in: arg) {
                guard let pid = Int(value) else { return .failure(.invalidNumber(value, option: "--pid")) }
                options.pid = pid
            } else if arg.hasPrefix("-") {
                return .failure(.unknownOption(arg, command: "whois"))
            } else if let port = Int(arg), PortManager.isValidPortNumber(port) {
                guard options.port == nil else { return .failure(.tooManyTargets) }
                options.port = port
            } else {
                return .failure(.invalidNumber(arg, option: "port"))
            }
            index += 1
        }
        guard options.port != nil || options.pid != nil else { return .failure(.missingTarget) }
        guard options.port == nil || options.pid == nil else { return .failure(.conflictingTargets) }
        return .success(.whois(options))
    }

    private static func parseDoctor(_ args: [String]) -> Result<CLICommand, ParseError> {
        var json = false
        var agents = false
        for arg in args {
            switch arg {
            case "--json": json = true
            case "--agents": agents = true
            default: return .failure(.unknownOption(arg, command: "doctor"))
            }
        }
        return .success(.doctor(json: json, agents: agents))
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

    private static func parseFreePort(_ args: [String]) -> Result<CLICommand, ParseError> {
        var prefer = 3000
        var range: ClosedRange<Int>?
        var json = false
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--json" {
                json = true
            } else if arg == "--prefer" || arg == "--range" {
                guard index + 1 < args.count else { return .failure(.missingValue(arg)) }
                index += 1
                if arg == "--prefer" {
                    guard let port = Int(args[index]), PortManager.isValidPortNumber(port) else { return .failure(.invalidNumber(args[index], option: "--prefer")) }
                    prefer = port
                } else {
                    guard let parsed = parseRange(args[index]) else { return .failure(.invalidNumber(args[index], option: "--range")) }
                    range = parsed
                }
            } else if let value = valueOf(option: "--prefer", in: arg) {
                guard let port = Int(value), PortManager.isValidPortNumber(port) else { return .failure(.invalidNumber(value, option: "--prefer")) }
                prefer = port
            } else if let value = valueOf(option: "--range", in: arg) {
                guard let parsed = parseRange(value) else { return .failure(.invalidNumber(value, option: "--range")) }
                range = parsed
            } else {
                return .failure(.unknownOption(arg, command: "free-port"))
            }
            index += 1
        }
        // Default range: the preferred port and the 999 above it.
        let resolved = range ?? prefer...min(prefer + 999, 65535)
        guard resolved.contains(prefer) else { return .failure(.invalidNumber("\(prefer)", option: "--prefer (outside --range)")) }
        return .success(.freePort(prefer: prefer, range: resolved, json: json))
    }

    /// "3000-3999"
    private static func parseRange(_ text: String) -> ClosedRange<Int>? {
        let parts = text.split(separator: "-", maxSplits: 1).map { Int($0) }
        guard parts.count == 2, let low = parts[0], let high = parts[1],
              PortManager.isValidPortNumber(low), PortManager.isValidPortNumber(high), low <= high else { return nil }
        return low...high
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
}
