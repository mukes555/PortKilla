# PortKilla Architecture

A tour of how the app is put together, for anyone touching the code.

## 10,000-ft view: one binary, two front-ends

`AppDelegate` is the `@main` entry point, but before the GUI launches,
[`CLI.swift`](PortKilla/Sources/PortKilla/App/CLI.swift) inspects `argv`: if the
first argument is a known subcommand (`list`, `kill`, `version`), it runs the CLI
and exits. Otherwise the menu-bar app starts. So `PortKilla` and
`portkilla list` are the same executable.

```
                         ┌───────────────────────────┐
   libproc syscalls ───► │ NativeScanner  (fast path)│
   (no subprocesses)     └────────────┬──────────────┘
                                      │ falls back to
   /usr/sbin/lsof, /bin/ps ─────────► │
                         ┌────────────▼──────────────┐
                         │ PortScanner / ProcessTable │  enrich: cmd, mem,
                         │  (+ DockerService)         │  cwd, container, cpu
                         └────────────┬──────────────┘
                                      │ [PortInfo]
                         ┌────────────▼──────────────┐
                         │ PortManager (Observable)   │  the hub the UI binds to
                         │  ports, watch/guard, kills │
                         └────────────┬──────────────┘
                                      │ @Published
                         ┌────────────▼──────────────┐
                         │ SwiftUI views (PortListView)│
                         └────────────────────────────┘
```

## The scan pipeline (the heart of the app)

Every refresh takes **one** snapshot and shares it, rather than shelling out
per port:

1. **`ProcessTable.capture()`** — one process snapshot for the whole refresh.
   It calls **`NativeScanner`** first.
2. **`NativeScanner`** ([Services/NativeScanner.swift](PortKilla/Sources/PortKilla/Services/NativeScanner.swift))
   walks the pid list once for both the process table and the listening
   sockets (`NativeScanner+Sockets.swift`). Facts that cannot change after
   exec (path, argv, env markers) come from `ProcessFacts`, a per-(pid, start
   time) cache, so steady-state refreshes skip most syscalls.
   — raw `libproc`/`proc_info` syscalls via the **`CLibProc`** C target. Lists
   PIDs, sockets, memory, CPU, working directories, and command lines with **no
   subprocesses** (~19 ms for ~480 processes). This is the fast path.
3. **`PortScanner`** ([Services/PortScanner.swift](PortKilla/Sources/PortKilla/Services/PortScanner.swift))
   — asks `NativeScanner` for listeners; if that returns empty (e.g. sandbox or
   an unexpected OS), it **falls back to `/usr/sbin/lsof`** and parses its text
   output. Both paths converge on the same `[PortInfo]`.
4. **`DockerService`** decorates ports that map to running containers.
5. **`AgentAttribution`** ([Services/AgentAttribution.swift](PortKilla/Sources/PortKilla/Services/AgentAttribution.swift))
   names the AI agent that spawned each listener: process ancestry first, then
   the allowlisted environment markers agents leave on children (read from the
   same `KERN_PROCARGS2` buffer as the command line). `KillDecision` turns
   the caller's and the target's owners into allow / warn / refuse; every kill
   path (CLI, GUI, bulk, link, port guard) asks it.

> The native-fast-path-with-lsof-fallback is the single most surprising design
> decision. If you touch scanning, keep both paths producing equivalent results
> — the parsing tests (`ScannerParsingTests`, `NativeScannerTests`) guard this.

All subprocess calls (lsof/ps/pgrep/docker) go through
[`CommandRunner`](PortKilla/Sources/PortKilla/Services/CommandRunner.swift),
which enforces a hard timeout and safe pipe handling.

## `PortManager` — the hub

[Services/PortManager.swift](PortKilla/Sources/PortKilla/Services/PortManager.swift)
(+ `PortManagerKills.swift`, `PortManager+WatchGuard.swift`) is the
`ObservableObject` the entire UI binds to. It owns:

- the refresh timer (fast while the popover/pinned window is open, slow in the
  background) and `activePorts` / `activeTests`;
- the **watchlist** and **port guards** (auto-kill a guarded port's new
  occupant) — see `PortManager+WatchGuard.swift`;
- **kill orchestration** (`PortManagerKills.swift`): signal off the main thread
  → event-driven `waitForExit` (`DispatchSourceProcess`) → report on main;
- settings persistence and update checks.

Kills go through [`ProcessKiller`](PortKilla/Sources/PortKilla/Services/ProcessKiller.swift),
which verifies process identity before signalling (PID reuse protection) and
never silently escalates SIGTERM → SIGKILL.

## Directory map

```
PortKilla/Sources/
  CLibProc/            C shim exposing Darwin libproc/proc_info to Swift
  PortKilla/
    App/               AppDelegate (@main), CLI, DemoReel (dev-only)
    Models/            PortInfo, TestProcessInfo, PortHistory
    Services/          Scanning, killing, Docker, hotkey, login item,
                       notifications, update check, formatting
    Views/             SwiftUI — PortListView is the root; +Actions / +Chrome
                       are its extensions; PortRowViews, SettingsView, etc.
```

## Notes for contributors

- **macOS-only.** AppKit + SwiftUI + Darwin syscalls. No cross-platform path.
- **Zero third-party dependencies.**
- **The package is in a nested dir** (`PortKilla/PortKilla/`) — see
  [CONTRIBUTING.md](CONTRIBUTING.md).
- **Dev-only hooks** (`PORTKILLA_SNAPSHOT`, `PORTKILLA_DEMO_GIF`) are compiled
  only in debug builds and documented in CONTRIBUTING.md.
- Pure, testable logic is deliberately factored into `static` functions
  (`watchEvents`, `parsePortMap`, `namesMatch`, `stableSignature`, …) so the
  test suite can cover it without a running app.
