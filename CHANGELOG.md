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

### Changed
- Row text uses relative text styles (`body`, `subheadline`, `caption`)
  instead of fixed point sizes, and the column widths are `ScaledMetric`,
  so the list follows whatever text scaling the system applies rather than
  clipping. macOS applies little of it to SwiftUI text today; the snapshot
  hook's `PORTKILLA_SNAPSHOT_TEXTSIZE=large` exists for when it does.
- Rows no longer observe the whole `PortManager`: the section hands each
  row plain values (density, protected, watched, terminating), so a
  publish re-evaluates only the rows whose inputs changed.
- The demo-GIF hook renders against a throwaway preference suite instead
  of the real one.

### Added
- `portkilla mcp` announces itself on stderr when run from a terminal
  (it used to wait in silence), and `portkilla mcp --setup [claude|cursor|
  codex]` prints the registration for each agent. There is no background
  mode by design: each agent starts its own copy over stdin/stdout when it
  needs one and stops it afterwards.

### Distribution
- The release workflow can pin the Homebrew cask to each release with its
  SHA-256 (`packaging/homebrew/portkilla.rb.tmpl`, `livecheck`,
  `brew upgrade` support). It runs only when a `HOMEBREW_TAP_TOKEN` secret
  exists; see RELEASING.md.
- README leads with a current screenshot; the demo GIF is regenerated.

## 1.16.0 — 2026-09-06

### The agent tools batch

### Added
- **`portkilla mcp`**: a Model Context Protocol server over stdin/stdout,
  no dependencies. Tools: `list_ports`, `kill_port` (dry-run by default,
  refusals come back as tool errors the model reads), `whoami`,
  `wait_for_port_free`. The agent spawns and reaps it, so nothing is
  resident or registered: the guard becomes a tool instead of a habit.
  Register with `{"mcpServers":{"portkilla":{"command":"portkilla","args":["mcp"]}}}`
  (Claude Code, Cursor) or `[mcp_servers.portkilla]` in Codex's config.
- **`portkilla agent-docs --write [--file CLAUDE.md]`** appends the agent
  snippet between markers, once, and updates it in place on later runs.
  Opt-in only; no other command writes into your repository.
- **`portkilla agent-docs --claude-hook`** prints a Claude Code PreToolUse
  hook that turns `kill -9 $(lsof -ti:PORT)` into a nudge toward
  `portkilla free`, at the point of the habit.

## 1.15.0 — 2026-09-06

### The distribution batch

### Added
- `portkilla doctor` (and Settings → About → **Copy debug info**): version,
  macOS, architecture, install source, quarantine state, scanner path and
  timing, PATH resolution, login item status. Paste it into bug reports.
- `portkilla <command> --help` and `portkilla help <command>`;
  `portkilla completions zsh|bash|fish`; `version --json`.
- Structured logging into the unified log (`log stream --predicate
  'subsystem == "com.mukes555.PortKilla"'`) for the scan path, kills, guard
  events, and update checks. Process names are marked private.
- VoiceOver reads each port row as one labelled element ("Port 3000, node,
  45 MB, owned by Claude Code, exposed on all interfaces") and announces
  the keyboard selection.
- `docs/FIRST-RUN.md`: the one page for Gatekeeper on macOS 13/14 versus
  15+, Homebrew, login-item re-approval, and uninstall. README badges and
  an FAQ.

### Changed
- **Updates know where you installed from.** A Homebrew install is offered
  the `brew reinstall` command instead of a DMG that would overwrite the
  cask's bundle. A GitHub rate limit is explained as such. Development
  builds no longer show a dead Check for Updates button. Pre-release tags
  are never offered as updates.
- Settings shows when macOS is waiting for you to re-approve the login item
  (common after an update) with a button to Login Items.
- `list` and `history` omit their header when piped; a JSON encoding
  failure exits 70 instead of 0 with no output.

### Distribution
- The release workflow refuses to run unless the tag, `build.sh`, and the
  newest CHANGELOG section agree; CI checks the same on every PR.
- The release verifies the binary is universal and signed and that
  Info.plist carries the tag's version, publishes `SHA256SUMS`, and marks
  `-rc`/`-beta`/`-alpha` tags as pre-releases.
- CI caches the SwiftPM build and runs the suite once through Rosetta, so
  the x86_64 slice has executed at least once (advisory).
- The Homebrew cask quits the running app and drops its login item before
  replacing the bundle, and `zap` removes saved state, caches, and HTTP
  storage as well as preferences.
- `CFBundleVersion` follows the release version (it was always 1); the
  bundle declares the Developer Tools category.

## 1.14.0 — 2026-09-06

### The guard batch

Closes the holes a fresh audit found in the friendly-fire guard.

### Changed
- **Session identity uses `CLAUDE_CODE_SESSION_ID`** where Claude Code
  provides it: a UUID is never recycled the way a pid is and survives a
  restart in place. Pids remain the fallback.
- A session pid reused by a *different* agent is no longer trusted.
- **Markerless sessions expire.** Owners detected from a marker with no
  session (Cursor, Gemini, Codex, older Claude Code) used to block other
  agents forever. If no process of that agent is running at all, the
  session is reported as ended.
- **tmux, screen, zellij, and ssh are attribution barriers.** Markers seen
  through a multiplexer belong to whoever started it, not the pane, so the
  name is kept and the session dropped; the tree walk stops there.
- `list --mine` means exactly what `kill` would allow without `--force`,
  and says so on stderr (exit 1) when the caller isn't identified.
- The `kill` report gains `guardVerdict` ("refused", "allowed",
  "overridden", "not-evaluated: caller unknown", "not-evaluated: target
  unknown"), and an unidentified caller killing an agent's live server is
  told on stderr that the guard could not apply.
- Refusals suggest the next step (ask the user, or use a free port).

### Added
- **`portkilla free <port>`**: kill for scripts; exit 0 when the port was
  already free, so `portkilla free 3000 && npm run dev` works under `set -e`.
- **`portkilla wait <port> [--timeout 30]`** blocks until the port is free.
- **`portkilla open <port>`** opens localhost in the browser.
- **`portkilla history [--port N] [--json]`**: the CLI now records its kills
  in the same store as the app, so the History window shows agent kills and
  an agent can find out who stopped its server.
- `agent-docs` covers `--dry-run`, `--pid`, stderr, same-tool sessions,
  `free`, `wait`, `history`, and `PORTKILLA_OWNER` for tools without markers.

## 1.13.1 — 2026-09-06

### Fixed
- **Running the test suite changed the developer's real preferences** (it
  once switched off "Hide system processes" and rewrote the watched ports).
  `PortManager` now takes an injected `UserDefaults` and `HistoryManager`,
  and every test uses a throwaway suite.
- Opening the popover while a hidden-state scan was running could show rows
  without chips, containers, or trees for one cycle. The full scan the
  popover asked for now runs instead of being dropped.
- The port guard looked up agent ownership by port number, so a port shared
  by a TCP listener and a UDP binder could be judged by the wrong process.
- An editor-terminal ancestor used to hide a stronger `CLAUDECODE` marker in
  the server's own environment, silently losing protection.
- The per-process facts cache survived `exec` without `fork` (`sh -c 'exec
  node …'`), so a row could keep showing `sh`. The kernel's short name is
  now part of the cache key, and an empty marker read is retried.
- Subprocess output: the pipe could be closed under a read in flight, and
  truncated `lsof` output was parsed as complete. Reads and the close now
  share one lock, and end-of-file is required.
- The CLI reported an unreaped zombie as "still running" after the full
  wait; `--force` erased the refusal reasons from the JSON report (now kept
  as `overriddenRefusals`); ports outside 1 to 65535 and `port` plus `--pid`
  together are usage errors.
- Pinned window shortcuts stopped working whenever no window was key.
- The Guard switch in Settings ran a modal dialog inside SwiftUI's update.
- Hardening: `PORTKILLA_OWNER` control characters are stripped, chip label
  colours are computed once per tint, the socket size re-probe keeps what it
  already read, a Docker restart is picked up immediately, the working
  directory lock is no longer held across the `lsof` subprocess, and
  concurrent scans no longer zero each other's CPU deltas.

### Security
- SECURITY.md now states the threat model: the friendly-fire guard is a
  cooperation protocol between well-behaved agents, not a security boundary.

## 1.13.0 — 2026-09-06

### The engineering batch

No user-visible feature changes; this release is for the people who read the
code. The one behaviour change: the CSV export gains Owner and Killed By
columns, and Reset All Settings also brings the tips banner back.

### Changed
- `PortManager` (762 lines) is split into its core, `PortManager+WatchGuard`
  (watchlist and guards) and `PortManager+Refresh` (scheduling and the scan
  pipeline); the row view's context menu and child row are their own files.
- One `KnownEditors` list drives both "IDE & Tools" classification and the
  default protected list, with a test that they agree. They had drifted.
- Every UserDefaults key lives in `DefaultsKey`; the `portkilla://` scheme is
  parsed by `URLCommand`; key codes are named (`KeyCode.escape`) instead of
  numbered.
- Port classification is a table of rules in priority order instead of a
  ten-branch if-ladder.
- The scanner's working-directory cache is lock-guarded, so link-initiated
  kills reuse the shared scanner instead of allocating a cold one.
- `HistoryManager` is observable (the History window updates while open) and
  takes an injectable `UserDefaults`, so tests never touch real history.
- Removed dead code: two unused view bindings, an unreachable history state,
  `killAllPorts(ofType:)`, and comments that restated their signatures.
- Docs: ARCHITECTURE lists the real CLI commands; README no longer says "TCP
  only", describes Kill All Dev's true scope, and points Check for Updates at
  Settings → About.

### Tests
- The exit wait (killed, surviving, already dead, deadline), the guard's
  four refusal rules, URL scheme parsing, editor/protected agreement,
  classification order, history cap and persistence, the CSV document, and
  several pure helpers. 139 tests.

## 1.12.0 — 2026-09-06

### The UI batch

### Added
- **States the app had no words for:** a "Scanning ports…" state before the
  first scan (it used to claim "No active ports" with a green check before
  any data existed), a "compatibility scan" note in the footer when the slow
  lsof path is in use, a "Notifications are blocked" row in Settings with a
  button to System Settings, rows that dim with a spinner while a process
  shuts down, and a "Refreshing…" toast when you press refresh mid-scan.
- **Guards are reachable:** "Guard :port" in every row's context menu, and a
  Watched ports section in Settings with guard switches and unwatch buttons.
  Previously the only guard toggle lived in a section that disappeared on
  any search or filter.
- Shortcuts pane documents Option-click, Shift-click, right-click, and ⌘C,
  and can bring the tips banner back.
- Settings: notification sound toggle and history retention (50 to 500).

### Changed
- **Watched rows** now use the same columns, padding, chips, and context
  menu as the rest of the list instead of a second, narrower layout.
- **Pinned window:** keyboard shortcuts work in it (each copy of the list
  answers only while its own window is key), it is resizable, and it
  remembers its position and display.
- **⌘K and the footer button honour the active filter:** "Kill All
  Databases" on the Databases tab, "Kill All Docker" on Docker. The All tab
  keeps the classic "Kill All Dev".
- Killing the selected row keeps the keyboard position on its neighbour
  instead of jumping to the top.
- One confirmation dialog style everywhere, with a properly destructive Kill
  button (five different idioms before).
- Chips share one component, use system colours that adapt to the
  appearance, and darken their label in light mode where the old ones
  failed contrast.
- The density toggle respects Reduce Motion.

### Removed (internal)
- Two unreachable sheet cases and the protected list's never-shown
  standalone mode.

## 1.11.0 — 2026-09-06

### The performance batch

Same features, a fraction of the work. Measured on a machine with ~600
processes and ~60 listeners, a refresh went from roughly 5,100 syscalls and
30,000 short-lived strings to about 1,400 syscalls and a few hundred strings.

### Changed
- **One native pass.** The process table and the listening sockets are
  gathered in a single walk over the pid list (two before), with a reusable
  descriptor buffer instead of a size probe per process.
- **Facts that can't change aren't re-read.** Executable path, argv, and the
  environment markers are cached per (pid, start time), so a refresh only
  pays for processes it hasn't seen. A recycled pid gets a fresh entry.
- **No render storm.** An unread published flag and an always-changing
  timestamp forced three whole-tree re-renders per refresh even when nothing
  changed. The flag is plain, the timestamp lives on its own object that
  only the footer observes, the visible-port filter is cached instead of
  recomputed thousands of times a minute, and the Tests list republishes on
  structural change (or every 10s for the CPU column).
- **Docker off the hot path.** `docker ps` runs on a background queue, only
  when a Docker process is listening, and backs off (5s to 60s) when the
  daemon is down, instead of blocking every refresh for up to three seconds.
- **Hidden means light.** With nothing on screen a refresh gathers the six
  fields the badge and watchlist need; working directories, Docker names,
  children, and agent attribution wait for the popover. Closing the popover
  no longer triggers a scan nobody sees.
- **Quiet launch.** No notification-permission prompt just for launching
  (it is asked when you turn notifications on or arm a watch), no
  preferences written back to disk on read, and the update check is
  deferred ten seconds.
- The menu-bar icon is drawn from two cached images and only when its state
  changes; `lsof` is no longer asked for working directories of other
  users' processes (it can't read them either).
- `portkilla whoami` walks its own ancestor chain instead of snapshotting
  every process; `kill` skips the Docker lookup it doesn't print.

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
