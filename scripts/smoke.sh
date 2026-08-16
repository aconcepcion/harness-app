#!/bin/bash
# End-to-end smoke for Harness.app using the fake dsh server.
# Usage: scripts/smoke.sh <path/to/Harness.app> <path/to/fakedsh>
set -uo pipefail
APP="$1"; FAKE="$2"; BIN="$APP/Contents/MacOS/Harness"
DOMAIN=com.arnoldoconcepcion.harness-app
PORT=3488; URL="http://127.0.0.1:$PORT/"
LOG="$HOME/Library/Logs/Harness.app/harness-app.log"
FAILS=0
ok()   { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; FAILS=$((FAILS+1)); }
up()   { curl -s -o /dev/null -w '%{http_code}' --max-time 1 "$URL" 2>/dev/null | grep -q '^200$'; }
wait_for() { local n=0; until eval "$1"; do n=$((n+1)); [ $n -ge "$2" ] && return 1; sleep 0.5; done; return 0; }
launch() { "$BIN" >/dev/null 2>&1 & APP_PID=$!; }
stop_app() { kill -TERM "$APP_PID" 2>/dev/null; wait_for "! kill -0 $APP_PID 2>/dev/null" 30 || { kill -9 "$APP_PID"; fail "app did not exit on SIGTERM"; }; }

# Preserve the user's preferences; use test values.
BACKUP="$(mktemp)"; defaults export "$DOMAIN" "$BACKUP" 2>/dev/null || true
restore() { defaults delete "$DOMAIN" 2>/dev/null; [ -s "$BACKUP" ] && defaults import "$DOMAIN" "$BACKUP"; rm -f "$BACKUP"; pkill -9 -f "fakedsh web" 2>/dev/null; }
trap restore EXIT
defaults write "$DOMAIN" Port -int $PORT
defaults write "$DOMAIN" DshPath "$FAKE"
defaults write "$DOMAIN" KeepServerRunning -bool NO
defaults write "$DOMAIN" CheckForDshUpdates -bool NO
defaults write "$DOMAIN" CheckForAppUpdates -bool NO
pkill -9 -f "fakedsh web" 2>/dev/null; sleep 0.5
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

echo "0. --check-env"
OUT="$("$BIN" --check-env 2>&1)"; echo "$OUT" | grep -q '^dsh:' && ok "--check-env prints a report" || fail "--check-env report missing: $OUT"

echo "1. cold start: spawn, ready, SIGTERM stops the server"
launch; wait_for up 60 && ok "server reachable after launch" || fail "server never came up"
grep -q "spawned dsh pid" "$LOG" && ok "log: spawned" || fail "log lacks 'spawned'"
stop_app; sleep 1
up && fail "server still up after quit" || ok "server stopped with the app"
pgrep -f "fakedsh web --port $PORT" >/dev/null && fail "fakedsh orphaned" || ok "no orphan"

echo "2. attach: a pre-started server is used and left running"
"$FAKE" web --port $PORT >/dev/null 2>&1 & PRE=$!
wait_for up 20 || fail "pre-started fakedsh not reachable"
launch; wait_for "grep -q 'attached to existing server' '$LOG'" 40 && ok "log: attached" || fail "did not attach"
stop_app; sleep 1
kill -0 $PRE 2>/dev/null && ok "pre-started server survived app quit" || fail "attached server was killed"
kill $PRE 2>/dev/null; wait $PRE 2>/dev/null; sleep 0.5

echo "3. keep-alive: server persists after quit, next launch attaches"
defaults write "$DOMAIN" KeepServerRunning -bool YES
launch; wait_for up 60 || fail "keep-alive: server never came up"
stop_app; sleep 1
up && ok "server still running after quit (keep-alive)" || fail "server stopped despite keep-alive"
: > "$LOG"
launch; wait_for "grep -q 'attached to existing server' '$LOG'" 40 && ok "second launch attached" || fail "second launch did not attach"
defaults write "$DOMAIN" KeepServerRunning -bool NO
stop_app; pkill -9 -f "fakedsh web --port $PORT"; sleep 0.5

echo "4. escalation: a server that ignores SIGTERM is killed anyway"
FAKEDSH_IGNORE_TERM=1 "$BIN" >/dev/null 2>&1 & APP_PID=$!
wait_for up 60 || fail "stubborn: never came up"
stop_app; sleep 1
up && fail "stubborn server survived" || ok "stubborn server killed (SIGKILL escalation)"

echo "smoke: $FAILS failure(s)"; exit $((FAILS > 0))
