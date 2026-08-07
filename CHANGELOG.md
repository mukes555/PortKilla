# Changelog

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
