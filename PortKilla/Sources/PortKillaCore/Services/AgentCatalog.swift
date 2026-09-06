import Foundation

/// One row of the compatibility matrix: how a tool is recognised, how
/// precisely its sessions can be told apart, and where each fact came from.
public struct AgentCatalogEntry: Encodable {
    public let name: String
    /// "agent" (something that runs commands on its own) or "editor terminal".
    public let kind: String
    public let executables: [String]
    public let bundles: [String]
    /// "CLAUDECODE" or "TERM_PROGRAM=vscode"
    public let envSignals: [String]
    public let session: String
    public let provenance: String
    public let tip: String?
}

/// The compatibility matrix, built from `AgentSignatures` so it cannot
/// drift from what the scanner matches. `doctor --agents` prints it against
/// the live machine; a test keeps docs/AGENTS.md in step with it.
public enum AgentCatalog {

    struct Note {
        let session: String
        let provenance: String
        let tip: String?
    }

    static let notes: [String: Note] = [
        "Claude Code": Note(
            session: "exact: CLAUDE_CODE_SESSION_ID and CLAUDE_PID travel with every process it starts, so a server keeps its session through nohup, pm2, or a shell that exited",
            provenance: "verified on Claude Code 2.1 (2026-09): every command it runs carries CLAUDECODE=1, CLAUDE_PID, and CLAUDE_CODE_SESSION_ID",
            tip: nil),
        "Codex CLI": Note(
            session: "pid while the server is still under the codex process; a detached server is Codex CLI without a session, because Codex exports no session id",
            provenance: "verified on Codex CLI 0.147 (2026-09): sandboxed commands carry CODEX_SANDBOX (seatbelt on macOS) and CODEX_SANDBOX_NETWORK_DISABLED=1",
            tip: "export PORTKILLA_SESSION=<anything unique per session> before starting servers to keep two Codex sessions apart"),
        "Gemini CLI": Note(
            session: "pid while attached; a detached server carries the name only",
            provenance: "Gemini CLI source: its shell tool sets GEMINI_CLI=1; not verified on a live install",
            tip: "export PORTKILLA_SESSION=<anything unique per session> to pin detached servers to a session"),
        "Copilot CLI": Note(
            session: "pid while attached; nothing survives reparenting",
            provenance: "executable name only; no environment marker is known",
            tip: "export PORTKILLA_OWNER=copilot and PORTKILLA_SESSION=<unique> before starting servers"),
        "OpenCode": Note(
            session: "pid while attached; nothing survives reparenting",
            provenance: "executable name only; no environment marker is known",
            tip: "export PORTKILLA_OWNER=opencode and PORTKILLA_SESSION=<unique> before starting servers"),
        "Aider": Note(
            session: "pid while attached; nothing survives reparenting",
            provenance: "executable name only; no environment marker is known",
            tip: "export PORTKILLA_OWNER=aider and PORTKILLA_SESSION=<unique> before starting servers"),
        "Cursor": Note(
            session: "pid of the Cursor process while attached; after reparenting CURSOR_AGENT names the agent without a session",
            provenance: "Cursor documentation: CURSOR_AGENT=1 on agent-run commands, CURSOR_TRACE_ID in the integrated terminal; Cursor.app in the tree",
            tip: nil),
        "VS Code": Note(
            session: "none: a terminal, not an agent",
            provenance: "TERM_PROGRAM=vscode in every integrated terminal; VSCODE_GIT_ASKPASS_* points at the fork that owns it",
            tip: "Copilot agent mode leaves no marker; export PORTKILLA_OWNER=copilot in its terminal to be identified"),
        "Windsurf": Note(
            session: "none: a terminal, not an agent",
            provenance: "Windsurf.app in the tree, or TERM_PROGRAM=vscode with VSCODE_GIT_ASKPASS_* pointing into Windsurf.app",
            tip: "Cascade leaves no marker; export PORTKILLA_OWNER=windsurf in its terminal"),
        "Zed": Note(
            session: "none: a terminal, not an agent",
            provenance: "executable zed, or Zed.app in the tree",
            tip: nil),
        "Trae": Note(
            session: "none: a terminal, not an agent",
            provenance: "Trae.app in the tree, or TERM_PROGRAM=vscode with VSCODE_GIT_ASKPASS_* pointing into Trae.app",
            tip: "export PORTKILLA_OWNER=trae in its terminal"),
    ]

    public static let entries: [AgentCatalogEntry] = {
        var names: [String] = []
        for signature in AgentSignatures.treeSignatures where !names.contains(signature.name) { names.append(signature.name) }
        for marker in AgentSignatures.envMarkers where !names.contains(marker.name) { names.append(marker.name) }

        let entries = names.map { name -> AgentCatalogEntry in
            let signatures = AgentSignatures.treeSignatures.filter { $0.name == name }
            let markers = AgentSignatures.envMarkers.filter { $0.name == name }
            let actsOnItsOwn = signatures.contains { $0.confidence == .agent } || markers.contains { $0.confidence == .agent }
            let note = notes[name]
            return AgentCatalogEntry(
                name: name,
                kind: actsOnItsOwn ? "agent" : "editor terminal",
                executables: signatures.map(\.label).filter { !$0.hasPrefix("/") },
                bundles: signatures.map(\.label).filter { $0.hasPrefix("/") },
                envSignals: markers.map { marker in marker.value.map { "\(marker.key)=\($0)" } ?? marker.key },
                session: note?.session ?? "",
                provenance: note?.provenance ?? "",
                tip: note?.tip
            )
        }
        // Agents first, then editors, each in signature order.
        return entries.filter { $0.kind == "agent" } + entries.filter { $0.kind != "agent" }
    }()

    public static func entry(named name: String) -> AgentCatalogEntry? {
        entries.first { $0.name == name }
    }
}
