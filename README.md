# cc-push — Claude Code Popup Notifier

Native OS dialogs for Claude Code permission requests and task completion, designed for developers who run multiple Claude Code windows simultaneously.

## The Problem

When you have several Claude Code sessions open in VSCode, permission requests and task completions can go unnoticed — the relevant window is buried behind others. `cc-push` hooks into Claude Code and surfaces these events as native OS dialogs that appear on top of everything.

## What It Does

### Permission Popup (PreToolUse)
Before Claude executes any tool, a native dialog appears showing:
- **Tool name** (e.g. `Bash`, `Write`, `Edit`)
- **Project path** — so you know which session triggered it
- **Parameter summary** — what the tool is about to do

Click **Allow** to proceed or **Deny** to block.

Read-only tools (`Read`, `Glob`, `Grep`, `LS`) are auto-allowed and never prompt.

### Completion Notification (Stop)
When Claude finishes a task, a dialog shows the project name and path.  
Click **OK** to dismiss.

## Requirements

| Platform | Requirement |
|----------|-------------|
| macOS    | `python3` (via Xcode CLI tools: `xcode-select --install`), `osascript` (built-in) |
| Windows  | PowerShell 5.1+ (built-in on Windows 10/11) |

## Installation

### macOS / Linux

```bash
git clone https://github.com/Jasmyn-X/cc-push.git
cd cc-push
bash install.sh
```

### Windows

```powershell
git clone https://github.com/Jasmyn-X/cc-push.git
cd cc-push
powershell -ExecutionPolicy Bypass -File install.ps1
```

Restart Claude Code after installation for hooks to take effect.

## Configuration

### POPUP_MODE — match your Claude Code permission mode

| `POPUP_MODE` | PreToolUse | Stop (task complete) |
|-------------|-----------|----------------------|
| `full` (default) | Popup for every tool call except the skip list | Always notifies |
| `auto` | Only `AskUserQuestion` — permissions are silent | Always notifies |

The completion notification fires in **both modes** — you'll always know when Claude finishes, regardless of `POPUP_MODE`. Use `auto` when Claude Code's auto-accept is enabled: permissions go through silently, but you're still alerted when Claude asks you a question or finishes a task.

**macOS:**
```bash
export POPUP_MODE="auto"   # when using auto-accept in Claude Code
export POPUP_MODE="full"   # when Claude Code prompts for permissions
```

**Windows:**
```powershell
$env:POPUP_MODE = "auto"   # when using auto-accept in Claude Code
$env:POPUP_MODE = "full"   # when Claude Code prompts for permissions
```

### POPUP_SKIP_TOOLS — auto-allow specific tools (full mode only)

By default, `Read`, `Glob`, `Grep`, and `LS` are silently allowed.  
Add more tools to skip:

**macOS** (add to `~/.zshrc` or `~/.bash_profile`):
```bash
export POPUP_SKIP_TOOLS="Write,Edit,TodoWrite"
```

**Windows** (add to PowerShell profile):
```powershell
$env:POPUP_SKIP_TOOLS = "Write,Edit,TodoWrite"
```

## Manual Installation

If you prefer to configure hooks yourself, add to `~/.claude/settings.json`:

**macOS:**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          { "type": "command", "command": "/absolute/path/to/cc-push/hooks/permission-popup.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "/absolute/path/to/cc-push/hooks/stop-notify.sh" }
        ]
      }
    ]
  }
}
```

**Windows:**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          { "type": "command", "command": "powershell -ExecutionPolicy Bypass -NonInteractive -File \"C:\\absolute\\path\\to\\cc-push\\hooks\\permission-popup.ps1\"" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "powershell -ExecutionPolicy Bypass -NonInteractive -File \"C:\\absolute\\path\\to\\cc-push\\hooks\\stop-notify.ps1\"" }
        ]
      }
    ]
  }
}
```

## Uninstallation

Remove the hook entries from `~/.claude/settings.json` (the entries with description `cc-push permission dialog` and `cc-push completion notification`), then delete the cloned directory.

## How It Works

Claude Code supports [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) — shell commands that run at specific lifecycle events:

- **PreToolUse**: runs before any tool call; exit `0` allows, exit `2` blocks
- **Stop**: runs when Claude finishes; exit `0` lets it stop normally

`cc-push` installs two hook scripts:

1. `hooks/permission-popup.sh` / `.ps1` — reads the tool name, parameters, and project path from Claude's JSON stdin, then shows an Allow/Deny dialog
2. `hooks/stop-notify.sh` / `.ps1` — shows a project-identified completion notification

## Inspiration

Inspired by [claude-permission-popup](https://github.com/Melodymaifafa/claude-permission-popup) (macOS-only, Node.js). `cc-push` extends the idea to Windows, adds Stop notifications, and uses only built-in tools.

## License

MIT
