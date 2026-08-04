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
    $selectedAvatarId = "custom:bubu-orange"
    $selectionLine = 'selected-avatar-id = "' + $selectedAvatarId + '"'
    $lines = [Text.RegularExpressions.Regex]::Split($ConfigText, "\r?\n")
    $output = New-Object Collections.Generic.List[string]
    $inDesktop = $false
    $desktopSeen = $false
    $desktopValuesWritten = $false
    $inRoot = $true

    foreach ($line in $lines) {
        if ($line -match '^\s*\[[^\]]+\]') {
            if ($inDesktop -and -not $desktopValuesWritten) {
                [void]$output.Add($selectionLine)
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
        [void]$output.Add($selectionLine)
        [void]$output.Add('avatar-overlay-mascot-width-px = 163')
    } elseif (-not $desktopSeen) {
        if ($output.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
            [void]$output.Add('')
        }
        [void]$output.Add('[desktop]')
        [void]$output.Add($selectionLine)
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
    $isUltimatePackage = Test-Path -LiteralPath (Join-Path $rootPath "ULTIMATE.txt") -PathType Leaf
    $installDirectory = Join-Path $env:LOCALAPPDATA $(if ($isUltimatePackage) {
        "OrangeBubuUltimate"
    } else {
        "OrangeBubuPet"
    })
    $runValueName = if ($isUltimatePackage) { "OrangeBubuUltimatePanel" } else { "OrangeBubuQuotaPanel" }
    $startupFileName = $runValueName + ".cmd"
    $legacyRunValueName = "OrangeBubuQuotaPanel"
    $legacyStartupFileName = "OrangeBubuQuotaPanel.cmd"
    $vocabularySource = @(
        (Join-Path $rootPath "pet\bubu-orange\vocabulary-web3-3000.json"),
        (Join-Path $rootPath "shared\pet\bubu-orange\vocabulary-web3-3000.json")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    $vocabularyRoot = Join-Path $env:APPDATA "OrangeBubuQuotaPanel"
    $vocabularyDestination = Join-Path $vocabularyRoot "vocabulary.json"
    $codexOnlySource = Join-Path $rootPath "CODEX-ONLY.txt"
    $marketPricesEnabled = -not (Test-Path -LiteralPath $codexOnlySource)
    $expectedPanelHeight = if ($marketPricesEnabled) { 75 } else { 53 }
    # This is the panel runtime build number, distinct from the Ultimate
    # package's release number.  Comparing it to the package number made a
    # healthy panel appear as a failed installation.
    $expectedPanelVersion = "37"
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
    $configPath = Join-Path $codexHome "config.toml"

    foreach ($required in @("BubuQuotaPanel.ps1", "StartBubuPanel.cmd", "quota-panel-background.png", "task-running-icon.png", "task-running-badge.gif", "task-waiting-icon.png", "task-completed-icon.png", "task-failed-icon.png", "Assets\Lightstick\lightstick-unlit.png", "Assets\Airplane\quota-airplane-material.png")) {
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
            Where-Object {
                $_.CommandLine -and $_.CommandLine -match
                    '(?i)OrangeBubu(?:Pet|Ultimate).*BubuQuotaPanel\.ps1'
            } |
            ForEach-Object {
                Invoke-CimMethod -InputObject $_ -MethodName Terminate -ErrorAction SilentlyContinue | Out-Null
            }
    } catch {
        Write-Warning "Could not stop an older panel instance. Installation will continue."
    }

    New-Item -ItemType Directory -Force -Path $installDirectory | Out-Null
    Copy-Item -LiteralPath (Join-Path $panelSource "BubuQuotaPanel.ps1") -Destination $installDirectory -Force
    Copy-Item -LiteralPath (Join-Path $panelSource "StartBubuPanel.cmd") -Destination $installDirectory -Force
    # Old packages installed a VBS trampoline here.  Remove it during every
    # upgrade so a stale Run entry can never raise a Windows Script Host error.
    Remove-Item -LiteralPath (Join-Path $installDirectory "StartBubuPanel.vbs") -Force -ErrorAction SilentlyContinue
    $installedUltimateMarker = Join-Path $installDirectory "ULTIMATE.txt"
    if ($isUltimatePackage) {
        Copy-Item -LiteralPath (Join-Path $rootPath "ULTIMATE.txt") -Destination $installedUltimateMarker -Force
    } else {
        Remove-Item -LiteralPath $installedUltimateMarker -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath (Join-Path $panelSource "quota-panel-background.png") -Destination $installDirectory -Force
    Copy-Item -LiteralPath (Join-Path $panelSource "task-completed-icon.png") -Destination $installDirectory -Force
    Copy-Item -LiteralPath (Join-Path $panelSource "task-running-icon.png") -Destination $installDirectory -Force
    Copy-Item -LiteralPath (Join-Path $panelSource "task-running-badge.gif") -Destination $installDirectory -Force
    Copy-Item -LiteralPath (Join-Path $panelSource "task-waiting-icon.png") -Destination $installDirectory -Force
    Copy-Item -LiteralPath (Join-Path $panelSource "task-failed-icon.png") -Destination $installDirectory -Force
    # These high-resolution material layers are runtime assets, not preview
    # files. Copying the full tree prevents upgrades from losing the airplane,
    # lightstick, or the Ultimate package's local music track.
    Copy-Item -LiteralPath (Join-Path $panelSource "Assets") -Destination (Join-Path $installDirectory "Assets") -Recurse -Force
    if ($vocabularySource -and -not (Test-Path -LiteralPath $vocabularyDestination -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path $vocabularyRoot | Out-Null
        Copy-Item -LiteralPath $vocabularySource -Destination $vocabularyDestination -Force
    }
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

    $panelScript = Join-Path $installDirectory "BubuQuotaPanel.ps1"
    $powerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
        $powerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\PowerShell.exe"
    }
    if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
        throw "Windows PowerShell executable was not found."
    }
    $powerShellArguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $panelScript + '"'
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $runCommand = '"' + $powerShell + '" ' + $powerShellArguments

    $startupConfigured = $false
    try {
        New-Item -Path $runKey -Force | Out-Null
        if ($isUltimatePackage) {
            # The old common value launches the VBS-based runtime.  Retire it
            # before installing the Ultimate-only, PowerShell-native launcher.
            Remove-ItemProperty -Path $runKey -Name $legacyRunValueName -ErrorAction SilentlyContinue
        }
        New-ItemProperty -Path $runKey -Name $runValueName -Value $runCommand -PropertyType String -Force | Out-Null
        $startupConfigured = $true
    } catch {
        Write-Warning "Registry startup is blocked; trying the Startup folder fallback."
    }

    $legacyShortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "橙色卜卜额度面板.lnk"
    Remove-Item -LiteralPath $legacyShortcut -Force -ErrorAction SilentlyContinue
    $startupDirectory = [Environment]::GetFolderPath("Startup")
    if ($isUltimatePackage) {
        Remove-Item -LiteralPath (Join-Path $startupDirectory $legacyStartupFileName) -Force -ErrorAction SilentlyContinue
    }
    $startupCommand = Join-Path $startupDirectory $startupFileName
    Remove-Item -LiteralPath $startupCommand -Force -ErrorAction SilentlyContinue
    if (-not $startupConfigured) {
        try {
            New-Item -ItemType Directory -Force -Path $startupDirectory | Out-Null
            $startupContent = '@echo off' + "`r`n" +
                'start "" /b "' + $powerShell + '" ' + $powerShellArguments + "`r`n" +
                'exit /b 0' + "`r`n"
            Write-Utf8NoBom $startupCommand $startupContent
            $startupConfigured = $true
        } catch {
            Write-Warning "Startup-folder fallback is blocked."
        }
    }
    if (-not $startupConfigured) {
        Write-Warning "Automatic startup could not be configured. Use the package's panel repair command after signing in."
    }

    Remove-Item -LiteralPath $oldHealthPath -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath $powerShell -ArgumentList $powerShellArguments -WindowStyle Hidden

    $panelStarted = $false
    $healthySamples = 0
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 250
        if (Test-Path -LiteralPath $oldHealthPath) {
            try {
                $health = [IO.File]::ReadAllText($oldHealthPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
                $healthProcess = Get-Process -Id ([int]$health.processId) -ErrorAction SilentlyContinue
                $healthAge = [DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($oldHealthPath)
                if ($health.version -eq $expectedPanelVersion -and
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
