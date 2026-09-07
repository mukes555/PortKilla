---
description: List listening ports with the AI agent that owns each
allowed-tools: Bash(portnanny:*)
---

!`portnanny list`

Summarise the listeners above: which belong to running agent sessions (do
not stop those; say who owns them), which are orphaned or unclaimed, and
which are mine. Suggest `portnanny free <port>` only for ports the guard
would let me stop.
