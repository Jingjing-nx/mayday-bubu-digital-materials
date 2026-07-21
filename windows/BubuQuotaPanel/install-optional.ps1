param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Set-CodexDesktopSettings([string]$ConfigText) {
    $lines = [Text.RegularExpressions.Regex]::Split($ConfigText, "\r?\n")
    $output = New-Object Collections.Generic.List[string]
    $inDesktop = $false
    $desktopSeen = $false
    $desktopValuesWritten = $false
    $inRoot = $true

    foreach ($line in $lines) {
        if ($line -match '^\s*\[[^\]]+\]') {
            if ($inDesktop -and -not $desktopValuesWritten) {
                [void]$output.Add('selected-avatar-id = "custom:bubu-office"')
                [void]$output.Add('avatar-overlay-mascot-width-px = 163')
                $desktopValuesWritten = $true
            }
            $inDesktop = $line -match '^\s*\[desktop\]\s*(?:#.*)?$'
            if ($inDesktop) {
                $desktopSeen = $true
                $desktopValuesWritten = $false
            }
            $inRoot = $false
            [void]$output.Add($line)
            continue
        }

        if ($inRoot -and $line -match '^\s*(selected-avatar-id|avatar-overlay-mascot-width-px)\s*=') {
            continue
        }
        if ($inDesktop -and $line -match '^\s*(selected-avatar-id|avatar-overlay-mascot-width-px)\s*=') {
            continue
        }
        [void]$output.Add($line)
    }

    if ($inDesktop -and -not $desktopValuesWritten) {
        [void]$output.Add('selected-avatar-id = "custom:bubu-office"')
        [void]$output.Add('avatar-overlay-mascot-width-px = 163')
    } elseif (-not $desktopSeen) {
        if ($output.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
            [void]$output.Add('')
        }
        [void]$output.Add('[desktop]')
        [void]$output.Add('selected-avatar-id = "custom:bubu-office"')
        [void]$output.Add('avatar-overlay-mascot-width-px = 163')
    }

    return ($output -join "`r`n").TrimEnd() + "`r`n"
}

try {
    if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
        throw "PowerShell is restricted by this PC's policy. The optional panel cannot run."
    }

    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop

    $rootPath = [IO.Path]::GetFullPath($Root)
    $panelSource = Join-Path $rootPath "windows"
    $installDirectory = Join-Path $env:LOCALAPPDATA "BubuPet"
    $codexOnlySource = Join-Path $rootPath "CODEX-ONLY.txt"
    $marketPricesEnabled = -not (Test-Path -LiteralPath $codexOnlySource)
    $expectedPanelHeight = if ($marketPricesEnabled) { 183 } else { 139 }
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
    $configPath = Join-Path $codexHome "config.toml"

    foreach ($required in @("BubuQuotaPanel.ps1", "StartBubuPanel.vbs", "StartBubuPanel.cmd", "quota-panel-background.png")) {
        if (-not (Test-Path -LiteralPath (Join-Path $panelSource $required))) {
            throw "Missing optional panel file: $required"
        }
    }

    $oldHealthPath = Join-Path $installDirectory "panel-health.json"
    if (Test-Path -LiteralPath $oldHealthPath) {
        try {
            $oldHealth = [IO.File]::ReadAllText($oldHealthPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $healthAge = [DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($oldHealthPath)
            $oldProcess = Get-Process -Id ([int]$oldHealth.processId) -ErrorAction SilentlyContinue
            if ($oldProcess -and $oldProcess.ProcessName -match "powershell|pwsh" -and
                $healthAge.TotalMinutes -lt 2) {
                Stop-Process -Id $oldProcess.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
            }
        } catch {
        }
    }

    try {
        Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object { $_.CommandLine -like "*BubuQuotaPanel.ps1*" } |
            ForEach-Object {
                Invoke-CimMethod -InputObject $_ -MethodName Terminate -ErrorAction SilentlyContinue | Out-Null
            }
    } catch {
        Write-Warning "Could not stop an older panel instance. Installation will continue."
    }

    New-Item -ItemType Directory -Force -Path $installDirectory | Out-Null
    Copy-Item -LiteralPath (Join-Path $panelSource "BubuQuotaPanel.ps1") -Destination $installDirectory -Force
    Copy-Item -LiteralPath (Join-Path $panelSource "StartBubuPanel.vbs") -Destination $installDirectory -Force
    Copy-Item -LiteralPath (Join-Path $panelSource "StartBubuPanel.cmd") -Destination $installDirectory -Force
    Copy-Item -LiteralPath (Join-Path $panelSource "quota-panel-background.png") -Destination $installDirectory -Force
    $installedCodexOnlyMarker = Join-Path $installDirectory "CODEX-ONLY.txt"
    if ($marketPricesEnabled) {
        Remove-Item -LiteralPath $installedCodexOnlyMarker -Force -ErrorAction SilentlyContinue
    } else {
        Copy-Item -LiteralPath $codexOnlySource -Destination $installedCodexOnlyMarker -Force
    }

    try {
        New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
        $configText = ""
        if (Test-Path -LiteralPath $configPath) {
            $configText = [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8)
        }

        $configText = Set-CodexDesktopSettings $configText
        Write-Utf8NoBom $configPath $configText
    } catch {
        Write-Warning "Bubu was installed, but could not be selected automatically. Select it manually in the pet picker."
    }

    $launcher = Join-Path $installDirectory "StartBubuPanel.vbs"
    $wscript = Join-Path $env:SystemRoot "System32\wscript.exe"
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $runCommand = '"' + $wscript + '" "' + $launcher + '"'

    $startupConfigured = $false
    try {
        New-Item -Path $runKey -Force | Out-Null
        New-ItemProperty -Path $runKey -Name "BubuQuotaPanel" -Value $runCommand -PropertyType String -Force | Out-Null
        $startupConfigured = $true
    } catch {
        Write-Warning "Registry startup is blocked; trying the Startup folder fallback."
    }

    $legacyShortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "卜卜额度面板.lnk"
    Remove-Item -LiteralPath $legacyShortcut -Force -ErrorAction SilentlyContinue
    $startupDirectory = [Environment]::GetFolderPath("Startup")
    $startupCommand = Join-Path $startupDirectory "BubuQuotaPanel.cmd"
    try {
        New-Item -ItemType Directory -Force -Path $startupDirectory | Out-Null
        Copy-Item -LiteralPath (Join-Path $panelSource "StartBubuPanel.cmd") -Destination $startupCommand -Force
        $startupConfigured = $true
    } catch {
        Write-Warning "Startup-folder fallback is blocked."
    }
    if (-not $startupConfigured) {
        Write-Warning "Automatic startup could not be configured. Use the package's panel repair command after signing in."
    }

    Remove-Item -LiteralPath $oldHealthPath -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath $wscript -ArgumentList ('"' + $launcher + '"')

    $panelStarted = $false
    $healthySamples = 0
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 250
        if (Test-Path -LiteralPath $oldHealthPath) {
            try {
                $health = [IO.File]::ReadAllText($oldHealthPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
                $healthProcess = Get-Process -Id ([int]$health.processId) -ErrorAction SilentlyContinue
                $healthAge = [DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($oldHealthPath)
                if ($health.version -eq "1.1.4" -and
                    [bool]$health.marketPricesEnabled -eq $marketPricesEnabled -and
                    [int]$health.panelHeightPoints -eq $expectedPanelHeight -and
                    $healthProcess -and
                    $healthProcess.ProcessName -match "powershell|pwsh" -and
                    $healthAge.TotalSeconds -lt 10) {
                    $healthySamples++
                    if ($healthySamples -ge 4) {
                        $panelStarted = $true
                        break
                    }
                } else {
                    $healthySamples = 0
                }
            } catch {
                $healthySamples = 0
            }
        }
    }
    if (-not $panelStarted) {
        throw "The quota panel did not report a healthy startup. Check panel.log in $installDirectory."
    }

    Write-Output "Optional panel installation completed and health check passed."
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
