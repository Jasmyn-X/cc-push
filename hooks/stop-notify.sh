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

with open(sys.argv[1]) as f:
    try:
        data = json.load(f)
    except Exception:
        sys.exit(0)

# Prevent recursive stop hook execution
if data.get("stop_hook_active", False):
    sys.exit(0)

project_path = data.get("cwd", "unknown")
project_name = os.path.basename(project_path) or project_path

if not shutil.which("osascript"):
    sys.exit(0)

def esc_as(s):
    return (
        s.replace("\\", "\\\\")
         .replace('"', '\\"')
         .replace("\n", "\\n")
         .replace("\r", "")
    )

msg = (
    f"Project: {esc_as(project_name)}\\n"
    f"Path: {esc_as(project_path)}"
)

script = (
    f'display dialog "{msg}" '
    f'with title "Claude Code — Task Finished" '
    f'buttons {{"OK"}} '
    f'default button "OK"'
)

subprocess.run(["osascript", "-e", script], capture_output=True)
sys.exit(0)
PYEOF

exit 0
