---
description: Free a port through PortNanny's guard (dry run first)
argument-hint: <port>
allowed-tools: Bash(portnanny:*)
---

!`portnanny kill $ARGUMENTS --dry-run`

If the dry run above says it would kill, run `portnanny free $ARGUMENTS`
and report the result. If it was refused (exit 3), do not use --force: tell
me who owns the port and offer `portnanny free-port --prefer $ARGUMENTS`
instead.
