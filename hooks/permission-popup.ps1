# PreToolUse hook — Windows
# Shows a native dialog before Claude Code executes a tool.
#
# Exit 0 = Allow tool to run
# Exit 2 = Deny tool execution
#
# POPUP_MODE:
#   full (default) — popup for all non-skip-listed tools
#   auto           — popup ONLY for AskUserQuestion (mirrors Claude Code auto mode:
#                    permissions auto-approved, but user questions still surface)
#
# POPUP_SKIP_TOOLS: comma-separated extra tool names to auto-allow (any mode)
# Default always-skip: Read,Glob,Grep,LS

param()

Add-Type -AssemblyName System.Windows.Forms

# Read JSON from stdin (Claude Code pipes it here)
try {
    $reader = [System.IO.StreamReader]::new(
        [Console]::OpenStandardInput(),
        [System.Text.Encoding]::UTF8
    )
    $inputData = $reader.ReadToEnd()
    $data = $inputData | ConvertFrom-Json
} catch {
    exit 0
}

$toolName    = if ($data.tool_name) { $data.tool_name } else { "unknown" }
$projectPath = if ($data.cwd)       { $data.cwd }       else { "unknown" }
$toolInput   = $data.tool_input
$popupMode   = if ($env:POPUP_MODE) { $env:POPUP_MODE.ToLower() } else { "full" }

# --- auto mode: only surface AskUserQuestion ---
if ($popupMode -eq "auto") {
    if ($toolName -ne "AskUserQuestion") { exit 0 }
    # Fall through to show the question popup below
}

# --- full mode: skip read-only + user-configured tools ---
if ($popupMode -ne "auto") {
    $skipSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    @("Read","Glob","Grep","LS") | ForEach-Object { [void]$skipSet.Add($_) }

    $envSkip = $env:POPUP_SKIP_TOOLS
    if ($envSkip) {
        $envSkip -split "," | ForEach-Object {
            $t = $_.Trim()
            if ($t) { [void]$skipSet.Add($t) }
        }
    }

    if ($skipSet.Contains($toolName)) { exit 0 }
}

# Prepare display text
try {
    $paramsJson = $toolInput | ConvertTo-Json -Compress -Depth 5
} catch {
    $paramsJson = "(unable to serialize)"
}
if ($null -eq $paramsJson) { $paramsJson = "null" }
if ($paramsJson.Length -gt 200) {
    $paramsJson = $paramsJson.Substring(0, 197) + "..."
}

$projectName = [System.IO.Path]::GetFileName($projectPath)
if (-not $projectName) { $projectName = $projectPath }

if ($toolName -eq "AskUserQuestion") {
    # Show the actual question content, not raw JSON
    $questionText = if ($data.tool_input.question) { $data.tool_input.question } else { $paramsJson }
    $message = @"
Claude is asking you a question:

$questionText

Project: $projectName
Path:    $projectPath

Switch to the Claude Code window to answer.
"@
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        "Claude Code — Question",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit 0
}

$message = @"
Tool:    $toolName
Project: $projectName
Path:    $projectPath

Params:  $paramsJson

[YES] Allow     [NO] Deny
"@

$result = [System.Windows.Forms.MessageBox]::Show(
    $message,
    "Claude Code Permission",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
    exit 0
} else {
    Write-Output "Permission denied by user."
    exit 2
}
