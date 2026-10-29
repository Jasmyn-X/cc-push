#!/usr/bin/env bash
# Black-box tests for the macOS hooks. A fake `osascript` on PATH records the
# dialog text instead of showing it, so these run headless.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE_BIN="$(mktemp -d)"
LOG="$FAKE_BIN/osascript.log"
trap 'rm -rf "$FAKE_BIN"' EXIT

cat > "$FAKE_BIN/osascript" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$OSASCRIPT_LOG"
[ -n "${FAKE_SLEEP:-}" ] && sleep "$FAKE_SLEEP"
echo "button returned:Allow"
SH
chmod +x "$FAKE_BIN/osascript"
export PATH="$FAKE_BIN:$PATH" OSASCRIPT_LOG="$LOG"

FAILS=0
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
pass() { echo "ok:   $1"; }
reset_log() { : > "$LOG"; }
wait_log() { for _ in $(seq 20); do [ -s "$LOG" ] && return; sleep 0.1; done; }

LONG_DESC=$(python3 -c 'print("x" * 3000)')

# 1. AskUserQuestion with the current `questions` array payload
reset_log
payload=$(python3 - "$LONG_DESC" <<'PY'
import json, sys
d = sys.argv[1]
print(json.dumps({
  "tool_name": "AskUserQuestion", "cwd": "/Users/me/proj",
  "tool_input": {"questions": [
    {"question": "Which auth method?", "header": "Auth", "multiSelect": False,
     "options": [{"label": "OAuth", "description": d, "preview": d},
                 {"label": "API key", "description": d}]},
    {"question": "Which DB?", "header": "DB", "multiSelect": False,
     "options": [{"label": "Postgres", "description": d}, {"label": "SQLite", "description": d}]}
  ]}}))
PY
)
start=$(python3 -c 'import time; print(time.time())')
echo "$payload" | FAKE_SLEEP=3 POPUP_MODE=auto "$ROOT/hooks/permission-popup.sh"; rc=$?
elapsed=$(python3 -c "import time; print(time.time() - $start)")
wait_log
text=$(cat "$LOG")
[ "$rc" -eq 0 ] && pass "question: exit 0" || fail "question: exit $rc"
echo "$text" | grep -q "Which auth method?" && pass "question: shows question text" || fail "question: missing question text"
echo "$text" | grep -q "Which DB?" && pass "question: shows every question" || fail "question: missing second question"
echo "$text" | grep -q 'options' && fail "question: raw JSON dumped" || pass "question: no raw JSON"
len=${#text}
[ "$len" -lt 900 ] && pass "question: dialog text short ($len chars)" || fail "question: dialog text too long ($len chars)"
python3 -c "import sys; sys.exit(0 if $elapsed < 2 else 1)" && pass "question: hook does not block on dialog" || fail "question: hook blocked ${elapsed}s"

# 2. Permission popup (full mode) with a huge command stays short
reset_log
payload=$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','cwd':'/p','tool_input':{'command':'echo ' + 'y'*5000}}))")
echo "$payload" | POPUP_MODE=full "$ROOT/hooks/permission-popup.sh" >/dev/null; rc=$?
text=$(cat "$LOG")
[ "$rc" -eq 0 ] && pass "permission: Allow -> exit 0" || fail "permission: exit $rc"
[ "${#text}" -lt 900 ] && pass "permission: dialog text short (${#text} chars)" || fail "permission: too long (${#text})"

# 3. auto mode silently allows non-question tools
reset_log
echo '{"tool_name":"Bash","cwd":"/p","tool_input":{"command":"ls"}}' | POPUP_MODE=auto "$ROOT/hooks/permission-popup.sh"; rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$LOG" ] && pass "auto: Bash allowed without popup" || fail "auto: rc=$rc log=$(cat "$LOG")"

# 4. Stop notification is short and non-blocking
reset_log
SECONDS=0
echo '{"cwd":"/Users/me/装修tracker","stop_hook_active":false}' | FAKE_SLEEP=3 "$ROOT/hooks/stop-notify.sh"; rc=$?
[ "$SECONDS" -lt 2 ] && pass "stop: hook does not block on dialog" || fail "stop: hook blocked ${SECONDS}s"
wait_log
text=$(cat "$LOG")
[ "$rc" -eq 0 ] && pass "stop: exit 0" || fail "stop: exit $rc"
echo "$text" | grep -q "装修tracker" && pass "stop: shows project name" || fail "stop: missing project name"

echo
[ "$FAILS" -eq 0 ] && echo "ALL PASSED" || { echo "$FAILS FAILED"; exit 1; }
