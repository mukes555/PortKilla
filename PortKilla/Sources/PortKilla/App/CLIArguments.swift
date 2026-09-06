import Foundation

/// Exit codes are part of the CLI's contract with scripts and agents.
enum CLIExit {
    static let ok: Int32 = 0
    static let notFound: Int32 = 1
    static let usage: Int32 = 2
    static let refused: Int32 = 3
    static let killFailed: Int32 = 4
    static let stillRunning: Int32 = 5
}

enum CLICommand: Equatable {
    case list(ListOptions)
    case kill(KillOptions)
    case whoami(json: Bool)
    case version
    case help
    case agentDocs

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

        var message: String {
            switch self {
            case .unknownCommand(let name): return "unknown command '\(name)'"
            case .unknownOption(let option, let command): return "unknown option '\(option)' for '\(command)'"
            case .missingValue(let option): return "'\(option)' needs a value"
            case .invalidNumber(let value, let option): return "'\(value)' is not a valid number for \(option)"
            case .missingTarget: return "kill needs a port number (or --pid <pid>)"
            case .tooManyTargets: return "kill takes one port number"
            }
        }
    }

    /// nil means "not a CLI invocation": launch the GUI. That is only the case
    /// for no arguments or system-injected launch flags (`-psn_…`), so a
    /// mistyped subcommand is reported instead of quietly opening a window.
    static func parse(_ arguments: [String]) -> Result<CLICommand, ParseError>? {
        guard let command = arguments.first else { return nil }
        if command.hasPrefix("-") && !["--help", "-h", "--version"].contains(command) {
            return nil
        }
        let rest = Array(arguments.dropFirst())

        switch command {
        case "list": return parseList(rest)
        case "kill": return parseKill(rest)
        case "whoami": return parseWhoami(rest)
        case "version", "--version": return rest.isEmpty ? .success(.version) : .failure(.unknownOption(rest[0], command: command))
        case "help", "--help", "-h": return .success(.help)
        case "agent-docs": return rest.isEmpty ? .success(.agentDocs) : .failure(.unknownOption(rest[0], command: command))
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

    private static func parseKill(_ args: [String]) -> Result<CLICommand, ParseError> {
        var options = CLICommand.KillOptions()
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
                    options.port = port
                } else {
                    return .failure(.invalidNumber(arg, option: "port"))
                }
            }
            index += 1
        }
        guard options.port != nil || options.pid != nil else { return .failure(.missingTarget) }
        return .success(.kill(options))
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

    static let usage = """
    PortKilla — macOS port manager

    Usage:
      portkilla list [--json] [--mine | --agent <name> | --unowned | --orphaned]
      portkilla kill <port> [--force|-9] [--dry-run] [--json]
      portkilla kill --pid <pid> [--force|-9] [--dry-run] [--json]
      portkilla whoami [--json]
      portkilla agent-docs
      portkilla version
      portkilla help

    kill stops every process listening on the port (use --pid for one of
    them). --dry-run reports what would happen without signalling anything.

    Friendly-fire guard: kill refuses to stop a port owned by a different AI
    agent session unless --force. Owners are detected from the process tree
    and from the environment agents leave on their children; export
    PORTKILLA_OWNER=<name> to declare who you are (and to label what you start).

    Exit codes: 0 done, 1 nothing listening, 2 usage, 3 refused (another
    agent's live session owns it), 4 kill failed, 5 still running after the
    wait. --dry-run exits 0 when it would kill and 3 when it would refuse.

    The GUI launches when run with no arguments.
    """
}
