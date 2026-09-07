# PortNanny Architecture

A tour of how the app is put together, for anyone touching the code.

## 10,000-ft view: one core, three front-ends

Everything that knows about ports lives in the **`PortNannyCore`** library
(Foundation only, no AppKit): the models, the scanners, the kill path, the
agent guard, the CLI commands and the MCP server. Three executables sit on
top of it:

- **`PortNanny`**, the menu-bar app. `AppDelegate` is the `@main` entry point,
  but before the GUI launches it hands `argv` to
  [`PortNannyCLI`](PortNanny/Sources/PortNannyCore/CLI/CLI.swift): a known
  subcommand runs and exits, anything else starts the app.
- **`portnanny-cli`** ([Sources/portnanny-cli](PortNanny/Sources/portnanny-cli/main.swift),
  one file): the same commands without AppKit, so `portnanny list` from a
  script or an agent starts in a few milliseconds. `scripts/build.sh` copies
  it into the bundle as `Contents/Helpers/portnanny`, which is what Homebrew
  links onto PATH. (The product is not called `portnanny` because on a
  case-insensitive volume that is the same file as the app's `PortNanny`.)
- **`PortNannyTests`** links both, so the suite can drive the core directly
  and spawn the debug `portnanny` as a real process.

Subcommands: `list`, `kill`, `free`, `wait`, `open`, `history`, `whois`,
`whoami`, `reserve`, `release`, `reservations`, `exec`, `drift`, `free-port`,
`schema`, `doctor`, `setup`, `agent-docs`, `mcp`, `completions`, `version`,
`help` (the list in `CLICompletions.commands` is the source of truth), plus
`__serve` in debug builds for the scenario tests.

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
2. **`NativeScanner`** ([Services/NativeScanner.swift](PortNanny/Sources/PortNannyCore/Services/NativeScanner.swift))
   walks the pid list once for both the process table and the listening
   sockets (`NativeScanner+Sockets.swift`, which also counts the established
   connections behind each listener). Facts that cannot change after exec
   (path, argv, env markers) come from `ProcessFacts`, a per-(pid, start
   time) cache, so steady-state refreshes skip most syscalls. Everything is
   raw `libproc`/`proc_info` syscalls via the **`CLibProc`** C target: PIDs,
   sockets, memory, CPU, working directories, and command lines with **no
   subprocesses** (~19 ms for ~480 processes). This is the fast path.
3. **`PortScanner`** ([Services/PortScanner.swift](PortNanny/Sources/PortNannyCore/Services/PortScanner.swift))
   asks `NativeScanner` for listeners; if that returns empty (e.g. sandbox or
   an unexpected OS), it **falls back to `/usr/sbin/lsof`** and parses its text
   output. Both paths converge on the same `[PortInfo]`. Command lines pass
   through `CommandRedaction` on the way (`--token=...`, `KEY=...`, URL
   passwords, bearer tokens), so nothing PortNanny shows, exports, or hands
   to an agent carries a secret.
4. **`DockerService`** decorates ports that map to running containers.
5. **`ManagedRuntime`** ([Services/ManagedRuntime.swift](PortNanny/Sources/PortNannyCore/Services/ManagedRuntime.swift))
   names the supervisor that would undo a plain kill (a Docker container,
   the outermost pm2 or launchd job, the nearest reloader) and the verb that
   stops it for real. Every kill path plans around it: the CLI in
   `CLIKill+Managed.swift`, the app in `PortManager+Managed.swift`.
6. **`AgentAttribution`** ([Services/AgentAttribution.swift](PortNanny/Sources/PortNannyCore/Services/AgentAttribution.swift))
   names the AI agent that spawned each listener: a declared
   `PORTNANNY_OWNER` first, then process ancestry, then the allowlisted
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
[`CommandRunner`](PortNanny/Sources/PortNannyCore/Services/CommandRunner.swift),
which enforces a hard timeout and safe pipe handling.

## `PortManager`, the hub

[Services/PortManager.swift](PortNanny/Sources/PortNannyCore/Services/PortManager.swift)
(+ `PortManagerKills.swift`, `PortManager+WatchGuard.swift`) is the
`ObservableObject` the entire UI binds to. It owns:

- the refresh timer (fast while the popover/pinned window is open, slow in the
  background) and `activePorts` / `activeTests`;
- the **watchlist** and **port guards** (auto-kill a guarded port's new
  occupant), see `PortManager+WatchGuard.swift`;
- **kill orchestration** (`PortManagerKills.swift`): signal off the main thread,
  then event-driven `waitForExit` (`DispatchSourceProcess`), then report on main;
- settings persistence and update checks;
- `MetricsHistory`, one CPU and memory sample per process per scan, which
  only the sparkline views observe.

`ReservationStore` keeps port leases in the shared preference domain, so
the CLI and the app agree on who has claimed which free port.

Kills go through [`ProcessKiller`](PortNanny/Sources/PortNannyCore/Services/ProcessKiller.swift),
which verifies process identity before signalling (PID reuse protection) and
never silently escalates SIGTERM to SIGKILL.

## Directory map

```
PortNanny/Sources/
  CLibProc/            C shim exposing Darwin libproc/proc_info to Swift
  PortNannyCore/       The library: Foundation, OSLog, ServiceManagement,
                       UserNotifications; no AppKit
    Models/            PortInfo, TestProcessInfo, PortHistory, DefaultsKey
    Services/          Scanning, attribution, KillDecision, killing, Docker,
                       redaction, login item, notifications, update check
    CLI/               Argument parsing, commands (kill, whois, reserve, exec,
                       setup, ...), output schemas, MCP server, the rule-file
                       installer, and the debug-only `__serve` test server
  PortNanny/           The menu-bar app
    App/               AppDelegate (@main), RefusalWatcher (CLI refusals
                       become actionable notifications), DemoReel (dev-only)
    Services/          GlobalHotKey
    Views/             SwiftUI; PortListView is the root, +Actions / +Chrome /
                       +Palette are its extensions; KillFlow holds the
                       confirmations every window shares; PaletteQuery parses
                       the search field's verbs; TourView, MascotView,
                       SparklineView
    Workbench/         The full-size window: sidebar, table, projects, agent
                       sessions, watchlist, inspector (WorkbenchModel groups)
  portnanny-cli/       main.swift, the standalone CLI
PortNanny/Tests/PortNannyTests/
                       Unit tests, plus ScenarioTests which spawn real servers
                       and drive the guard through the CLI as a process
```

## Notes for contributors

- **macOS-only.** AppKit + SwiftUI + Darwin syscalls. No cross-platform path.
- **Zero third-party dependencies.**
- **The package is in a nested dir** (`PortNanny/PortNanny/`), see
  [CONTRIBUTING.md](CONTRIBUTING.md).
- **`PortNannyCore` must not import AppKit.** Colors and other UI-only
  extensions of the models live in the app target (`Views/ModelColors.swift`).
- **Dev-only hooks** (`PORTNANNY_SNAPSHOT`, `PORTNANNY_DEMO_GIF`,
  `portnanny __serve <port>`) are compiled only in debug builds and documented
  in CONTRIBUTING.md.
- Pure, testable logic is deliberately factored into `static` functions
  (`watchEvents`, `parsePortMap`, `namesMatch`, `stableSignature`, ...) so the
  test suite can cover it without a running app.
