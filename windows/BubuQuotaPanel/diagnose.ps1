param(
    [Parameter(Mandatory = $true)]
    [string]$Report,
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "SilentlyContinue"

function Redact-Text([string]$text) {
    $safeText = [string]$text
    foreach ($privatePath in @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, $env:CODEX_HOME, $Root)) {
        if (-not [string]::IsNullOrWhiteSpace($privatePath)) {
            $safeText = $safeText.Replace($privatePath, "<redacted-path>")
        }
    }
    $safeText = [Text.RegularExpressions.Regex]::Replace(
        $safeText,
        '(?i)[A-Z]:\\Users\\[^\\\s"'']+',
        '<redacted-user-path>'
    )
    $safeText = [Text.RegularExpressions.Regex]::Replace(
        $safeText,
        '(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
        '<redacted-email>'
    )
    return [Text.RegularExpressions.Regex]::Replace(
        $safeText,
        '(?i)(?:ghp_|github_pat_|sk-)[A-Z0-9_-]+',
        '<redacted-token>'
    )
}

function Add-Report([string]$text) {
    Add-Content -LiteralPath $Report -Value (Redact-Text $text) -Encoding UTF8
}

Add-Report ""
Add-Report "=== PowerShell ==="
Add-Report ("Version: " + $PSVersionTable.PSVersion)
Add-Report ("LanguageMode: " + $ExecutionContext.SessionState.LanguageMode)
Add-Report ("ExecutionPolicy: " + (Get-ExecutionPolicy -List | Out-String).Trim())

$installDirectory = Join-Path $env:LOCALAPPDATA "BubuPet"
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$statePath = Join-Path $codexHome ".codex-global-state.json"
$statePaths = @(
    $statePath,
    (Join-Path (Join-Path $env:USERPROFILE ".codex") ".codex-global-state.json"),
    (Join-Path (Join-Path $env:APPDATA "Codex") ".codex-global-state.json"),
    (Join-Path (Join-Path $env:LOCALAPPDATA "Codex") ".codex-global-state.json"),
    (Join-Path (Join-Path $env:APPDATA "OpenAI\Codex") ".codex-global-state.json"),
    (Join-Path (Join-Path $env:LOCALAPPDATA "OpenAI\Codex") ".codex-global-state.json")
) | Select-Object -Unique

Add-Report ""
Add-Report "=== Installed panel ==="
foreach ($name in @("BubuQuotaPanel.ps1", "StartBubuPanel.vbs", "StartBubuPanel.cmd", "quota-panel-background.png", "task-running-icon.png", "task-waiting-icon.png", "task-completed-icon.png", "task-failed-icon.png")) {
    $path = Join-Path $installDirectory $name
    Add-Report ($name + ": " + $(if (Test-Path -LiteralPath $path) { "OK" } else { "MISSING" }))
}
$codexOnlyMarker = Join-Path $installDirectory "CODEX-ONLY.txt"
Add-Report ("Panel variant: " + $(if (Test-Path -LiteralPath $codexOnlyMarker) { "CODEX-ONLY" } else { "FULL" }))

Add-Report ""
Add-Report "=== Startup ==="
$runValue = (Get-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "BubuQuotaPanel").BubuQuotaPanel
Add-Report ("Registry Run: " + $(if ($runValue) { "CONFIGURED" } else { "MISSING" }))
$startupCommand = Join-Path ([Environment]::GetFolderPath("Startup")) "BubuQuotaPanel.cmd"
Add-Report ("Startup folder command: " + $(if (Test-Path -LiteralPath $startupCommand) { "OK" } else { "MISSING" }))

Add-Report ""
Add-Report "=== Health ==="
$healthPath = Join-Path $installDirectory "panel-health.json"
if (Test-Path -LiteralPath $healthPath) {
    Add-Report ([IO.File]::ReadAllText($healthPath, [Text.Encoding]::UTF8))
    Add-Report ("Health file age seconds: " + [Math]::Round(([DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($healthPath)).TotalSeconds, 1))
} else {
    Add-Report "panel-health.json: MISSING"
}

Add-Report ""
Add-Report "=== Overlay state (redacted) ==="
$matchedStatePath = $null
$container = $null
$candidateIndex = 0
foreach ($candidateStatePath in $statePaths) {
    $candidateIndex++
    Add-Report ("State candidate #" + $candidateIndex + " = " +
        $(if (Test-Path -LiteralPath $candidateStatePath) { "found" } else { "not found" }))
    if ($container -or -not (Test-Path -LiteralPath $candidateStatePath)) { continue }
    try {
        $state = [IO.File]::ReadAllText($candidateStatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $containers = @($state, $state.'electron-persisted-atom-state', $state.state, $state.settings)
        $container = $containers | Where-Object { $_ -and $_.'electron-avatar-overlay-bounds' } | Select-Object -First 1
        if ($container) { $matchedStatePath = $candidateStatePath }
    } catch {
        Add-Report ("State parse error: " + $_.Exception.Message)
    }
}
if ($container) {
    Add-Report "Selected state source: available"
    $bounds = $container.'electron-avatar-overlay-bounds'
    Add-Report ("Open: " + $container.'electron-avatar-overlay-open')
    Add-Report ("Bounds: x=" + $bounds.x + " y=" + $bounds.y + " width=" + $bounds.width + " height=" + $bounds.height)
    if ($bounds.mascot) {
        Add-Report ("Mascot: left=" + $bounds.mascot.left + " top=" + $bounds.mascot.top + " width=" + $bounds.mascot.width + " height=" + $bounds.mascot.height)
    } else {
        Add-Report "Mascot: MISSING (fallback positioning will be used)"
    }
    if ($bounds.anchor) {
        Add-Report ("Anchor: x=" + $bounds.anchor.x + " y=" + $bounds.anchor.y + " width=" + $bounds.anchor.width + " height=" + $bounds.anchor.height)
    }
    Add-Report ("DisplayId: " + $bounds.displayId + " placement=" + $bounds.placement)
} else {
    Add-Report "Overlay bounds: MISSING (native heuristic fallback will be used)"
}

Add-Report ""
Add-Report "=== Codex executable candidates ==="
$command = Get-Command codex.exe, codex.cmd, codex -ErrorAction SilentlyContinue | Select-Object -First 1
Add-Report ("PATH command: " + $(if ($command) { "FOUND" } else { "NOT FOUND" }))
$candidateIndex = 0
foreach ($candidate in @(
    (Join-Path $env:APPDATA "npm\codex.cmd"),
    (Join-Path $codexHome "packages\standalone\current\bin\codex.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\ChatGPT\resources\codex.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Codex\resources\codex.exe")
)) {
    $candidateIndex++
    Add-Report ("Candidate #" + $candidateIndex + ": " + $(if (Test-Path -LiteralPath $candidate) { "OK" } else { "not found" }))
}

Add-Report ""
Add-Report "=== Related processes ==="
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match "ChatGPT|Codex|OpenAI|powershell|pwsh" } |
    ForEach-Object { Add-Report ($_.ProcessName + " pid=" + $_.Id) }

foreach ($logName in @("panel.log", "panel-launcher.log")) {
    Add-Report ""
    Add-Report ("=== " + $logName + " (last 80 lines) ===")
    $logPath = Join-Path $installDirectory $logName
    if (Test-Path -LiteralPath $logPath) {
        Get-Content -LiteralPath $logPath -Tail 80 | ForEach-Object { Add-Report $_ }
    } else {
        Add-Report "MISSING"
    }
}

exit 0
