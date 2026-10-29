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

# Keep dialogs small enough that the buttons always stay on screen
MAX_LINE = 160
MAX_QUESTIONS = 4
MAX_PARAMS = 300
QUESTION_TIMEOUT_SEC = 120

# Text is passed via argv so no AppleScript string escaping is needed
DIALOG_SCRIPT = """
on run argv
    set {msg, ttl, btns, giveUp} to {item 1 of argv, item 2 of argv, item 3 of argv, item 4 of argv as integer}
    set AppleScript's text item delimiters to "|"
    set btnList to text items of btns
    if giveUp > 0 then
        display dialog msg with title ttl buttons btnList default button (last item of btnList) giving up after giveUp
    else
        display dialog msg with title ttl buttons btnList default button (last item of btnList)
    end if
end run
"""

with open(sys.argv[1]) as f:
    try:
        data = json.load(f)
    except Exception:
        sys.exit(0)

tool_name    = data.get("tool_name", "unknown")
project_path = data.get("cwd", "unknown")
tool_input   = data.get("tool_input") or {}
popup_mode   = os.environ.get("POPUP_MODE", "full").lower()

# --- auto mode: only surface AskUserQuestion ---
if popup_mode == "auto" and tool_name != "AskUserQuestion":
    sys.exit(0)

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


def clip(s, n):
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 1] + "…"


def dialog_args(msg, title, buttons, give_up=0):
    return ["osascript", "-e", DIALOG_SCRIPT, msg, title, "|".join(buttons), str(give_up)]


def summarize_questions(ti):
    # Current payload: {"questions": [{question, header, options: [{label, ...}]}]}
    # Legacy payload: {"question": "..."}
    questions = ti.get("questions")
    if not isinstance(questions, list):
        return [clip(ti.get("question", "(no question text)"), MAX_LINE)]
    lines = []
    for q in questions[:MAX_QUESTIONS]:
        if not isinstance(q, dict):
            continue
        header = q.get("header")
        text = q.get("question", "")
        lines.append(clip(f"• [{header}] {text}" if header else f"• {text}", MAX_LINE))
        labels = [o.get("label", "") for o in q.get("options", []) if isinstance(o, dict)]
        if labels:
            lines.append(clip("   " + " / ".join(labels), MAX_LINE))
    if len(questions) > MAX_QUESTIONS:
        lines.append(f"…and {len(questions) - MAX_QUESTIONS} more")
    return lines or ["(no question text)"]


def summarize_params(name, ti):
    if name == "Bash" and "command" in ti:
        return clip(ti["command"], MAX_PARAMS)
    if "file_path" in ti:
        return clip(ti["file_path"], MAX_PARAMS)
    return clip(json.dumps(ti, ensure_ascii=False), MAX_PARAMS)


if tool_name == "AskUserQuestion":
    msg = "\n".join(
        ["Claude is asking you:", ""]
        + summarize_questions(tool_input)
        + ["", f"Project: {clip(project_name, MAX_LINE)}", "Switch to the Claude Code window to answer."]
    )
    # Informational only: don't block, or the question can't render until OK is clicked
    subprocess.Popen(
        dialog_args(msg, "Claude Code — Question", ["OK"], QUESTION_TIMEOUT_SEC),
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
    )
    sys.exit(0)

# Permission popup
msg = "\n".join([
    f"Tool: {clip(tool_name, MAX_LINE)}",
    f"Project: {clip(project_name, MAX_LINE)}",
    f"Path: {clip(project_path, MAX_LINE)}",
    "",
    summarize_params(tool_name, tool_input),
])
result = subprocess.run(
    dialog_args(msg, "Claude Code Permission", ["Deny", "Allow"]),
    capture_output=True, text=True,
)
if "Allow" in result.stdout:
    sys.exit(0)
print("Permission denied by user.")
sys.exit(2)
PYEOF

exit $?
