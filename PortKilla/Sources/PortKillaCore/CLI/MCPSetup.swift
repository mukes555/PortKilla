import Foundation

/// How each agent registers the MCP server. Printed, never written: the
/// agents' config files are theirs.
public enum MCPSetup {
    public static let agents: [String: String] = [
        "claude": """
        Claude Code (one command, per project or with --scope user):
          claude mcp add portkilla -- portkilla mcp
        or in .mcp.json / ~/.claude.json:
          { "mcpServers": { "portkilla": { "command": "portkilla", "args": ["mcp"] } } }
        """,
        "cursor": """
        Cursor (.cursor/mcp.json in the project, or ~/.cursor/mcp.json):
          { "mcpServers": { "portkilla": { "command": "portkilla", "args": ["mcp"] } } }
        """,
        "codex": """
        Codex CLI (~/.codex/config.toml):
          [mcp_servers.portkilla]
          command = "portkilla"
          args = ["mcp"]
        """,
    ]

    public static func instructions(for agent: String?) -> String {
        let chosen = agent.flatMap { agents[$0].map { [$0] } } ?? ["claude", "cursor", "codex"].compactMap { agents[$0] }
        let footer = """
        `portkilla` must be on the agent's PATH (Homebrew links it; otherwise use the full path
        /Applications/PortKilla.app/Contents/MacOS/portkilla). The agent starts the server when it
        needs it and stops it afterwards; there is nothing to keep running.
        """
        return (chosen + [footer]).joined(separator: "\n")
    }
}
