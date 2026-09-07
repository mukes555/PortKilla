---
description: Free a port through PortKilla's guard (dry run first)
argument-hint: <port>
allowed-tools: Bash(portkilla:*)
---

!`portkilla kill $ARGUMENTS --dry-run`

If the dry run above says it would kill, run `portkilla free $ARGUMENTS`
and report the result. If it was refused (exit 3), do not use --force: tell
me who owns the port and offer `portkilla free-port --prefer $ARGUMENTS`
instead.
