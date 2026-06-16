# Install cc-push hooks for Windows
# Adds PreToolUse and Stop hooks to %USERPROFILE%\.claude\settings.json
#
# Run with:
#   powershell -ExecutionPolicy Bypass -File install.ps1

param(
    [string]$SettingsFile = (Join-Path $env:USERPROFILE ".claude\settings.json")
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$hooksDir  = Join-Path $scriptDir "hooks"

Write-Host "Installing cc-push..."
Write-Host ""

# Resolve absolute paths
$popupScript  = Resolve-Path (Join-Path $hooksDir "permission-popup.ps1") -ErrorAction SilentlyContinue
$notifyScript = Resolve-Path (Join-Path $hooksDir "stop-notify.ps1") -ErrorAction SilentlyContinue

if (-not $popupScript -or -not $notifyScript) {
    Write-Host "Error: hook scripts not found in $hooksDir"
    exit 1
}

$popupCmd  = "powershell -ExecutionPolicy Bypass -NonInteractive -File `"$popupScript`""
$notifyCmd = "powershell -ExecutionPolicy Bypass -NonInteractive -File `"$notifyScript`""

# Ensure .claude directory exists
$claudeDir = Split-Path -Parent $SettingsFile
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

# Load existing settings or start fresh
if (Test-Path $SettingsFile) {
    try {
        $raw      = Get-Content $SettingsFile -Raw -Encoding UTF8
        $settings = $raw | ConvertFrom-Json
    } catch {
        Write-Host "Warning: could not parse existing settings.json — starting fresh."
        $settings = [PSCustomObject]@{}
    }
} else {
    $settings = [PSCustomObject]@{}
}

# Ensure hooks object exists
if (-not ($settings.PSObject.Properties.Name -contains "hooks")) {
    $settings | Add-Member -MemberType NoteProperty -Name "hooks" -Value ([PSCustomObject]@{})
}

# Helper: return property as array
function Get-HooksArray {
    param($obj, [string]$key)
    if ($obj.PSObject.Properties.Name -contains $key) {
        return @($obj.$key)
    }
    return @()
}

# Helper: check if an entry's inner hooks array already contains our command
function Has-OurCommand {
    param($entry, [string]$cmd)
    if (-not ($entry.PSObject.Properties.Name -contains "hooks")) { return $false }
    foreach ($h in @($entry.hooks)) {
        if ($h.command -eq $cmd) { return $true }
    }
    return $false
}

# PreToolUse — remove stale entry, then append
$preHooks = Get-HooksArray $settings.hooks "PreToolUse" |
    Where-Object { -not (Has-OurCommand $_ $popupCmd) }

$newPreEntry = [PSCustomObject]@{
    matcher = ".*"
    hooks   = @(
        [PSCustomObject]@{
            type    = "command"
            command = $popupCmd
        }
    )
}
$allPre = @($preHooks) + @($newPreEntry)

if ($settings.hooks.PSObject.Properties.Name -contains "PreToolUse") {
    $settings.hooks.PreToolUse = $allPre
} else {
    $settings.hooks | Add-Member -MemberType NoteProperty -Name "PreToolUse" -Value $allPre
}

# Stop — remove stale entry, then append
$stopHooks = Get-HooksArray $settings.hooks "Stop" |
    Where-Object { -not (Has-OurCommand $_ $notifyCmd) }

$newStopEntry = [PSCustomObject]@{
    hooks = @(
        [PSCustomObject]@{
            type    = "command"
            command = $notifyCmd
        }
    )
}
$allStop = @($stopHooks) + @($newStopEntry)

if ($settings.hooks.PSObject.Properties.Name -contains "Stop") {
    $settings.hooks.Stop = $allStop
} else {
    $settings.hooks | Add-Member -MemberType NoteProperty -Name "Stop" -Value $allStop
}

# Write back
$settings | ConvertTo-Json -Depth 10 | Out-File $SettingsFile -Encoding UTF8

Write-Host "Updated: $SettingsFile"
Write-Host ""
Write-Host "Done! Restart Claude Code for hooks to take effect."
Write-Host ""
Write-Host "Optional — auto-allow additional tools (comma-separated):"
Write-Host '  $env:POPUP_SKIP_TOOLS = "Write,Edit,TodoWrite"'
Write-Host "  Add to your PowerShell profile to persist."
