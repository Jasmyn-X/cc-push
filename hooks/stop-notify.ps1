# Stop hook — Windows
# Shows a notification dialog when Claude Code finishes a task.
# Requires user to click OK to dismiss.

param()

Add-Type -AssemblyName System.Windows.Forms

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

# Prevent recursive stop hook execution
if ($data.stop_hook_active) {
    exit 0
}

$projectPath = if ($data.cwd) { $data.cwd } else { "unknown" }
$projectName = [System.IO.Path]::GetFileName($projectPath)
if (-not $projectName) { $projectName = $projectPath }

$message = @"
Project: $projectName
Path:    $projectPath
"@

[System.Windows.Forms.MessageBox]::Show(
    $message,
    "Claude Code — Task Finished",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null

exit 0
