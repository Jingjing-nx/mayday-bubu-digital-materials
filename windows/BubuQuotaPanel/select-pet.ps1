param(
    [Parameter(Mandatory = $true)]
    [string]$CodexHome
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

$homePath = [IO.Path]::GetFullPath($CodexHome)
$configPath = Join-Path $homePath "config.toml"
New-Item -ItemType Directory -Force -Path $homePath | Out-Null

$configText = ""
if (Test-Path -LiteralPath $configPath) {
    $configText = [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8)
}

$updated = Set-CodexDesktopSettings $configText
Write-Utf8NoBom $configPath $updated

$verified = [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8)
if ($verified -notmatch '(?ms)^\s*\[desktop\].*?^\s*selected-avatar-id\s*=\s*"custom:bubu-office"\s*$') {
    throw "The Bubu pet selection could not be verified in config.toml."
}

Write-Output "Bubu pet selection configured."
