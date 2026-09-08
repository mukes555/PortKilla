#!/usr/bin/env python3
"""Run a command with no agent in its ancestry.

Double-forks and calls setsid, so the child reparents to launchd and its
process tree no longer leads back to the Claude Code session that started
this script. Writes "<pid>" (servers) or "exit <code>" (short commands)
to the status file.

    detach.py <status-file> [--wait] <command> [args...]
"""
import os, sys, subprocess

status, args = sys.argv[1], sys.argv[2:]
wait = args and args[0] == "--wait"
if wait:
    args = args[1:]

if os.fork() != 0:
    os._exit(0)          # parent returns to the caller at once
os.setsid()              # new session: no controlling terminal, no agent above
if not wait and os.fork() != 0:
    os._exit(0)          # servers get a second fork so they reparent to launchd

env = {k: v for k, v in os.environ.items()
       if not k.startswith(("PORTNANNY_", "PORTKILLA_", "CLAUDE", "CURSOR", "CODEX", "GEMINI"))}
env.pop("TERM_PROGRAM", None)

if wait:
    done = subprocess.run(args, env=env, capture_output=True, text=True)
    with open(status, "w") as f:
        f.write(f"exit {done.returncode}\n{done.stdout}{done.stderr}")
else:
    child = subprocess.Popen(args, env=env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(status, "w") as f:
        f.write(str(child.pid))
    child.wait()
