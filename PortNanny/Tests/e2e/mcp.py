#!/usr/bin/env python3
"""Speak MCP to `portnanny mcp` over stdin/stdout, the way an agent does.

Starts one real listener on 45012 to call tools against, and kills only that
pid at the end. kill_port is only ever called with dry_run left at its
default, so nothing is signalled.
"""
import json, os, subprocess, sys, time

PN = os.environ.get("PN", "/opt/homebrew/bin/portnanny")
PORT = 45012
passed = failed = 0


def ok(what):
    global passed
    passed += 1
    print(f"  ok    {what}")


def bad(what):
    global failed
    failed += 1
    print(f"  FAIL  {what}")


def check(what, condition, detail=""):
    ok(what) if condition else bad(f"{what}{(': ' + detail) if detail else ''}")


class MCP:
    def __init__(self):
        self.proc = subprocess.Popen(
            [PN, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1,
            env={**os.environ, "PORTNANNY_OWNER": "Cursor", "PORTNANNY_SESSION": "mcp-session"},
        )
        self.n = 0

    def call(self, method, params=None):
        self.n += 1
        request = {"jsonrpc": "2.0", "id": self.n, "method": method}
        if params is not None:
            request["params"] = params
        self.proc.stdin.write(json.dumps(request) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        return json.loads(line) if line.strip() else None

    def raw(self, text):
        self.proc.stdin.write(text + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        return json.loads(line) if line.strip() else None

    def tool(self, name, arguments=None):
        return self.call("tools/call", {"name": name, "arguments": arguments or {}})

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=5)


def structured(reply):
    return ((reply or {}).get("result") or {}).get("structuredContent")


def is_error(reply):
    return ((reply or {}).get("result") or {}).get("isError")


server = subprocess.Popen(
    ["python3", "-m", "http.server", str(PORT), "--bind", "127.0.0.1"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    env={**os.environ, "PORTNANNY_OWNER": "Claude Code", "PORTNANNY_SESSION": "mcp-victim"},
)
try:
    for _ in range(40):
        listed = subprocess.run([PN, "list", "--json"], capture_output=True, text=True)
        if f'"port" : {PORT},' in listed.stdout:
            break
        time.sleep(0.25)

    m = MCP()
    print(f"== MCP over stdio, {PN} mcp")

    print("\n== handshake")
    reply = m.call("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                  "clientInfo": {"name": "e2e", "version": "1"}})
    check("initialize answers", (reply or {}).get("result") is not None)
    info = ((reply or {}).get("result") or {}).get("serverInfo") or {}
    check("it names itself", "portnanny" in json.dumps(info).lower(), json.dumps(info))

    print("\n== tools/list")
    tools = [t["name"] for t in (m.call("tools/list") or {}).get("result", {}).get("tools", [])]
    expected = {"list_ports", "whois_port", "kill_port", "free_port",
                "reserve_port", "release_port", "whoami", "wait_for_port_free"}
    check("all eight tools are advertised", set(tools) == expected, f"got {sorted(tools)}")

    print("\n== read-only tools")
    who = structured(m.tool("whoami"))
    owner = (who or {}).get("owner") or {}
    check("whoami reports the declared agent", owner.get("name") == "Cursor", json.dumps(who))
    check("whoami carries the declared session", owner.get("sessionKey") == "mcp-session", json.dumps(owner))
    ports = structured(m.tool("list_ports"))
    text = json.dumps(ports)
    check(f"list_ports includes the test listener on {PORT}", f'"port": {PORT}' in text.replace(" :", ":"))
    dossier = structured(m.tool("whois_port", {"port": PORT}))
    check("whois_port names the owning agent", "Claude Code" in json.dumps(dossier), json.dumps(dossier)[:160])

    print("\n== kill_port is a dry run unless told otherwise")
    reply = m.tool("kill_port", {"port": PORT})
    action = (structured(reply) or {}).get("action", "")
    check("the default action only reports", action.startswith("would-"), f"action was {action!r}")
    check("the server is untouched", server.poll() is None)
    check("it refuses another agent's server", is_error(reply) is True, json.dumps(structured(reply))[:160])

    print("\n== leases")
    reserved = structured(m.tool("reserve_port", {"port": 45013, "minutes": 1, "reason": "e2e"}))
    check("reserve_port takes the port", (reserved or {}).get("action") in ("reserved", "renewed"), json.dumps(reserved))
    listed = subprocess.run([PN, "reservations", "--json"], capture_output=True, text=True).stdout
    check("the CLI sees the lease the MCP server made", "45013" in listed)
    again = m.tool("reserve_port", {"port": 45013, "minutes": 1})
    check("reserving it again renews rather than fails", is_error(again) is not True, json.dumps(structured(again)))
    released = structured(m.tool("release_port", {"port": 45013}))
    check("release_port frees it", (released or {}).get("action") == "released", json.dumps(released))
    twice = m.tool("release_port", {"port": 45013})
    check("releasing an unheld port is not an error", is_error(twice) is not True, json.dumps(structured(twice)))

    print("\n== free_port and wait_for_port_free")
    free = structured(m.tool("free_port", {"prefer": 45014}))
    check("free_port suggests a port at or above the preference",
          isinstance((free or {}).get("port"), int) and free["port"] >= 45014, json.dumps(free))
    check("free_port rejects a range that ends below the preference",
          is_error(m.tool("free_port", {"prefer": 45100, "range_end": 45000})) is True)
    waited = structured(m.tool("wait_for_port_free", {"port": 45015, "timeout_seconds": 1}))
    check("wait_for_port_free returns at once for a free port", (waited or {}).get("free") is True, json.dumps(waited))

    print("\n== bad input")
    check("an unknown tool is an error", (m.tool("no_such_tool") or {}).get("error") is not None
          or is_error(m.tool("no_such_tool")) is True)
    check("reserve_port with no port is an error", is_error(m.tool("reserve_port")) is True)
    check("a port as a string is rejected", is_error(m.tool("kill_port", {"port": str(PORT)})) is True)
    check("malformed JSON gets a JSON-RPC error", (m.raw("{not json") or {}).get("error") is not None)
    check("the server is still answering after that", (m.tool("whoami") or {}).get("result") is not None)

    m.close()
finally:
    server.kill()
    server.wait()

print(f"\n== {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
