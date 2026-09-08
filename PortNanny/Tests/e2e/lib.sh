# Shared harness for the PortNanny end-to-end suites.
#
# Safety rules, learned the hard way:
#   - only ever signal PIDs recorded here at spawn time, never a pattern
#   - refuse to start a server on a port that is not already free
#   - every listener binds 127.0.0.1 in 45001-45019
setopt NO_HUP NO_CHECK_JOBS
PN="${PN:?set PN to the portnanny binary under test}"
# Where the scripts park command output they need to grep.
S_OUT="${S_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/portnanny-e2e.XXXXXX")}"
PASS=0; FAIL=0
STARTED=()
LAST_PID=""

ok()  { PASS=$((PASS+1)); print -r -- "  ok    $1" }
bad() { FAIL=$((FAIL+1)); print -r -- "  FAIL  $1" }
check() { if [ "$2" = "$3" ]; then ok "$1 (exit $3)"; else bad "$1 (expected exit $2, got $3)"; fi }
alive() { kill -0 "$1" 2>/dev/null }

cleanup() {
  local pid
  for pid in $STARTED; do kill -9 "$pid" 2>/dev/null; done
  STARTED=()
}
trap cleanup EXIT INT TERM

portBusy() { "$PN" list --json 2>/dev/null | grep -q "\"port\" : $1," }

# serve <port> [env assignments...]; sets LAST_PID, returns non-zero on failure.
# Runs in the calling shell: a command substitution would take the server down
# with its subshell.
serve() {
  local port=$1; shift
  if portBusy "$port"; then
    bad "port $port was already in use, refusing to start a test server on it"
    return 1
  fi
  if [ "$#" -gt 0 ]; then
    env "$@" python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 &
  else
    python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 &
  fi
  LAST_PID=$!
  STARTED+=($LAST_PID)
  local i
  for i in {1..40}; do
    if ! alive $LAST_PID; then bad "the server for $port exited immediately"; return 1; fi
    portBusy "$port" && return 0
    sleep 0.25
  done
  bad "port $port never appeared in list"
  return 1
}

# Runs the CLI as a named agent session.
asAgent() {
  local owner=$1 session=$2; shift 2
  env PORTNANNY_OWNER="$owner" PORTNANNY_SESSION="$session" "$PN" "$@"
}

summary() {
  print -r -- ""
  print -r -- "== $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}
