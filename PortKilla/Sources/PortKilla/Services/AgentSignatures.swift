import Foundation

/// How PortKilla recognises AI coding agents: what their processes look like
/// in the tree, what they leave in the environment of their children, and
/// what names people use for them. Pure data; the logic lives in
/// `AgentAttribution`.
enum AgentSignatures {

    /// A process in the ancestry chain. Bare binaries match on the exact
    /// executable name, never on arguments, so a project folder named
    /// "claude-code" is not mistaken for the binary. The name is
    /// case-sensitive on purpose: `claude` is the Claude Code CLI, `Claude`
    /// is the desktop app it may be running inside. App bundles match on
    /// their distinctive `.app/` path anywhere in the (lowercased) command.
    struct TreeSignature {
        let name: String
        let confidence: AgentOwner.Confidence
        let matches: (_ commandLower: String, _ executableName: String) -> Bool
    }

    /// Editors spawn shells for humans and for their built-in agents alike, so
    /// an editor ancestor only proves "started from inside the editor".
    static let appBundles: [(name: String, pathFragment: String)] = [
        ("Cursor", "/cursor.app/"),
        ("VS Code", "/visual studio code.app/"),
        ("Windsurf", "/windsurf.app/"),
        ("Zed", "/zed.app/"),
        ("Trae", "/trae.app/"),
    ]

    static let treeSignatures: [TreeSignature] = [
        TreeSignature(name: "Claude Code", confidence: .agent) { _, exe in exe == "claude" },
        TreeSignature(name: "Codex CLI", confidence: .agent) { _, exe in exe == "codex" },
        TreeSignature(name: "Gemini CLI", confidence: .agent) { _, exe in exe == "gemini" },
        TreeSignature(name: "Copilot CLI", confidence: .agent) { _, exe in exe == "copilot" },
        TreeSignature(name: "OpenCode", confidence: .agent) { _, exe in exe == "opencode" },
        TreeSignature(name: "Aider", confidence: .agent) { _, exe in exe == "aider" },
        TreeSignature(name: "Zed", confidence: .editorTerminal) { _, exe in exe == "zed" },
    ] + appBundles.map { bundle in
        TreeSignature(name: bundle.name, confidence: .editorTerminal) { cmd, _ in cmd.contains(bundle.pathFragment) }
    }

    /// An environment variable an agent leaves on its children. `value` nil
    /// means any value counts. Order is precedence: an explicit declaration
    /// first, then agents, then editor terminals, so Claude Code running
    /// inside a Cursor terminal is Claude Code.
    struct EnvMarker {
        let name: String
        let key: String
        let value: String?
        let confidence: AgentOwner.Confidence
    }

    static let envMarkers: [EnvMarker] = [
        EnvMarker(name: "Claude Code", key: "CLAUDECODE", value: nil, confidence: .agent),
        EnvMarker(name: "Cursor", key: "CURSOR_AGENT", value: nil, confidence: .agent),
        EnvMarker(name: "Gemini CLI", key: "GEMINI_CLI", value: nil, confidence: .agent),
        EnvMarker(name: "Codex CLI", key: "CODEX_SANDBOX", value: nil, confidence: .agent),
        EnvMarker(name: "Codex CLI", key: "CODEX_SANDBOX_NETWORK_DISABLED", value: nil, confidence: .agent),
        EnvMarker(name: "Cursor", key: "CURSOR_TRACE_ID", value: nil, confidence: .editorTerminal),
        EnvMarker(name: "VS Code", key: "TERM_PROGRAM", value: "vscode", confidence: .editorTerminal),
    ]

    /// An agent (or a person) can label everything it starts by exporting
    /// this before launching servers; PortKilla reads it like any marker.
    static let declaredOwnerKey = "PORTKILLA_OWNER"

    /// Names the Claude Code process itself; equals the pid the tree walk
    /// finds, which is what makes the two signals agree on a session.
    static let claudeSessionKey = "CLAUDE_PID"
    /// A UUID per Claude Code session: never recycled the way a pid is, and
    /// stable across a restart in place. Preferred identity when both sides
    /// have it.
    static let claudeSessionIdKey = "CLAUDE_CODE_SESSION_ID"

    /// Multiplexers and remote shells freeze the environment they were
    /// started with and re-parent everything under themselves, so markers
    /// and ancestry seen through one of these say nothing about which pane
    /// or session started a server.
    static let attributionBarriers: Set<String> = ["tmux", "screen", "zellij", "sshd"]

    /// VS Code forks point these at their own app bundle, which names the
    /// fork when only `TERM_PROGRAM=vscode` is set.
    static let vscodeForkHintKeys = ["VSCODE_GIT_ASKPASS_MAIN", "VSCODE_GIT_ASKPASS_NODE"]

    /// The only environment keys ever read from another process.
    static let markerKeys: Set<String> = Set(
        envMarkers.map(\.key) + [declaredOwnerKey, claudeSessionKey, claudeSessionIdKey] + vscodeForkHintKeys
    )

    /// Turns whatever someone typed into PORTKILLA_OWNER into the display
    /// name PortKilla uses, so "claude-code" and "Claude Code" are one agent.
    /// Unknown names are kept as typed (custom bots are legitimate owners).
    static func canonicalName(_ declared: String) -> String {
        // The name lands in notifications and terminal output, so control
        // characters (newlines, tabs, escape sequences) are dropped.
        let cleaned = declared
            .map { $0.isNewline || ($0.asciiValue.map { $0 < 0x20 || $0 == 0x7F } ?? false) ? " " : $0 }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(64)
        let key = cleaned.lowercased().filter { $0.isLetter || $0.isNumber }
        return aliases[key] ?? String(cleaned)
    }

    private static let aliases: [String: String] = [
        "claude": "Claude Code", "claudecode": "Claude Code",
        "codex": "Codex CLI", "codexcli": "Codex CLI",
        "gemini": "Gemini CLI", "geminicli": "Gemini CLI",
        "copilot": "Copilot CLI", "copilotcli": "Copilot CLI", "githubcopilot": "Copilot CLI",
        "opencode": "OpenCode",
        "aider": "Aider",
        "cursor": "Cursor",
        "vscode": "VS Code", "code": "VS Code", "visualstudiocode": "VS Code",
        "windsurf": "Windsurf",
        "zed": "Zed",
        "trae": "Trae",
    ]

    /// The editor whose app bundle a path points into, if any.
    static func bundleName(inPath path: String) -> String? {
        let lower = path.lowercased()
        return appBundles.first { lower.contains($0.pathFragment) }?.name
    }
}
