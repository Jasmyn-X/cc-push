# cc-push — Claude Code 弹窗通知器

为同时开启多个 Claude Code 窗口的开发者提供原生 OS 弹窗，在权限请求和任务完成时及时提醒。

## 问题背景

当你在 VSCode 里同时开着多个 Claude Code 会话时，权限请求和任务完成通知很容易被埋在后台窗口里被忽略。`cc-push` 接入 Claude Code 的 hook 系统，将这些事件以原生 OS 对话框的形式弹出到最前方。

## 功能介绍

### 权限弹窗（PreToolUse）

Claude 执行任何工具前，弹出原生对话框，显示：
- **工具名称**（如 `Bash`、`Write`、`Edit`）
- **项目路径** — 告诉你是哪个会话触发的
- **参数摘要** — 工具即将执行的操作

点击 **Allow（允许）** 继续，或 **Deny（拒绝）** 阻止。

只读工具（`Read`、`Glob`、`Grep`、`LS`）自动放行，不弹窗。

### 完成通知（Stop）

Claude 完成任务后，弹出对话框显示项目名称和路径。  
点击 **OK** 关闭。

## 环境要求

| 平台 | 要求 |
|------|------|
| macOS | `python3`（通过 Xcode 命令行工具：`xcode-select --install`），`osascript`（系统内置） |
| Windows | PowerShell 5.1+（Windows 10/11 内置） |

## 安装方法

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

安装完成后重启 Claude Code 使 hook 生效。

## 配置说明

### POPUP_MODE — 匹配你的 Claude Code 权限模式

| `POPUP_MODE` | PreToolUse | Stop（任务完成） |
|-------------|-----------|-----------------|
| `full`（默认） | 所有工具弹窗（跳过列表除外） | 始终通知 |
| `auto` | 仅 `AskUserQuestion` — 权限请求静默通过 | 始终通知 |

两种模式下完成通知均会弹出——无论 `POPUP_MODE` 如何，你都能知道 Claude 何时完成任务。

开启 Claude Code 的 Auto mode 时建议使用 `auto`：权限自动通过，但 Claude 问你问题或完成任务时仍会弹窗提醒。

推荐做法：在 `~/.claude/settings.json` 的 `env` 字段中设置（一次配置，永久生效）：

```json
{
  "env": {
    "POPUP_MODE": "auto"
  }
}
```

也可以临时设置：

**macOS：**
```bash
export POPUP_MODE="auto"   # 使用 Claude Code Auto mode 时
export POPUP_MODE="full"   # Claude Code 手动审批权限时
```

**Windows：**
```powershell
$env:POPUP_MODE = "auto"   # 使用 Claude Code Auto mode 时
$env:POPUP_MODE = "full"   # Claude Code 手动审批权限时
```

### POPUP_SKIP_TOOLS — 自动放行指定工具（仅 full 模式）

默认自动放行 `Read`、`Glob`、`Grep`、`LS`。  
可添加更多工具：

**macOS**（加入 `~/.zshrc` 或 `~/.bash_profile`）：
```bash
export POPUP_SKIP_TOOLS="Write,Edit,TodoWrite"
```

**Windows**（加入 PowerShell profile）：
```powershell
$env:POPUP_SKIP_TOOLS = "Write,Edit,TodoWrite"
```

## 手动安装

如需手动配置，在 `~/.claude/settings.json` 中添加：

**macOS：**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          { "type": "command", "command": "/绝对路径/cc-push/hooks/permission-popup.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "/绝对路径/cc-push/hooks/stop-notify.sh" }
        ]
      }
    ]
  }
}
```

**Windows：**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          { "type": "command", "command": "powershell -ExecutionPolicy Bypass -NonInteractive -File \"C:\\绝对路径\\cc-push\\hooks\\permission-popup.ps1\"" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "powershell -ExecutionPolicy Bypass -NonInteractive -File \"C:\\绝对路径\\cc-push\\hooks\\stop-notify.ps1\"" }
        ]
      }
    ]
  }
}
```

## 卸载

从 `~/.claude/settings.json` 中删除对应 hook 条目，然后删除克隆目录即可。

## 工作原理

Claude Code 支持 [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)——在特定生命周期事件时执行的 shell 命令：

- **PreToolUse**：任何工具调用前执行；exit `0` 允许，exit `2` 阻止
- **Stop**：Claude 完成任务时执行；exit `0` 正常结束

`cc-push` 安装两个 hook 脚本：

1. `hooks/permission-popup.sh` / `.ps1` — 从 Claude 的 JSON stdin 读取工具名、参数和项目路径，显示 Allow/Deny 对话框
2. `hooks/stop-notify.sh` / `.ps1` — 显示带项目标识的完成通知

## 灵感来源

灵感来自 [claude-permission-popup](https://github.com/Melodymaifafa/claude-permission-popup)（仅支持 macOS，基于 Node.js）。`cc-push` 将其扩展至 Windows，增加了 Stop 通知，且只使用系统内置工具。

## 许可证

MIT
