#!/usr/bin/env bash
# PreToolUse hook — macOS/Linux
# Requires: python3, osascript (macOS built-in)
#
# Exit 0 = Allow tool to run
# Exit 2 = Deny tool execution
#
# POPUP_MODE:
#   full (default) — popup for all non-skip-listed tools
#   auto           — popup ONLY for AskUserQuestion (mirrors Claude Code auto mode)
#
# POPUP_SKIP_TOOLS: comma-separated extra tool names to auto-allow (full mode only)

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

tool_name    = data.get("tool_name", "unknown")
project_path = data.get("cwd", "unknown")
tool_input   = data.get("tool_input", {})
popup_mode   = os.environ.get("POPUP_MODE", "full").lower()

# --- auto mode: only surface AskUserQuestion ---
if popup_mode == "auto":
    if tool_name != "AskUserQuestion":
        sys.exit(0)
    # Fall through to show the question popup

# --- full mode: skip read-only + user-configured tools ---
if popup_mode != "auto":
    default_skip = {"Read", "Glob", "Grep", "LS"}
    env_skip = os.environ.get("POPUP_SKIP_TOOLS", "")
    if env_skip:
        default_skip.update(s.strip() for s in env_skip.split(",") if s.strip())
    if tool_name in default_skip:
        sys.exit(0)

if not shutil.which("osascript"):
    sys.exit(0)

project_name = os.path.basename(project_path) or project_path

def esc_as(s):
    return (
        s.replace("\\", "\\\\")
         .replace('"', '\\"')
         .replace("\n", "\\n")
         .replace("\r", "")
    )

if tool_name == "AskUserQuestion":
    question = tool_input.get("question", json.dumps(tool_input))
    msg = (
        f"Claude is asking you a question:\\n\\n"
        f"{esc_as(question)}\\n\\n"
        f"Project: {esc_as(project_name)}\\n"
        f"Path: {esc_as(project_path)}\\n\\n"
        f"Switch to the Claude Code window to answer."
    )
    script = (
        f'display dialog "{msg}" '
        f'with title "Claude Code — Question" '
        f'buttons {{"OK"}} '
        f'default button "OK"'
    )
    subprocess.run(["osascript", "-e", script], capture_output=True)
    sys.exit(0)

# Permission popup
params = json.dumps(tool_input, ensure_ascii=False)
if len(params) > 200:
    params = params[:197] + "..."

msg = (
    f"Tool: {esc_as(tool_name)}\\n"
    f"Project: {esc_as(project_name)}\\n"
    f"Path: {esc_as(project_path)}\\n\\n"
    f"Params: {esc_as(params)}"
)
script = (
    f'display dialog "{msg}" '
    f'with title "Claude Code Permission" '
    f'buttons {{"Deny", "Allow"}} '
    f'default button "Allow"'
)

result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
if "Allow" in result.stdout:
    sys.exit(0)
else:
    print("Permission denied by user.")
    sys.exit(2)
PYEOF

exit $?
