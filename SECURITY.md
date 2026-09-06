# Security Policy

PortKilla lists processes and sends signals to them (it kills processes), reads
process metadata via `libproc` syscalls, and shells out to system tools
(`lsof`, `ps`, `docker`). It requests no special privileges and opens no network
listeners; its only outbound network call is a once-a-day GitHub Releases check.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Instead, report
privately via GitHub's **Security → Report a vulnerability** ("Private
vulnerability reporting") on the repository, or contact the maintainer directly.

Include repro steps and the affected version. You'll get an acknowledgement, and
we'll work on a fix and disclosure timeline with you.

## Scope worth noting

- The `portkilla://` URL scheme can request a kill, but every scheme-initiated
  kill requires an explicit in-app confirmation and refuses protected processes.
- Kills verify process identity before signalling to avoid PID-reuse mistakes.
- The app is ad-hoc signed and not notarized (no Apple Developer account); this
  is a distribution property, documented in the README, not a code vulnerability.

## Process environment access

To attribute a port to the AI agent that started it, PortKilla reads a fixed
allowlist of environment variables from listening processes it owns (via the
same `KERN_PROCARGS2` buffer it already uses for command lines). The allowlist
is `AgentAttribution.markerKeys`; nothing else in a process environment is
read, stored, logged, or displayed. Environments of other users' processes are
not readable by the kernel to begin with.
