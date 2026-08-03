# PreToolUse hook — Windows
# Shows a custom WPF dialog before Claude Code executes a tool.
# Adapts to system dark/light mode automatically.
#
# Exit 0 = Allow tool to run
# Exit 2 = Deny tool execution
#
# POPUP_MODE:
#   full (default) — popup for all non-skip-listed tools
#   auto           — popup ONLY for AskUserQuestion
#
# POPUP_SKIP_TOOLS: comma-separated extra tool names to auto-allow (full mode only)

param()

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Identify the calling agent from the hook payload. Returns "Claude Code",
# "Codex", "Kimi Code", or "Agent" (unknown). Detection order favours the
# transcript path, which is the most reliable signal, then falls back to
# payload-only fields. Kimi Code is a Codex-family fork, so it is matched on its
# own signals *before* the generic `turn_id` fallback that also flags Codex.
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

# Read JSON from stdin
try {
    $reader = [System.IO.StreamReader]::new(
        [Console]::OpenStandardInput(),
        [System.Text.Encoding]::UTF8
    )
    $inputData = $reader.ReadToEnd()
    $data = $inputData | ConvertFrom-Json
} catch { exit 0 }

$toolName    = if ($data.tool_name) { $data.tool_name } else { "unknown" }
$projectPath = if ($data.cwd)       { $data.cwd }       else { "unknown" }
$toolInput   = $data.tool_input
$popupMode   = if ($env:POPUP_MODE) { $env:POPUP_MODE.ToLower() } else { "full" }

# Identify which agent triggered this hook so the popup is distinguishable.
# Codex payloads carry a `model` (gpt-*), a `turn_id`, and a `.codex` transcript
# path; Claude Code payloads carry `prompt_id`/`effort` and a `.claude` path.
$sourceName = Get-AgentSource $data

# auto mode: only surface AskUserQuestion
if ($popupMode -eq "auto") {
    if ($toolName -ne "AskUserQuestion") { exit 0 }
}

# full mode: skip read-only + user-configured tools
if ($popupMode -ne "auto") {
    $skipSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    @("Read","Glob","Grep","LS") | ForEach-Object { [void]$skipSet.Add($_) }
    if ($env:POPUP_SKIP_TOOLS) {
        $env:POPUP_SKIP_TOOLS -split "," | ForEach-Object {
            $t = $_.Trim(); if ($t) { [void]$skipSet.Add($t) }
        }
    }
    if ($skipSet.Contains($toolName)) { exit 0 }
}

# Prepare params
try { $paramsJson = $toolInput | ConvertTo-Json -Compress -Depth 5 } catch { $paramsJson = "(unable to serialize)" }
if ($null -eq $paramsJson) { $paramsJson = "null" }
if ($paramsJson.Length -gt 300) { $paramsJson = $paramsJson.Substring(0, 297) + "..." }

$projectName = [System.IO.Path]::GetFileName($projectPath)
if (-not $projectName) { $projectName = $projectPath }

# XML-escape for safe embedding in XAML attributes
function xEsc([string]$s) { [System.Security.SecurityElement]::Escape($s) }
$xTool   = xEsc $toolName
$xProjN  = xEsc $projectName
$xProjP  = xEsc $projectPath
$xParams = xEsc $paramsJson

# Detect system dark/light mode
$isDark = $true
try {
    $lv = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -ErrorAction Stop).AppsUseLightTheme
    if ($lv -eq 1) { $isDark = $false }
} catch {}

if ($isDark) {
    $cBg     = "#1C1C1E"; $cSurface = "#2C2C2E"; $cBorder = "#3A3A3C"
    $cTextP  = "#FFFFFF";  $cTextS   = "#8E8E93"
    $cAllow  = "#0A84FF"
    $cDeny   = "#3A3A3C";  $cDenyFg  = "#AEAEB2"
    $cParam  = "#141416"
} else {
    $cBg     = "#F2F2F7"; $cSurface = "#FFFFFF";  $cBorder = "#D1D1D6"
    $cTextP  = "#1C1C1E"; $cTextS   = "#6E6E73"
    $cAllow  = "#0071E3"
    $cDeny   = "#E5E5EA";  $cDenyFg  = "#3A3A3C"
    $cParam  = "#F0F0F3"
}

# Accent colour per source — a glanceable cue when several windows stack up.
switch ($sourceName) {
    "Codex"       { $cAccent = "#10A37F" }  # OpenAI green
    "Claude Code" { $cAccent = "#D97757" }  # Claude clay
    "Kimi Code"   { $cAccent = "#7C5CFF" }  # Kimi violet
    default       { $cAccent = $cTextS }
}
$xSource = xEsc $sourceName

$global:exitCode = 2

# ── AskUserQuestion popup ──────────────────────────────────────────────────────
if ($toolName -eq "AskUserQuestion") {
    $xQuestion = xEsc (if ($data.tool_input.question) { $data.tool_input.question } else { $paramsJson })

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$xSource" Width="400" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" Topmost="True"
        ResizeMode="NoResize" Background="$cBg">
  <Window.Resources>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="$cAllow"/>
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
        <Run Text="  &#183;  Question" Foreground="$cTextS"/>
      </TextBlock>
      <TextBlock Text="$xQuestion" FontFamily="Segoe UI Variable, Segoe UI"
                 FontSize="14" Foreground="$cTextP" TextWrapping="Wrap" Margin="0,0,0,16"/>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
        <TextBlock Text="Project  " FontFamily="Segoe UI Variable, Segoe UI" FontSize="12" Foreground="$cTextS"/>
        <TextBlock Text="$xProjN"  FontFamily="Segoe UI Variable, Segoe UI" FontSize="12" Foreground="$cTextP" FontWeight="SemiBold"/>
      </StackPanel>
      <TextBlock Text="$xProjP" FontFamily="Segoe UI Variable, Segoe UI"
                 FontSize="11" Foreground="$cTextS" TextWrapping="Wrap" Margin="0,0,0,16"/>
      <TextBlock Text="Switch to the $xSource window to answer."
                 FontFamily="Segoe UI Variable, Segoe UI" FontSize="12" Foreground="$cTextS"
                 FontStyle="Italic" Margin="0,0,0,20"/>
      <Button x:Name="BtnOK" Content="OK" Style="{StaticResource Btn}" HorizontalAlignment="Right"/>
    </StackPanel>
  </Border>
</Window>
"@

    $xr  = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $win = [System.Windows.Markup.XamlReader]::Load($xr)
    $win.FindName("BtnOK").Add_Click({ $win.Close() })
    $win.ShowDialog() | Out-Null
    exit 0
}

# ── Permission popup ───────────────────────────────────────────────────────────
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$xSource" Width="420" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" Topmost="True"
        ResizeMode="NoResize" Background="$cBg">
  <Window.Resources>
    <Style x:Key="AllowBtn" TargetType="Button">
      <Setter Property="Background" Value="$cAllow"/>
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
    <Style x:Key="DenyBtn" TargetType="Button">
      <Setter Property="Background" Value="$cDeny"/>
      <Setter Property="Foreground" Value="$cDenyFg"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontFamily" Value="Segoe UI Variable, Segoe UI"/>
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
        <Run Text="  &#183;  Permission" Foreground="$cTextS"/>
      </TextBlock>

      <Border Background="$cSurface" CornerRadius="6" Padding="10,6"
              BorderThickness="1" BorderBrush="$cBorder"
              HorizontalAlignment="Left" Margin="0,0,0,16">
        <TextBlock Text="$xTool" FontFamily="Segoe UI Variable, Segoe UI"
                   FontSize="13" FontWeight="SemiBold" Foreground="$cTextP"/>
      </Border>

      <TextBlock Text="$xProjN" FontFamily="Segoe UI Variable, Segoe UI"
                 FontSize="15" FontWeight="SemiBold" Foreground="$cTextP" Margin="0,0,0,3"/>
      <TextBlock Text="$xProjP" FontFamily="Segoe UI Variable, Segoe UI"
                 FontSize="11" Foreground="$cTextS" TextWrapping="Wrap" Margin="0,0,0,14"/>

      <Border Background="$cParam" CornerRadius="8" Padding="12,10"
              Margin="0,0,0,24" BorderThickness="1" BorderBrush="$cBorder">
        <TextBlock Text="$xParams" FontFamily="Cascadia Code, Consolas, monospace"
                   FontSize="11" Foreground="$cTextS" TextWrapping="Wrap"/>
      </Border>

      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnDeny"  Content="Deny"  Style="{StaticResource DenyBtn}"  Margin="0,0,8,0"/>
        <Button x:Name="BtnAllow" Content="Allow" Style="{StaticResource AllowBtn}"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
"@

$xr  = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$win = [System.Windows.Markup.XamlReader]::Load($xr)

$win.FindName("BtnAllow").Add_Click({ $global:exitCode = 0; $win.Close() })
$win.FindName("BtnDeny").Add_Click({  $global:exitCode = 2; $win.Close() })

$win.ShowDialog() | Out-Null
exit $global:exitCode
