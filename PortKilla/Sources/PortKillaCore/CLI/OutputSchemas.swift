import Foundation

/// The JSON contracts, written down. `portkilla schema <command>` prints one;
/// a test checks that what the encoders emit stays within it. Fields are only
/// ever added within a schema version.
public enum OutputSchemas {
    public static let commands = ["list", "kill", "whois", "whoami", "wait", "history", "version", "doctor", "agents", "free-port"]

    public static let agentOwner: [String: String] = [
        "name": "agent display name, e.g. \"Claude Code\"",
        "sessionPid": "pid of the agent process for this session, when known",
        "sessionKey": "per-session id: the agent's own (Claude Code) or PORTKILLA_SESSION; preferred identity",
        "source": "\"process tree\" | \"environment\" | \"declared\"",
        "confidence": "\"agent\" | \"editor terminal\"",
        "sessionEnded": "true when the session that started the process has exited",
    ]

    public static let port: [String: String] = [
        "port": "port number", "pid": "process id", "processName": "executable name", "command": "command line, secrets redacted",
        "user": "owning user", "memoryUsage": "human-readable RSS", "memorySizeKB": "RSS in KB", "type": "classification, e.g. \"Node.js\"",
        "projectName": "project folder name, when known", "projectPath": "working directory, when known",
        "containerName": "Docker container, when the port is published by one", "children": "child processes [{pid, name, command}]",
        "bindAddress": "\"*\" / \"0.0.0.0\" / \"::\" mean all interfaces", "proto": "\"tcp\" | \"udp\"", "cpuPercent": "CPU between scans",
        "age": "human-readable process age, when known", "agentOwner": "AgentOwner or absent", "connections": "established TCP connections on this port",
        "managedBy": "ManagedRuntime or absent: a supervisor that would undo a plain kill",
    ]

    public static let managedRuntime: [String: String] = [
        "kind": "pm2 | launchd | docker | reloader", "name": "pm2 app, launchd label, container, or the reloader (nodemon, next dev, ...)",
        "supervisorPid": "the process kill signals instead of the listener, for reloaders and masters", "supervisorName": "its executable name",
        "stopArguments": "argv of the command that stops it for real, when one exists", "stopCommand": "the same command, for display",
    ]

    public static let evidence: [String: String] = [
        "declaredOwner": "PORTKILLA_OWNER as found in the environment, before canonicalising",
        "declaredSession": "PORTKILLA_SESSION as found",
        "ancestry": "[{pid, name, role}] from the parent upwards, ending with the deciding ancestor; role is \"agent: X\", \"editor: X\", \"barrier\", or absent",
        "markers": "{key: value} for the allowlisted marker keys present in the environment",
        "decidedBy": "declared | process tree | environment | docker (the container owns the port) | none",
        "owner": "AgentOwner or absent",
    ]

    public static let whoisTarget: [String: String] = [
        "port": "port number", "proto": "\"tcp\" | \"udp\"", "bindAddress": "bind address, when known", "pid": "process id",
        "processName": "executable name", "command": "command line, secrets redacted", "user": "owning user",
        "type": "classification, e.g. \"Node.js\"", "age": "human-readable process age, when known",
        "projectName": "project folder name, when known", "projectPath": "working directory, when known",
        "containerName": "Docker container, when published by one", "connections": "established TCP connections",
        "peers": "[{host, port, kind}] remote ends of the established connections; kind is local | lan | remote",
        "children": "child processes [{pid, name, command}]", "agentOwner": "AgentOwner or absent",
        "managedBy": "ManagedRuntime or absent",
        "evidence": "AttributionEvidence (fields below)",
        "verdict": "what kill would do for this caller, same vocabulary as kill.guardVerdict",
        "reason": "the refusal reason, when refused",
        "sameProject": "the target runs in the caller's working directory, above it, or below it",
    ]

    public static let agentStatus: [String: String] = [
        "name": "tool display name", "kind": "\"agent\" | \"editor terminal\"",
        "recognisedBy": "[\"executable claude\", \"env CLAUDECODE\", \"cursor.app in the tree\", ...]",
        "session": "how precisely sessions of this tool are told apart", "provenance": "where the facts come from and what was verified",
        "tip": "what to export to be identified better, when applicable",
        "running": "processes of this tool right now", "installedAt": "where the executable was found on PATH, when it was",
    ]

    public static let all: [String: [String: String]] = [
        "list": ["<array>": "PortInfo objects (see fields below)"].merging(port) { a, _ in a },
        "kill": [
            "schema": "1", "action": "not-found | already-free | no-orphans | would-kill | would-refuse | refused | managed | killed | stopped | still-running | failed",
            "port": "requested port, absent for --pid and --orphaned", "force": "whether --force was given", "caller": "AgentOwner of the caller, or absent",
            "targets": "[{pid, processName, port, proto, agentOwner, connections, projectPath, managedBy}]", "reasons": "refusal or failure lines",
            "stoppedVia": "supervisors signalled or commands run in place of a plain kill",
            "overriddenRefusals": "refusals --force overrode", "guardVerdict": "refused | allowed | overridden | not-evaluated: … | allowed: caller is not an agent",
            "exitCode": "0 done, 1 nothing listening, 3 refused, 4 failed, 5 still running, 6 managed (a supervisor would undo it; the stop command is in reasons)",
        ],
        "whois": [
            "schema": "1", "port": "requested port, absent for --pid", "pid": "requested pid, absent for a port",
            "caller": "AgentOwner of the caller, or absent", "targets": "[Dossier] one per process (fields below)", "exitCode": "0 found, 1 nothing listening",
        ],
        "whoami": ["schema": "1", "detected": "whether an agent was identified", "owner": "AgentOwner or absent"],
        "wait": ["schema": "1", "port": "port", "free": "true when nothing listens", "waitedSeconds": "time waited", "exitCode": "0 free, 5 timeout"],
        "history": ["<array>": "[{id, port, processName, timestamp, action, owner, killedBy}] newest first; action is Killed, Detected, or Refused (then killedBy names the agent that was refused)"],
        "version": ["schema": "1", "version": "semver", "bundleIdentifier": "com.mukes555.PortKilla", "installSource": "Homebrew | Applications (DMG) | development build", "architecture": "arm64 | x86_64"],
        "doctor": ["<object>": "label -> value, one entry per diagnostic line"],
        "agents": ["schema": "1", "caller": "AgentOwner of the caller, or absent", "agents": "[AgentStatus] the compatibility matrix against this machine (fields below)"],
        "free-port": ["schema": "1", "port": "first free port, absent when none", "preferred": "requested port", "range": "\"A-B\"", "exitCode": "0 found, 1 none"],
    ]

    /// Sub-objects a command's output embeds, printed under it.
    static let nested: [String: [(String, [String: String])]] = [
        "list": [("AgentOwner", agentOwner), ("ManagedRuntime", managedRuntime)],
        "kill": [("AgentOwner", agentOwner), ("ManagedRuntime", managedRuntime)],
        "whoami": [("AgentOwner", agentOwner)],
        "whois": [("Dossier", whoisTarget), ("AttributionEvidence", evidence), ("AgentOwner", agentOwner), ("ManagedRuntime", managedRuntime)],
        "agents": [("AgentStatus", agentStatus), ("AgentOwner", agentOwner)],
    ]

    public static func render(_ command: String?) -> String? {
        guard let command, let fields = all[command] else { return nil }
        var lines = ["\(command == "agents" ? "doctor --agents" : command) --json"]
        for key in fields.keys.sorted() {
            lines.append("  \(key.padding(toLength: 20, withPad: " ", startingAt: 0)) \(fields[key]!)")
        }
        for (name, block) in nested[command] ?? [] {
            lines.append("  \(name):")
            for key in block.keys.sorted() {
                lines.append("    \(key.padding(toLength: 18, withPad: " ", startingAt: 0)) \(block[key]!)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
