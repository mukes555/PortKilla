# Security Policy

PortNanny lists processes and sends signals to them (it kills processes), reads
process metadata via `libproc` syscalls, and shells out to system tools
(`lsof`, `ps`, `pgrep`, `docker`, `pm2`, `launchctl`, `brew`, and `claude mcp
add` when the setup wizard registers the MCP server). It requests no special
privileges and opens no network listeners; its only outbound network call is a
once-a-day GitHub Releases check.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Instead, report
privately via GitHub's **Security → Report a vulnerability** ("Private
vulnerability reporting") on the repository, or contact the maintainer directly.

Include repro steps and the affected version. You'll get an acknowledgement, and
we'll work on a fix and disclosure timeline with you.

## Scope worth noting

- The `portnanny://` URL scheme can request a kill (`?force=1` asks for
  SIGKILL), but every scheme-initiated kill requires an explicit in-app
  confirmation that names the variant, and refuses protected processes.
- Kills verify process identity before signalling to avoid PID-reuse mistakes.
- The app is ad-hoc signed and not notarized (no Apple Developer account); this
  is a distribution property, documented in the README, not a code vulnerability.

## Process environment access

To attribute a port to the AI agent that started it, PortNanny reads a fixed
allowlist of environment variables from listening processes it owns (via the
same `KERN_PROCARGS2` buffer it already uses for command lines). The allowlist
is `AgentSignatures.markerKeys`; nothing else in a process environment is
read, stored, logged, or displayed; the allowlist is applied to the raw
bytes and the buffer is zeroed afterwards. Environments of other users' processes are
not readable by the kernel to begin with.

## What PortNanny can and cannot see

PortNanny runs as your user with no elevated privileges, no helper tool, and
no TCC prompts. It can see every process's name, path, arguments, and
listening sockets (through libproc, as `lsof` and `ps` do). It can read the
environment only of processes you own, and only the handful of keys in the
allowlist. It cannot signal root or other users' processes (the kill fails
with EPERM). It never reads file contents, network traffic, or the
clipboard. Nothing leaves the machine except one GET to
`api.github.com/repos/mukes555/PortNanny/releases/latest` (or
`.../releases?per_page=15` when beta releases are enabled) for the update
check; the inspector's Peek is a GET to 127.0.0.1 only.

## The friendly-fire guard is a cooperation protocol

The guard stops well-behaved AI agents from killing each other's servers by
accident. It is not a security boundary: any process running as your user
can call `kill(2)` directly, and `PORTNANNY_OWNER` is a self-declaration that
PortNanny takes at face value. A hostile local process could declare an
owner to make its port refusable to other agents, or declare a victim's name
to bypass the guard. Both require code already running as you, at which
point PortNanny is not what stands between it and your processes.
