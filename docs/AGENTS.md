# PortNanny and AI agents

How PortNanny tells agents apart, what each tool gets, and what to export
when PortNanny cannot see you. `portnanny doctor --agents` prints the same
matrix checked against your machine.

## The rules

- **Agents are refused, people are warned.** `portnanny kill` refuses (exit
  3) to stop a server owned by a different agent, by a different running
  session of the same agent, or by nobody it can name when the caller is an
  agent (the app's Settings > Agents can turn that last part off for this
  Mac; it is a preference in the shared domain, a convenience for the
  person, not a lock against an agent with a shell). A person in the app is
  warned and decides. `--force` overrides, and
  the override is recorded.
- **Sessions, not tools.** Two Claude Code windows are two sessions. A
  server belongs to the session that started it; another session of the same
  tool is "another agent" to the guard.
- **Ended sessions block nobody.** When the session that started a server
  has exited, the server shows as "(ended)" and anyone may stop it.
  `portnanny kill --orphaned` sweeps all of them.
- **Editor terminals are people.** A server started from a VS Code, Cursor,
  Windsurf, Trae, or Zed terminal never locks a port. A `kill` typed in one
  is treated as a person's, except against another agent's running server,
  where it needs `--force`: the editor's own agent leaves no marker.
- **Unknown stays unknown.** PortNanny never guesses an owner. `portnanny
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

## Setting the tools up

`portnanny setup` finds the tools on this Mac and offers each step: register
the MCP server with Claude Code, write the rule file each tool reads into
the project, and print what has to be pasted by hand. Nothing is written or
run without a yes (`--yes` says yes to everything).

| Tool | Rules | MCP |
|---|---|---|
| Claude Code | `portnanny agent-docs --claude` (CLAUDE.md), or the plugin: `claude plugin marketplace add mukes555/PortNanny && claude plugin install portnanny@portnanny` | `claude mcp add portnanny -- portnanny mcp`, or the plugin |
| Codex CLI | `portnanny agent-docs --codex` (AGENTS.md) | `[mcp_servers.portnanny]` in `~/.codex/config.toml` (`portnanny mcp --setup codex`) |
| Cursor | `portnanny agent-docs --cursor` (`.cursor/rules/portnanny.mdc`) | `.cursor/mcp.json` (`portnanny mcp --setup cursor`) |
| Windsurf | `portnanny agent-docs --windsurf` (`.windsurf/rules/portnanny.md`) | its MCP settings, same command and args |
| Gemini CLI, Copilot CLI, OpenCode, Aider | `portnanny agent-docs --write --file <their rules file>` | where they read MCP servers from, same command and args |

The plugin's hook turns `kill -9 $(lsof -ti:PORT)` into a nudge toward
`portnanny free`; `portnanny agent-docs --claude-hook` prints the same hook
for a settings.json.

## Declare yourself: PORTNANNY_OWNER and PORTNANNY_SESSION

Any tool, wrapper, or person can label what it starts:

```bash
export PORTNANNY_OWNER=copilot          # who (aliases: claude, codex, cursor, ...; any name works)
export PORTNANNY_SESSION=$(uuidgen)     # which session, for tools that export none
npm run dev
```

A declared owner wins over the process tree, for the server and for the
caller, so a bot started from inside another agent's session keeps its own
name. `PORTNANNY_SESSION` is any string that is unique per session; two
servers with different values belong to different sessions, and a caller
without one is "unknown session", which never blocks a same-name kill.
The names from before 2.1, `PORTKILLA_OWNER` and `PORTKILLA_SESSION`, are
read as well, so nothing written for PortKilla needs to change.

What to export, by tool:

- **Claude Code**: nothing. It already stamps every process.
- **Codex CLI, Gemini CLI**: `PORTNANNY_SESSION`, so detached servers stay
  tied to the session that started them.
- **Copilot CLI, OpenCode, Aider**: `PORTNANNY_OWNER` and
  `PORTNANNY_SESSION`; nothing of theirs survives reparenting.
- **Copilot in VS Code, Cascade in Windsurf, Trae's agent**:
  `PORTNANNY_OWNER` in the terminal they run in, or they count as the
  editor's terminal (a person).

## Leases: reserve a port before you use it

Two agents about to start servers can race for the same free port. A lease
settles it:

```bash
portnanny exec --free-port --prefer 3000 -- npm run dev   # port, PORT, lease, identity, in one go
portnanny reserve 3000 --for 10m --reason "e2e run"       # by hand; release with portnanny release 3000
portnanny reservations                                     # who holds what, until when
```

`free-port` and `exec` skip ports others have leased; `kill` refuses other
agents on a leased port (exit 3) until the lease expires (a day at most)
or is released. `exec` also exports `PORTNANNY_OWNER` and
`PORTNANNY_SESSION`, so a server started through it is attributed to you
even when your tool leaves no marker.

## What agents should run

- `portnanny free <port>` to stop what is on a port (exit 0 if already
  free), `portnanny kill <port> --dry-run --json` to see the decision first.
- `portnanny whois <port>` when a kill is refused: who owns it and why
  PortNanny thinks so, and whether it runs in your working directory.
- Exit 6 means a supervisor (pm2, launchd, Docker, a reloader such as
  nodemon) would undo a plain kill and its tool is not on PATH; stderr names
  the command to run. When the tool is there, `kill` runs it for you and
  reports `action: "stopped"`.
- `portnanny free-port --prefer 3000` to pick a port instead of fighting
  for one.
- `portnanny drift` when "the app is not where I expect": servers that
  ended up off the port their project's .env, package.json, or vite.config
  names, and who holds that port.
- `portnanny kill --orphaned` to clean up servers left behind by sessions
  that have ended.
- `portnanny list --mine` for the servers you may stop without `--force`.
- `portnanny doctor --agents` to see how this machine's tools are
  recognised and what to export.
- `portnanny mcp` for the same through MCP: `list_ports`, `kill_port`,
  `whois_port`, `whoami`, `wait_for_port_free`. `portnanny mcp --setup`
  prints the registration for Claude Code, Cursor, and Codex.

`portnanny agent-docs --write` puts a short version of this into CLAUDE.md
or AGENTS.md; `portnanny schema <command>` documents every `--json` field.
