---
name: portnanny
description: Free, find, reserve, or inspect local ports with PortNanny, which knows which AI agent owns each server. Use whenever a port is busy, a dev server must be stopped or started, or "EADDRINUSE" appears.
---

# Freeing ports with PortNanny

Never run `kill -9 $(lsof -ti:PORT)`: other AI agents may be using that
port, and PortNanny knows who owns what.

- `portnanny free <port>` frees the port (SIGTERM, verified; exit 0 if it
  was already free). `portnanny kill <port> --dry-run --json` shows what
  would happen first.
- Exit code 3 means the port belongs to another agent's running session, to
  nobody PortNanny can name (most likely a person's server), or someone
  holds a lease on it. The refusal is on stderr. Do not retry with
  `--force`; tell the user, or pick another port. "Another Claude Code
  session" is still another session: it is not you.
- Exit code 6 means a supervisor (pm2, launchd, Docker, a reloader such as
  nodemon) would undo a plain kill and its tool is not on PATH; stderr names
  the command to run instead.
- `portnanny exec --free-port --prefer 3000 -- npm run dev` picks a free
  port, exports PORT, leases the port for the run, and attributes the server
  to you. `portnanny reserve <port> --for 10m` leases a port you are about
  to use by hand; `portnanny release <port>` gives it back.
- `portnanny free-port --prefer 3000` prints the first free port nobody has
  leased.
- `portnanny whois <port>` explains who started a server and why PortNanny
  thinks so, and what `kill` would do for you.
- `portnanny drift` lists servers running off the port their project's
  .env, package.json, or vite.config names, and who holds that port.
- `portnanny kill --orphaned` stops servers left behind by ended agent
  sessions; safe for anyone.
- `portnanny wait <port> --timeout 30` blocks until the port is free.
- `portnanny list --json` lists every listener with its owning agent;
  `portnanny list --mine` shows only the ones you may stop.
- `portnanny history --port <port>` shows who started and who stopped a
  server that has vanished.

The MCP server this plugin registers offers the same as tools: `list_ports`,
`kill_port` (dry run by default), `whois_port`, `free_port`, `reserve_port`,
`release_port`, `whoami`, `wait_for_port_free`.
