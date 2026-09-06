# PortKilla Architecture

A tour of how the app is put together, for anyone touching the code.

## 10,000-ft view: one core, three front-ends

Everything that knows about ports lives in the **`PortKillaCore`** library
(Foundation only, no AppKit): the models, the scanners, the kill path, the
agent guard, the CLI commands and the MCP server. Three executables sit on
top of it:

- **`PortKilla`**, the menu-bar app. `AppDelegate` is the `@main` entry point,
  but before the GUI launches it hands `argv` to
  [`PortKillaCLI`](PortKilla/Sources/PortKillaCore/CLI/CLI.swift): a known
  subcommand runs and exits, anything else starts the app.
- **`portkilla`** ([Sources/portkilla-cli](PortKilla/Sources/portkilla-cli/main.swift),
  one file): the same commands without AppKit, so `portkilla list` from a
  script or an agent starts in a few milliseconds. `scripts/build.sh` copies
  it into the bundle as `Contents/MacOS/portkilla`, which is what Homebrew
  links onto PATH.
- **`PortKillaTests`** links both, so the suite can drive the core directly
  and spawn the debug `portkilla` as a real process.

Subcommands: `list`, `kill`, `free`, `free-port`, `wait`, `open`, `history`,
`whoami`, `doctor`, `schema`, `agent-docs`, `mcp`, `completions`, `version`,
`help`.

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

1. **`ProcessTable.capture()`**: one process snapshot for the whole refresh.
   It calls **`NativeScanner`** first.
2. **`NativeScanner`** ([Services/NativeScanner.swift](PortKilla/Sources/PortKillaCore/Services/NativeScanner.swift))
   walks the pid list once for both the process table and the listening
   sockets (`NativeScanner+Sockets.swift`, which also counts the established
   connections behind each listener). Facts that cannot change after exec
   (path, argv, env markers) come from `ProcessFacts`, a per-(pid, start
   time) cache, so steady-state refreshes skip most syscalls. Everything is
   raw `libproc`/`proc_info` syscalls via the **`CLibProc`** C target: PIDs,
   sockets, memory, CPU, working directories, and command lines with **no
   subprocesses** (~19 ms for ~480 processes). This is the fast path.
3. **`PortScanner`** ([Services/PortScanner.swift](PortKilla/Sources/PortKillaCore/Services/PortScanner.swift))
   asks `NativeScanner` for listeners; if that returns empty (e.g. sandbox or
   an unexpected OS), it **falls back to `/usr/sbin/lsof`** and parses its text
   output. Both paths converge on the same `[PortInfo]`. Command lines pass
   through `CommandRedaction` on the way (`--token=...`, `KEY=...`, URL
   passwords, bearer tokens), so nothing PortKilla shows, exports, or hands
   to an agent carries a secret.
4. **`DockerService`** decorates ports that map to running containers.
5. **`AgentAttribution`** ([Services/AgentAttribution.swift](PortKilla/Sources/PortKillaCore/Services/AgentAttribution.swift))
   names the AI agent that spawned each listener: a declared
   `PORTKILLA_OWNER` first, then process ancestry, then the allowlisted
   environment markers agents leave on children (read from the same
   `KERN_PROCARGS2` buffer as the command line). `KillDecision` turns the
   caller's and the target's owners into allow / warn / refuse; every kill
   path (CLI, GUI, bulk, link, port guard, MCP) asks it. Agents are refused
   other agents' running sessions and servers nobody claims; people are
   warned, never refused.

> The native-fast-path-with-lsof-fallback is the single most surprising design
> decision. If you touch scanning, keep both paths producing equivalent
> results: the parsing tests (`ScannerParsingTests`, `NativeScannerTests`)
> guard this.

All subprocess calls (lsof/ps/pgrep/docker) go through
[`CommandRunner`](PortKilla/Sources/PortKillaCore/Services/CommandRunner.swift),
which enforces a hard timeout and safe pipe handling.

## `PortManager`, the hub

[Services/PortManager.swift](PortKilla/Sources/PortKillaCore/Services/PortManager.swift)
(+ `PortManagerKills.swift`, `PortManager+WatchGuard.swift`) is the
`ObservableObject` the entire UI binds to. It owns:

- the refresh timer (fast while the popover/pinned window is open, slow in the
  background) and `activePorts` / `activeTests`;
- the **watchlist** and **port guards** (auto-kill a guarded port's new
  occupant), see `PortManager+WatchGuard.swift`;
- **kill orchestration** (`PortManagerKills.swift`): signal off the main thread,
  then event-driven `waitForExit` (`DispatchSourceProcess`), then report on main;
- settings persistence and update checks.

Kills go through [`ProcessKiller`](PortKilla/Sources/PortKillaCore/Services/ProcessKiller.swift),
which verifies process identity before signalling (PID reuse protection) and
never silently escalates SIGTERM to SIGKILL.

## Directory map

```
PortKilla/Sources/
  CLibProc/            C shim exposing Darwin libproc/proc_info to Swift
  PortKillaCore/       The library: Foundation, OSLog, ServiceManagement,
                       UserNotifications; no AppKit
    Models/            PortInfo, TestProcessInfo, PortHistory, DefaultsKey
    Services/          Scanning, attribution, KillDecision, killing, Docker,
                       redaction, login item, notifications, update check
    CLI/               Argument parsing, commands, output schemas, MCP server,
                       and the debug-only `__serve` test server
  PortKilla/           The menu-bar app
    App/               AppDelegate (@main), DemoReel (dev-only)
    Services/          GlobalHotKey
    Views/             SwiftUI; PortListView is the root, +Actions / +Chrome
                       are its extensions; PortRowViews, SettingsView, etc.
  portkilla-cli/       main.swift, the standalone CLI
PortKilla/Tests/PortKillaTests/
                       Unit tests, plus ScenarioTests which spawn real servers
                       and drive the guard through the CLI as a process
```

## Notes for contributors

- **macOS-only.** AppKit + SwiftUI + Darwin syscalls. No cross-platform path.
- **Zero third-party dependencies.**
- **The package is in a nested dir** (`PortKilla/PortKilla/`), see
  [CONTRIBUTING.md](CONTRIBUTING.md).
- **`PortKillaCore` must not import AppKit.** Colors and other UI-only
  extensions of the models live in the app target (`Views/ModelColors.swift`).
- **Dev-only hooks** (`PORTKILLA_SNAPSHOT`, `PORTKILLA_DEMO_GIF`,
  `portkilla __serve <port>`) are compiled only in debug builds and documented
  in CONTRIBUTING.md.
- Pure, testable logic is deliberately factored into `static` functions
  (`watchEvents`, `parsePortMap`, `namesMatch`, `stableSignature`, ...) so the
  test suite can cover it without a running app.
