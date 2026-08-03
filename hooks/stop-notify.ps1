# Stop hook — Windows
# Shows a WPF notification when Claude Code finishes a task.
# Adapts to system dark/light mode automatically.

param()

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Identify the calling agent from the hook payload. Returns "Claude Code",
# "Codex", "Kimi Code", or "Agent" (unknown). Codex sends a `model` (gpt-*),
# `turn_id`, and a `.codex` transcript path; Claude Code sends `prompt_id`/`effort`
# and `.claude`. Kimi Code is a Codex-family fork, matched on its own signals
# *before* the generic `turn_id` fallback so it is not mistaken for Codex.
function Get-AgentSource($d) {
    $tp    = if ($d.transcript_path) { [string]$d.transcript_path } else { "" }
    $model = if ($d.model)           { [string]$d.model }           else { "" }
    $names = $d.PSObject.Properties.Name
    if ($tp -match '(?i)[\\/]\.kimi[\\/]' -or $model -match '(?i)kimi|moonshot') {
        return "Kimi Code"
    }
    if ($tp -match '(?i)[\\/]\.codex[\\/]' -or $model -match '(?i)^gpt' -or ($names -contains 'turn_id')) {
        return "Codex"
    }
    if ($tp -match '(?i)[\\/]\.claude[\\/]' -or ($names -contains 'prompt_id') -or $model -match '(?i)claude') {
        return "Claude Code"
    }
    return "Agent"
}

try {
    $reader = [System.IO.StreamReader]::new(
        [Console]::OpenStandardInput(),
        [System.Text.Encoding]::UTF8
    )
    $inputData = $reader.ReadToEnd()
    $data = $inputData | ConvertFrom-Json
} catch { exit 0 }

if ($data.stop_hook_active) { exit 0 }

$projectPath = if ($data.cwd) { $data.cwd } else { "unknown" }
$projectName = [System.IO.Path]::GetFileName($projectPath)
if (-not $projectName) { $projectName = $projectPath }

$sourceName = Get-AgentSource $data

function xEsc([string]$s) { [System.Security.SecurityElement]::Escape($s) }
$xProjN   = xEsc $projectName
$xProjP   = xEsc $projectPath
$xSource  = xEsc $sourceName

# Detect system dark/light mode
$isDark = $true
try {
    $lv = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -ErrorAction Stop).AppsUseLightTheme
    if ($lv -eq 1) { $isDark = $false }
} catch {}

if ($isDark) {
    $cBg = "#1C1C1E"; $cTextP = "#FFFFFF"; $cTextS = "#8E8E93"; $cBtn = "#0A84FF"
} else {
    $cBg = "#F2F2F7"; $cTextP = "#1C1C1E"; $cTextS = "#6E6E73"; $cBtn = "#0071E3"
}

# Accent colour per source — a glanceable cue when several windows stack up.
switch ($sourceName) {
    "Codex"       { $cAccent = "#10A37F" }  # OpenAI green
    "Claude Code" { $cAccent = "#D97757" }  # Claude clay
    "Kimi Code"   { $cAccent = "#7C5CFF" }  # Kimi violet
    default       { $cAccent = $cTextS }
}

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$xSource" Width="360" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" Topmost="True"
        ResizeMode="NoResize" Background="$cBg">
  <Window.Resources>
    <Style x:Key="OKBtn" TargetType="Button">
      <Setter Property="Background" Value="$cBtn"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontFamily" Value="Segoe UI Variable, Segoe UI"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="24,8"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border Padding="24">
    <StackPanel>
      <TextBlock FontFamily="Segoe UI Variable, Segoe UI" FontSize="11" Margin="0,0,0,16">
        <Run Text="&#9679; $xSource" Foreground="$cAccent" FontWeight="SemiBold"/>
        <Run Text="  &#183;  Task Finished" Foreground="$cTextS"/>
      </TextBlock>
      <TextBlock Text="$xProjN" FontFamily="Segoe UI Variable, Segoe UI"
                 FontSize="15" FontWeight="SemiBold" Foreground="$cTextP" Margin="0,0,0,3"/>
      <TextBlock Text="$xProjP" FontFamily="Segoe UI Variable, Segoe UI"
                 FontSize="11" Foreground="$cTextS" TextWrapping="Wrap" Margin="0,0,0,20"/>
      <Button x:Name="BtnOK" Content="OK" Style="{StaticResource OKBtn}" HorizontalAlignment="Right"/>
    </StackPanel>
  </Border>
</Window>
"@

$xr  = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$win = [System.Windows.Markup.XamlReader]::Load($xr)
$win.FindName("BtnOK").Add_Click({ $win.Close() })
$win.ShowDialog() | Out-Null
exit 0
