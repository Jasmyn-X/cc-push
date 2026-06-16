#!/usr/bin/env bash
# Install cc-push hooks for macOS/Linux
# Adds PreToolUse and Stop hooks to ~/.claude/settings.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/hooks"
SETTINGS_FILE="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

echo "Installing cc-push..."
echo ""

# Check dependencies
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required."
    echo "  macOS: install Xcode Command Line Tools with 'xcode-select --install'"
    exit 1
fi

if ! command -v osascript &>/dev/null; then
    echo "Warning: osascript not found — popups will be skipped on this system."
    echo "  (This tool is designed for macOS. Linux support is limited.)"
    echo ""
fi

# Make hook scripts executable
chmod +x "$HOOKS_DIR/permission-popup.sh"
chmod +x "$HOOKS_DIR/stop-notify.sh"

# Ensure ~/.claude directory exists
mkdir -p "$(dirname "$SETTINGS_FILE")"

# Update settings.json
python3 - "$SETTINGS_FILE" "$HOOKS_DIR" <<'PYEOF'
import sys, json, os

settings_file = sys.argv[1]
hooks_dir = sys.argv[2]

# Load existing settings or start fresh
if os.path.exists(settings_file):
    with open(settings_file) as f:
        try:
            settings = json.load(f)
        except Exception:
            settings = {}
else:
    settings = {}

hooks = settings.setdefault("hooks", {})

popup_cmd  = os.path.join(hooks_dir, "permission-popup.sh")
notify_cmd = os.path.join(hooks_dir, "stop-notify.sh")

def has_our_command(entry, cmd):
    for h in entry.get("hooks", []):
        if h.get("command") == cmd:
            return True
    return False

# PreToolUse — remove stale entry, then append
pre = [h for h in hooks.get("PreToolUse", []) if not has_our_command(h, popup_cmd)]
pre.append({
    "matcher": ".*",
    "hooks": [{"type": "command", "command": popup_cmd}]
})
hooks["PreToolUse"] = pre

# Stop — remove stale entry, then append
stop = [h for h in hooks.get("Stop", []) if not has_our_command(h, notify_cmd)]
stop.append({
    "hooks": [{"type": "command", "command": notify_cmd}]
})
hooks["Stop"] = stop

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)

print(f"Updated: {settings_file}")
PYEOF

echo ""
echo "Done! Restart Claude Code for hooks to take effect."
echo ""
echo "Optional — auto-allow additional tools (comma-separated):"
echo "  export POPUP_SKIP_TOOLS=\"Write,Edit,TodoWrite\""
echo "  Add to ~/.zshrc or ~/.bash_profile to persist."
