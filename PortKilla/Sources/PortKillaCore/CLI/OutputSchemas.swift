import Foundation

/// The JSON contracts, written down. `portkilla schema <command>` prints one;
/// a test checks that what the encoders emit stays within it. Fields are only
/// ever added within a schema version.
public enum OutputSchemas {
    public static let commands = ["list", "kill", "whoami", "wait", "history", "version", "doctor", "free-port"]

    public static let agentOwner: [String: String] = [
        "name": "agent display name, e.g. \"Claude Code\"",
        "sessionPid": "pid of the agent process for this session, when known",
        "sessionKey": "per-session id where the agent provides one (Claude Code); preferred identity",
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
    ]

    public static let all: [String: [String: String]] = [
        "list": ["<array>": "PortInfo objects (see fields below)"].merging(port) { a, _ in a },
        "kill": [
            "schema": "1", "action": "not-found | already-free | would-kill | would-refuse | refused | killed | still-running | failed",
            "port": "requested port, absent for --pid", "force": "whether --force was given", "caller": "AgentOwner of the caller, or absent",
            "targets": "[{pid, processName, port, proto, agentOwner}]", "reasons": "refusal or failure lines",
            "overriddenRefusals": "refusals --force overrode", "guardVerdict": "refused | allowed | overridden | not-evaluated: … | allowed: caller is not an agent",
            "exitCode": "0 done, 1 nothing listening, 3 refused, 4 failed, 5 still running",
        ],
        "whoami": ["schema": "1", "detected": "whether an agent was identified", "owner": "AgentOwner or absent"],
        "wait": ["schema": "1", "port": "port", "free": "true when nothing listens", "waitedSeconds": "time waited", "exitCode": "0 free, 5 timeout"],
        "history": ["<array>": "[{id, port, processName, timestamp, action, owner, killedBy}] newest first"],
        "version": ["schema": "1", "version": "semver", "bundleIdentifier": "com.mukes555.PortKilla", "installSource": "Homebrew | Applications (DMG) | development build", "architecture": "arm64 | x86_64"],
        "doctor": ["<object>": "label -> value, one entry per diagnostic line"],
        "free-port": ["schema": "1", "port": "first free port, absent when none", "preferred": "requested port", "range": "\"A-B\"", "exitCode": "0 found, 1 none"],
    ]

    public static func render(_ command: String?) -> String? {
        guard let command, let fields = all[command] else { return nil }
        var lines = ["\(command) --json"]
        for key in fields.keys.sorted() {
            lines.append("  \(key.padding(toLength: 20, withPad: " ", startingAt: 0)) \(fields[key]!)")
        }
        if command == "list" || command == "kill" || command == "whoami" {
            lines.append("  AgentOwner:")
            for key in agentOwner.keys.sorted() {
                lines.append("    \(key.padding(toLength: 18, withPad: " ", startingAt: 0)) \(agentOwner[key]!)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
