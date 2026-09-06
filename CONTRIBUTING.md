# Contributing to PortKilla

Thanks for your interest! PortKilla is a small, dependency-free, native macOS
menu-bar app (with a built-in CLI). This guide gets you from clone to running in
about a minute, and explains how the project is organized.

> New to the codebase? Read [ARCHITECTURE.md](ARCHITECTURE.md) first — it maps
> the module layout and the scan pipeline.

## Prerequisites

- **macOS 13 (Ventura) or newer.** This is a macOS-only AppKit/SwiftUI app; it
  will not build or run on Linux or Windows.
- A Swift toolchain. CI builds with **Swift 6.0.2**; `Package.swift` declares a
  `5.9` minimum. Anything in that range should work.
- **No third-party dependencies.** There are zero external Swift packages — just
  the standard library, AppKit/SwiftUI, and a thin C shim (`CLibProc`) over
  Darwin's `libproc`.

## The one gotcha: the package lives in a nested directory

The Git repo is named `PortKilla` and the Swift package sits in a `PortKilla/`
subdirectory of it. After cloning you have to step in twice:

```bash
git clone https://github.com/mukes555/PortKilla.git
cd PortKilla/PortKilla        # repo root → Swift package root
```

Every `swift` command below is run from that package root.

## Run it (clone → running GUI in ~60s)

```bash
swift build
swift run PortKilla            # launches the menu-bar app (look for the ⚡ icon)
```

The same binary is also a CLI — handy during development:

```bash
swift run PortKilla list          # table of listening ports
swift run PortKilla list --json   # JSON, for scripting
swift run PortKilla kill 3000     # graceful kill; add --force for SIGKILL
```

## Test

```bash
swift test --disable-sandbox
```

`--disable-sandbox` is required: several tests exercise the native scanner,
which makes raw `libproc` syscalls the SwiftPM sandbox blocks.

## Build a distributable app

```bash
./scripts/build.sh            # → dist/PortKilla.app (ad-hoc signed)
./scripts/build.sh --dmg      # also produces dist/PortKilla-<version>.dmg
./scripts/build.sh --bundle-id=com.you.PortKilla   # override the bundle id
```

The app is **ad-hoc signed** (no Apple Developer account), so Gatekeeper will
warn on first open — right-click → Open, or
`xattr -dr com.apple.quarantine dist/PortKilla.app`.

## Developer hooks (env vars)

The app renders its own UI offscreen for screenshots and the README GIF — no
screen-recording permission needed. CI uses the first one as a smoke test.

| Env var | Effect |
|---|---|
| `PORTKILLA_SNAPSHOT=/path.png` | Render a view offscreen to PNG, then quit |
| `PORTKILLA_SNAPSHOT_VIEW=main\|bulkkill\|protected\|detail\|settings` | Which view to render (default `main`) |
| `PORTKILLA_SNAPSHOT_DENSITY=clean\|advanced` | Seed the row density |
| `PORTKILLA_SNAPSHOT_WATCH=3000,9999` | Seed watched ports |
| `PORTKILLA_SNAPSHOT_APPEARANCE=light\|dark` | Force appearance |
| `PORTKILLA_SHOW_ON_LAUNCH=1` | Auto-open the popover on launch |
| `PORTKILLA_DEMO_GIF=/path.gif` | Render the scripted demo reel (fabricated data) to an animated GIF, then quit |

Regenerate the README assets:

```bash
# main-view screenshot
PORTKILLA_SNAPSHOT=../assets/screenshot.png .build/debug/PortKilla
# animated demo
PORTKILLA_DEMO_GIF=../assets/demo.gif .build/debug/PortKilla
```

## Coding style

The project favors code written **for human brains**: early returns over nested
`if`s, complex conditions extracted into named booleans, deep modules with
simple interfaces, and files small enough to hold in your head (aim ~300 lines, split at ~500,
split by responsibility well before 1000). Comments explain **why**, not what.
Match the surrounding style.

## Submitting a pull request

1. Branch from `main` — **never push directly to `main`/`master`** (CI gates it).
2. Keep the change focused; one concern per PR.
3. `swift test --disable-sandbox` must pass, and the build must stay green.
4. Add an entry to [CHANGELOG.md](CHANGELOG.md) under an "Unreleased" heading.
5. Open the PR; CI runs `scripts/build.sh`, the test suite, and a UI-render
   smoke test on `macos-14`.

## Releases (maintainers)

Tag a version — `git tag v1.6.0 && git push --tags` — and
`.github/workflows/release.yml` builds the universal DMG + zip and publishes a
GitHub release whose notes come from `CHANGELOG.md`. Full process and the
"What's new" standard: **[RELEASING.md](RELEASING.md)**.

## Reporting bugs & security issues

Use the issue templates for bugs and features. For anything security-sensitive
(this app kills processes and shells out to system tools), see
[SECURITY.md](SECURITY.md).
