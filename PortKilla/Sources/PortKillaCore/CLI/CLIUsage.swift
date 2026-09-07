import Foundation

/// The help text, kept apart from the parser so the two stay readable.
extension CLIArguments {

    /// Per-command help; nil topic (or an unknown one) gives the overview.
    public static func usage(for topic: String?) -> String {
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
            portkilla kill --orphaned [--dry-run] [--json]
            portkilla free <port> [...]

            Stops every process listening on the port (SIGTERM, verified; --force
            sends SIGKILL). Refuses (exit 3) when another AI agent's running
            session owns it, or when the caller is an agent and nobody claims the
            server, unless --force. --dry-run reports the decision without
            signalling. free is the same command with exit 0 when the port was
            already free, for `portkilla free 3000 && npm run dev`. --orphaned
            stops every server left behind by an agent session that has ended
            (any agent's); exit 0 when there is nothing to clean up.

            A supervised listener is stopped the way its supervisor expects: a
            reloader (nodemon, next dev, uvicorn --reload, a gunicorn master) is
            stopped together with its child; a pm2 app, a launchd job, or a Docker
            container gets its own stop command (pm2 stop, brew services stop or
            launchctl bootout, docker stop), run for you when the tool is on PATH
            and printed with exit 6 when it is not. --force kills the listener
            itself regardless.

            Exit codes: 0 done, 1 nothing listening, 2 usage, 3 refused, 4 kill
            failed, 5 still running after the wait, 6 managed, 70 internal error.
            """
        case "whois": return """
            portkilla whois <port> [--json]
            portkilla whois --pid <pid> [--json]

            Everything PortKilla knows about what listens there: process, command,
            project, connected clients, the AI agent that started it together with
            the evidence (ancestry, environment markers, declaration), and what
            `kill` would do for you and why. Exit 1 when nothing listens.
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
            environment, or declared via PORTKILLA_OWNER (and PORTKILLA_SESSION).
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
            list_ports, kill_port (dry-run by default), whois_port, whoami, and
            wait_for_port_free. It is not a background service: each agent starts
            its own copy when it needs one and stops it afterwards, so register it
            once and forget it. `--setup` prints the registration (the exact
            `claude mcp add` command, Cursor's mcp.json, Codex's config.toml).
            Run by hand it waits silently for requests; Ctrl-C stops it.
            """
        case "free-port": return """
            portkilla free-port [--prefer 3000] [--range A-B] [--json]

            Prints the first port in the range that nothing listens on and that can
            be bound right now, starting at --prefer (default 3000; default range is
            the preferred port plus 999). Stateless: no reservation is made. Exit 1
            when the whole range is taken.
            """
        case "schema": return """
            portkilla schema [list|kill|whois|whoami|wait|history|version|doctor|agents|free-port]

            Prints the JSON contract for a command's --json output: every field and
            its meaning (`agents` is `doctor --agents`). Fields are only ever added,
            never renamed or removed, within a schema version.
            """
        case "reserve", "release", "reservations": return """
            portkilla reserve <port> [--for 10m] [--reason "..."] [--json]
            portkilla release <port> [--force] [--json]
            portkilla reservations [--json]

            A lease on a free port: free-port and exec skip it for everyone else,
            and kill refuses other agents on it, until it expires (default 10
            minutes, at most a day) or you release it. Reserving a port you already
            hold renews the lease. Exit 1 when the port is in use, 3 when someone
            else holds the lease. release needs --force for another holder's lease.
            """
        case "exec": return """
            portkilla exec [--port N | --free-port [--prefer 3000] [--range A-B]] [--no-reserve]
                           [--owner NAME] [--session KEY] -- <command> [args...]

            Runs the command with PORT set to a free port (--port must be free;
            --free-port, the default, takes the first free one nobody else has
            leased, starting at --prefer), leases the port for the run, and exports
            PORTKILLA_OWNER and PORTKILLA_SESSION (yours, unless given) so the
            server is attributed to you even when your tool leaves no marker.
            Signals are forwarded; the exit code is the command's.
            """
        case "doctor": return """
            portkilla doctor [--json] [--agents]

            Version, macOS, architecture, install source, quarantine state, which
            scanner is in use and how long a scan takes, PATH resolution, and login
            item status. Paste it into bug reports.

            --agents prints the agent compatibility matrix against this machine:
            which tools are running or installed, how each is recognised, how
            precisely its sessions are told apart, and where each fact came from.
            """
        default: return usage
        }
    }

    public static let usage = """
    PortKilla, the macOS port manager

    Usage:
      portkilla list [--json] [--mine | --agent <name> | --unowned | --orphaned]
      portkilla kill <port> [--force|-9] [--dry-run] [--json]
      portkilla kill --pid <pid> [--force|-9] [--dry-run] [--json]
      portkilla kill --orphaned [--dry-run] [--json]   servers whose agent session ended
      portkilla free <port> [...]        like kill, but exit 0 if already free
      portkilla whois <port> [--json]    who started it, and why PortKilla thinks so
      portkilla reserve <port> [--for 10m] [--reason "..."] [--json]
      portkilla release <port> [--force]  |  portkilla reservations [--json]
      portkilla exec [--port N | --free-port] [--] <command...>   PORT set, leased, attributed
      portkilla wait <port> [--timeout 30] [--json]
      portkilla open <port>
      portkilla history [--json] [--port <port>] [--limit 20]
      portkilla whoami [--json]
      portkilla free-port [--prefer 3000] [--range 3000-3999] [--json]
      portkilla schema [command]         JSON output contracts
      portkilla doctor [--json] [--agents]
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
    agent session, or one nobody claims when the caller is an agent, unless
    --force. Owners are detected from the process tree and from the
    environment agents leave on their children; export PORTKILLA_OWNER=<name>
    to declare who you are (and to label what you start), and
    PORTKILLA_SESSION=<unique> to tell your sessions apart.

    Exit codes: 0 done, 1 nothing listening, 2 usage, 3 refused (another
    agent's live session owns it, or nobody claims it), 4 kill failed,
    5 still running after the wait, 6 managed (a supervisor would undo the
    kill; the stop command is printed), 70 internal error. --dry-run exits
    0 when it would kill and 3 when it would refuse. `portkilla help
    <command>` or `<command> --help` for more.

    The GUI launches when run with no arguments.
    """
}
