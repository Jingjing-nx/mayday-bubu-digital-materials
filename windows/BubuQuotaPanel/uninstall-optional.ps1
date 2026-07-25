$ErrorActionPreference = "SilentlyContinue"

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$configPath = Join-Path $codexHome "config.toml"
$legacyShortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "橙色卜卜额度面板.lnk"
$startupCommand = Join-Path ([Environment]::GetFolderPath("Startup")) "OrangeBubuQuotaPanel.cmd"

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*OrangeBubuPet*BubuQuotaPanel.ps1*" } |
    ForEach-Object {
        Invoke-CimMethod -InputObject $_ -MethodName Terminate -ErrorAction SilentlyContinue | Out-Null
    }

Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OrangeBubuQuotaPanel" -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $legacyShortcut -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $startupCommand -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $configPath) {
    try {
        $configText = [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8)
        $configText = [Text.RegularExpressions.Regex]::Replace(
            $configText,
            '(?m)^\s*selected-avatar-id\s*=\s*"custom:bubu-orange"\s*\r?\n?',
            ''
        )
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($configPath, $configText, $encoding)
    } catch {
    }
}

exit 0
