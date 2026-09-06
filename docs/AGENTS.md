# PortKilla and AI agents

How PortKilla tells agents apart, what each tool gets, and what to export
when PortKilla cannot see you. `portkilla doctor --agents` prints the same
matrix checked against your machine.

## The rules

- **Agents are refused, people are warned.** `portkilla kill` refuses (exit
  3) to stop a server owned by a different agent, by a different running
  session of the same agent, or by nobody it can name when the caller is an
  agent. A person in the app is warned and decides. `--force` overrides, and
  the override is recorded.
- **Sessions, not tools.** Two Claude Code windows are two sessions. A
  server belongs to the session that started it; another session of the same
  tool is "another agent" to the guard.
- **Ended sessions block nobody.** When the session that started a server
  has exited, the server shows as "(ended)" and anyone may stop it.
  `portkilla kill --orphaned` sweeps all of them.
- **Editor terminals are people.** A server started from a VS Code, Cursor,
  Windsurf, Trae, or Zed terminal never locks a port. A `kill` typed in one
  is treated as a person's, except against another agent's running server,
  where it needs `--force`: the editor's own agent leaves no marker.
- **Unknown stays unknown.** PortKilla never guesses an owner. `portkilla
  whois <port>` shows the evidence it used: the ancestry it walked, the
  markers it found, and what was declared.

## Compatibility matrix

| Tool | Kind | Recognised by | Sessions | Verified |
|---|---|---|---|---|
| Claude Code | agent | executable `claude`; env `CLAUDECODE`, `CLAUDE_PID`, `CLAUDE_CODE_SESSION_ID` | exact: the session id and pid travel with every process it starts and survive reparenting | Claude Code 2.1, 2026-09 |
| Codex CLI | agent | executable `codex`; env `CODEX_SANDBOX`, `CODEX_SANDBOX_NETWORK_DISABLED` | pid while the server is still under `codex`; a detached server is Codex CLI without a session | Codex CLI 0.147, 2026-09 |
| Gemini CLI | agent | executable `gemini`; env `GEMINI_CLI` | pid while attached | Gemini CLI source; not verified on a live install |
| Copilot CLI | agent | executable `copilot` | pid while attached | executable name only |
| OpenCode | agent | executable `opencode` | pid while attached | executable name only |
| Aider | agent | executable `aider` | pid while attached | executable name only |
| Cursor | agent (an editor with a built-in agent) | Cursor.app in the tree; env `CURSOR_AGENT` (agent-run commands), `CURSOR_TRACE_ID` (the terminal) | pid of the Cursor process while attached | Cursor documentation |
| VS Code | editor terminal | Visual Studio Code.app in the tree; env `TERM_PROGRAM=vscode`, `VSCODE_GIT_ASKPASS_*` names the fork | none | observed |
| Windsurf | editor terminal | Windsurf.app in the tree, or the VS Code fork hints | none | observed |
| Trae | editor terminal | Trae.app in the tree, or the VS Code fork hints | none | observed |
| Zed | editor terminal | executable `zed`, Zed.app in the tree | none | observed |

"Verified" says where the facts come from. Marker names for Claude Code and
Codex were checked against the installed binaries; the others come from the
tools' documentation or source and are marked as such.

## Declare yourself: PORTKILLA_OWNER and PORTKILLA_SESSION

Any tool, wrapper, or person can label what it starts:

```bash
export PORTKILLA_OWNER=copilot          # who (aliases: claude, codex, cursor, ...; any name works)
export PORTKILLA_SESSION=$(uuidgen)     # which session, for tools that export none
npm run dev
```

A declared owner wins over the process tree, for the server and for the
caller, so a bot started from inside another agent's session keeps its own
name. `PORTKILLA_SESSION` is any string that is unique per session; two
servers with different values belong to different sessions, and a caller
without one is "unknown session", which never blocks a same-name kill.

What to export, by tool:

- **Claude Code**: nothing. It already stamps every process.
- **Codex CLI, Gemini CLI**: `PORTKILLA_SESSION`, so detached servers stay
  tied to the session that started them.
- **Copilot CLI, OpenCode, Aider**: `PORTKILLA_OWNER` and
  `PORTKILLA_SESSION`; nothing of theirs survives reparenting.
- **Copilot in VS Code, Cascade in Windsurf, Trae's agent**:
  `PORTKILLA_OWNER` in the terminal they run in, or they count as the
  editor's terminal (a person).

## What agents should run

- `portkilla free <port>` to stop what is on a port (exit 0 if already
  free), `portkilla kill <port> --dry-run --json` to see the decision first.
- `portkilla whois <port>` when a kill is refused: who owns it and why
  PortKilla thinks so, and whether it runs in your working directory.
- `portkilla free-port --prefer 3000` to pick a port instead of fighting
  for one.
- `portkilla kill --orphaned` to clean up servers left behind by sessions
  that have ended.
- `portkilla list --mine` for the servers you may stop without `--force`.
- `portkilla doctor --agents` to see how this machine's tools are
  recognised and what to export.
- `portkilla mcp` for the same through MCP: `list_ports`, `kill_port`,
  `whois_port`, `whoami`, `wait_for_port_free`. `portkilla mcp --setup`
  prints the registration for Claude Code, Cursor, and Codex.

`portkilla agent-docs --write` puts a short version of this into CLAUDE.md
or AGENTS.md; `portkilla schema <command>` documents every `--json` field.
