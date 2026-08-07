# PortKilla for Raycast (experimental)

A Raycast command that lists listening ports via the PortKilla CLI and kills
the one in your way — `⌘Space → "kill port" → ⏎`.

**Status: scaffold, not yet published to the Raycast Store.** It has not been
run against a real Raycast dev environment; treat it as a starting point.

## Requirements

- PortKilla.app installed at `/Applications` (the extension shells out to its
  built-in CLI: `PortKilla list --json` / `PortKilla kill <port>`)
- Raycast + Node 20+

## Develop

```bash
cd extensions/raycast
npm install
npm run dev   # opens the command in Raycast's dev mode
```

Add an `icon.png` (512×512 — regenerate from `PortKilla/scripts/make_icon.swift`)
before publishing.
