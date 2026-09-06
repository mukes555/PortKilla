# Changelog

All notable changes are documented here. The GitHub Release notes for each
version are generated automatically from the matching section below, so keep
entries user-facing and concise.

Format: one `## <version> — <date>` heading per release, with changes grouped
under **Added**, **Changed**, **Fixed**, **Security**, or **Distribution**.
Accumulate work-in-progress notes under **[Unreleased]** as you land PRs; on
release, rename it to the version and date.

## [Unreleased]

<!-- next -->

## 1.10.0 — 2026-09-06

### The agent batch

### Changed
- **One kill decision for every path.** The friendly-fire guard used to live
  only in the CLI. Now the GUI warns before you kill a port owned by another
  agent's running session (even with confirmations off), bulk dialogs say how
  many targets belong to running agents, link-initiated kills show the owner
  before asking, and port guards never auto-kill one.
- **Agent versus editor terminal.** `TERM_PROGRAM=vscode` fires for every VS
  Code fork and for humans typing in an editor terminal, and Windsurf or Trae
  collapsed into "VS Code". Editor signals now mean "started inside the
  editor" and are never a reason to refuse; the fork is resolved from the
  editor's own environment; `CURSOR_AGENT`, `GEMINI_CLI`, and Codex's sandbox
  markers identify real agents.
- **Session ended** is a first-class state: a grey "(ended)" chip, no longer
  blocking anyone, and `list --orphaned` to find abandoned servers. Ports
  fronted by Docker never get an agent owner.
- The tree walk starts at the parent, so an editor's own helper resolves to
  the editor instead of a "session" of one; the caller's identity gets the
  same session-liveness check as targets.
- `PORTKILLA_OWNER` is canonicalised (`claude-code` is "Claude Code") and,
  when exported before starting servers, labels them.
- Kill history records who started the process and who stopped it (you, the
  port guard, or a link).

### Added
- `portkilla kill --dry-run`, `--json`, `--pid <pid>`; `kill` stops every
  process on the port; documented exit codes (0 done, 1 nothing listening,
  2 usage, 3 refused, 4 failed, 5 still running); errors on stderr.
- `portkilla list --mine`, `--agent <name>`, `--unowned`, `--orphaned`;
  `whoami --json`; `portkilla agent-docs` prints a CLAUDE.md / AGENTS.md
  snippet.
- Strict argument parsing: an unknown flag is an error. (`kill 3000
  --dry-run` on 1.9 killed for real because the flag was ignored.) A mistyped
  subcommand no longer launches the GUI.
- The GUI search matches agent names; the detail sheet shows session and
  source; the chip tooltip explains how PortKilla knows.

## 1.9.0 — 2026-09-06

### The safety batch

Every item here came out of a full audit; none removes a feature.

### Fixed
- **Subprocess timeouts leaked** a file descriptor and a blocked thread each
  time `lsof` or `docker` hung; after enough of them, refreshes and kills
  silently stopped. Pipe output is now collected without a blocking read.
- **Crash on launch** from a corrupt hotkey preference, and a CPU-pegging or
  throwing timer from an out-of-range refresh interval. Every stored
  preference is validated (hotkey, interval, watched and guarded ports).
- `portkilla://show` during a cold launch could dereference the popover
  before it existed. Scheme-initiated kills are now one confirmation per
  delivery with a short cooldown, so a page can't stack dialogs.
- **Tree kill** re-enumerated the whole process table at every node with no
  cycle guard. It now walks one snapshot with a visited set and depth limit.
- **Port guards** killed and notified every scan, forever, when a supervised
  process (pm2, nodemon, launchd KeepAlive) kept rebinding. After three kills
  in a minute the guard stands down with a single notification.
- **Update check** reported "up to date" on any HTTP error or when offline,
  then suppressed retries for a day. Failures are now reported as failures
  and retried on the next launch; the URL cache is bypassed.
- **Kill verdicts were too hasty:** a one-second wait marked healthy Node or
  Postgres shutdowns as failures. SIGTERM now gets three seconds, SIGKILL
  one, and the message says "still shutting down" instead of "failed".
- A machine with zero listeners fell through to the slow `lsof` path on every
  refresh. An empty native result is now a real answer.
- Context-menu **Kill Process Tree** and **Force Kill**, and Test Radar
  kills, bypassed the confirm-before-kill setting. All kills now share one
  confirmation flow.
- An undecodable bind address made the "exposed" badge disappear; it now
  fails closed and shows the port as wildcard-bound.
- **Reset all settings** promised to reset the hotkey and didn't.
- The exit-wait had a narrow race where a late kernel event could change a
  result after it was decided.

### Security
- The agent-attribution environment read now enforces its allowlist at the
  byte level: no process environment is ever decoded into strings beyond the
  five marker keys, and the buffer is zeroed after use.
- CSV export escapes every column and treats tab and carriage return as
  formula lead-ins. `docker stop` passes `--` before the container name.

## 1.8.3 — 2026-09-06

### Fixed
- A restarted agent could not kill its own older dev server without `--force`:
  the server's `CLAUDE_PID` marker pointed at the previous session. When that
  session process no longer exists, the owner keeps the agent name but no
  longer pins a session, so the same tool is allowed through.

## 1.8.2 — 2026-09-06

### Fixed
- `portkilla version` still printed `dev` when invoked by bare name through
  PATH (argv[0] carries no path). The CLI now asks the kernel for its real
  executable path before locating the app bundle.

## 1.8.1 — 2026-09-06

### Fixed
- `portkilla version` printed `dev` when run through a symlink (as installed
  by Homebrew); it now resolves the link to the app bundle.

### Distribution
- The Homebrew cask links `portkilla` onto your PATH, so the CLI (`list`,
  `kill`, `whoami`) works right after `brew install --cask portkilla`.

## 1.8.0 — 2026-09-06

### Changed
- **Agent attribution now survives detached servers.** Besides the process
  tree, PortKilla reads the environment markers agents leave on their
  children (`CLAUDECODE`, `CURSOR_TRACE_ID`, `TERM_PROGRAM=vscode`,
  `GEMINI_CLI`). A server backgrounded by an agent's shell, or started via
  nohup/pm2, is reparented to launchd and lost the tree link in 1.7.0; it is
  now attributed correctly. Only that allowlist of keys is ever read.
- Session identity is recovered from `CLAUDE_PID`, which matches the pid the
  tree walk finds, so the two signals agree.

### Added
- `portkilla whoami` prints how the friendly-fire guard identifies the caller
  (name, session, and whether it was detected or declared).
- Codex CLI, Gemini CLI, Copilot CLI, and OpenCode are recognised.
- The `kill` refusal now names both sides and points at `whoami`.


## 1.7.0 — 2026-09-06

### Added
- **Agent attribution & friendly-fire protection** — so AI coding agents don't
  kill each other's dev servers. PortKilla attributes each listening process to
  the agent that spawned it (Claude Code, Cursor, VS Code, Windsurf, Zed, Trae,
  Aider) by walking the process ancestry — no launcher or opt-in required.
  - A ✨ agent chip on rows and an **Agent** field in the detail sheet.
  - `portkilla list` shows an **AGENT** column.
  - **`portkilla kill` refuses** to stop a port owned by a different agent
    session unless `--force` (exit code 3). Set `PORTKILLA_OWNER` to declare the
    caller's identity, or it's detected from the process tree.
  - GUI kill confirmations note the owning agent.
  - Best-effort: a detached server (double-fork / nohup / pm2) loses the
    ancestry link and reports no owner rather than guessing.

## 1.6.0 — 2026-08-08

### Hardening, UI polish, and contributor-readiness

**Distribution**
- The release is now a **universal binary** (arm64 + x86_64) — runs natively on
  both Apple Silicon and Intel Macs. Minimum macOS 13 (Ventura).

**UI**
- **Simple / Advanced row density** with a modern segmented header toggle. Simple
  shows one clean line per port; Advanced adds command, chips, CPU, and the tree.
- **Settings redesigned** as a native macOS System Settings-style **sidebar**
  window (⚙︎ / ⌘,), replacing the overloaded gear menu. New: Notifications
  master toggle, menu-bar count toggle, in-app shortcut reference, Reset all.
- Header split into three clear controls: density toggle · **⋯ actions** ·
  **⚙︎ settings**.
- **Pin as Floating Window** now closes the popover instead of showing two copies.

**Security & correctness** (from a multi-agent audit)
- URL-scheme kills require confirmation and refuse protected processes.
- Fixed a data race in `waitForExit`; tree-kill children run the identity check;
  bounded reads on fixed kernel arrays; CPU% no longer wraps on PID reuse; guard
  fires on occupant swaps; docker-proxy classified as Docker; CSV quotes `\r`.

**Engineering & docs**
- Dev-only snapshot/demo hooks gated behind `#if DEBUG` (out of the shipped app).
- Deduplicated: one `KillConfirm` dialog, one `isWildcardHost` check.
- Fixed the test-runner self-exclusion string; removed unreachable `TestType` cases.
- Added **CONTRIBUTING.md**, **ARCHITECTURE.md**, **SECURITY.md**, issue/PR
  templates; fixed the README build path.
- 60 tests (+ regression coverage), universal build verified.

## 1.5.0 — 2026-08-07

### The native scanner release

- **Raw-syscall scanning (libproc)**: process + socket enumeration now uses
  kernel interfaces directly — a full scan (≈480 processes, ≈60 listeners) takes
  ~19ms with **zero subprocesses** (previously two lsof runs + ps per refresh).
  lsof/ps remain only as an automatic fallback. CPU% is now a true
  between-scans delta, and process names are no longer truncated at 9 chars.
- **Pin as Floating Window** (gear menu): keep the port list on top while you
  work; refresh stays at full cadence while pinned.
- **Port guards** (bolt-shield in the Watched section): opt-in per port —
  anything unprotected of yours that grabs a guarded port is auto-killed, with
  a notification. Explicit confirmation required to enable.
- **Raycast extension scaffold** under `extensions/raycast/` (experimental),
  built on the CLI's `list --json` / `kill`.
- CLI `list` now shows a PROTO column.
- Internals: kill verification is event-driven (DispatchSourceProcess), the
  two largest files were split per-responsibility, CI actions bumped and a UI
  render smoke test added to every CI run.

## 1.4.0 — 2026-08-07

The "big batch" release.

### Added
- **Watched section**: starred ports pinned to the top of the list with live status — including "free ✓", the answer you usually came for.
- **Kill & notify**: when a kill doesn't finish (slow shutdown, trapped SIGTERM), PortKilla notifies you the moment the port actually frees.
- **UDP ports**: bound UDP sockets now appear with a purple UDP tag (ephemeral/outgoing sockets are filtered out).
- **Process age & CPU%**: shown in row tooltips and the detail sheet; Test Radar rows show live CPU to expose runaway watchers.
- **Open Project in Editor**: detects VS Code, Cursor, Zed, Sublime Text, and Trae; opens the process's real working directory.
- **Free-port answer**: searching a port number that's free shows ":8080 is free ✓ — Watch it" instead of a dead-end empty state; if it's occupied but hidden by a filter, it says so.
- **Configurable global hotkey**: gear menu → Change Hotkey (default ⌥⌘P).
- Keyboard navigation (↑↓ ⏎) now also works on the Tests filter.
- Accessibility labels on all icon-only buttons.

## 1.3.0 — 2026-08-07

- Port watchlist with "freed"/"taken" notifications.
- Real project detection from process working directories, with Reveal in Finder / Open in Terminal.
- CLI mode: `portkilla list [--json]`, `portkilla kill <port> [--force]`.
- URL scheme: `portkilla://kill/3000`, `portkilla://show`.
- Update check against GitHub Releases (gear menu).
- First-run popover + hotkey tip; generated app icon; History gained "Kill again".
- Homebrew cask template under `packaging/homebrew/`.

## 1.2.0 — 2026-08-07

- Keyboard-first flow: ⌥⌘P global hotkey, search-focused popover, ↑↓ selection, ⏎ kill, ⌘⏎ force, ⌘O open in browser.
- Filter chips (All/Dev/Databases/Docker/Tests) replace tabs; settings moved to a gear menu.
- Hide System Processes filter (default on) and dev-only menu-bar count.
- "Exposed" badge for ports bound to all interfaces (0.0.0.0/::).
- Safety: PID-identity re-check before kills, `pid > 0` guard, no silent SIGTERM→SIGKILL escalation.
- Performance: one `ps` snapshot per refresh instead of 3 subprocesses per port; hard timeouts on all subprocess calls; background refresh slows to 30s while the popover is closed.
- Fixes: Docker on Apple Silicon Homebrew paths, IPv6 container port parsing, CSV injection escaping, locale-formatted port numbers, false "Refresh failed" with zero ports.

## 1.1.0

- Process tree with Smart Kill (kill tree), Docker container names, Test Radar (beta).

## 1.0.x

- Initial releases: port list, one-click kill, history + CSV export, protected processes, bulk kill.
