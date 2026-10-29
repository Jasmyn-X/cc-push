#!/usr/bin/env bash
# Stop hook — macOS/Linux
# Shows a native notification dialog when Claude Code finishes a task.
# Requires: python3, osascript (macOS built-in)

TMP=$(mktemp 2>/dev/null) || exit 0
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" 2>/dev/null || exit 0

python3 - "$TMP" <<'PYEOF'
import sys
import json
import subprocess
import os
import shutil

MAX_LINE = 160
DISMISS_AFTER_SEC = 60

# Text is passed via argv so no AppleScript string escaping is needed
DIALOG_SCRIPT = """
on run argv
    display dialog (item 1 of argv) with title (item 2 of argv) buttons {"OK"} default button "OK" giving up after (item 3 of argv as integer)
end run
"""

with open(sys.argv[1]) as f:
    try:
        data = json.load(f)
    except Exception:
        sys.exit(0)

# Prevent recursive stop hook execution
if data.get("stop_hook_active", False):
    sys.exit(0)

if not shutil.which("osascript"):
    sys.exit(0)


def clip(s, n):
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 1] + "…"


project_path = data.get("cwd", "unknown")
project_name = os.path.basename(project_path) or project_path

msg = f"Project: {clip(project_name, MAX_LINE)}\nPath: {clip(project_path, MAX_LINE)}"

# Don't block Claude Code while the dialog is open
subprocess.Popen(
    ["osascript", "-e", DIALOG_SCRIPT, msg, "Claude Code — Task Finished", str(DISMISS_AFTER_SEC)],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
)
sys.exit(0)
PYEOF

exit 0
