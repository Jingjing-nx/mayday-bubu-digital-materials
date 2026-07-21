param(
    [switch]$CodexOnlyRelease
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Version = "15"
$StageRoot = Join-Path $Root "build\release"
$FullStage = Join-Path $StageRoot "卜卜-Windows"
$CodexOnlyStage = Join-Path $StageRoot "卜卜-Windows-仅Codex额度"
$FullOutput = Join-Path $Root "dist\Mayday-Bubu-Windows-10-11-$Version.zip"
$CodexOnlyOutput = Join-Path $Root "dist\Mayday-Bubu-Windows-10-11-Codex-Only-$Version.zip"

function New-ReleasePackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Stage,
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [bool]$CodexOnly
    )

    Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Output -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Stage | Out-Null

    Copy-Item -LiteralPath (Join-Path $Root "shared\pet") -Destination $Stage -Recurse
    Copy-Item -LiteralPath (Join-Path $Root "shared\preview") -Destination $Stage -Recurse
    Copy-Item -LiteralPath (Join-Path $Root "windows\BubuQuotaPanel") -Destination (Join-Path $Stage "windows") -Recurse
    Copy-Item -Path (Join-Path $Root "windows\package\*") -Destination $Stage -Force
    Copy-Item -LiteralPath (Join-Path $Root "windows\README.md") -Destination (Join-Path $Stage "README.md")
    Copy-Item -LiteralPath (Join-Path $Root "windows\VERSION.txt") -Destination (Join-Path $Stage "VERSION.txt")
    Copy-Item -LiteralPath (Join-Path $Root "LICENSE") -Destination $Stage
    Copy-Item -LiteralPath (Join-Path $Root "ASSET-NOTICE.md") -Destination $Stage
    Copy-Item -LiteralPath (Join-Path $Root "PRIVACY.md") -Destination $Stage
    if ($CodexOnly) {
        Copy-Item -LiteralPath (Join-Path $Root "windows\CODEX-ONLY.txt") -Destination (Join-Path $Stage "CODEX-ONLY.txt")
    }

    # A versioned atlas path prevents the desktop app from reusing the previous
    # custom-pet texture after an in-place Windows upgrade.
    $petDirectory = Join-Path $Stage "pet\bubu-office"
    $oldAtlas = Join-Path $petDirectory "spritesheet.webp"
    # Tie the cache-busting atlas name to the same integer release number used
    # by the installer and compatibility checker.
    $atlasName = "spritesheet-win-$Version.webp"
    $newAtlas = Join-Path $petDirectory $atlasName
    Move-Item -LiteralPath $oldAtlas -Destination $newAtlas -Force

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $manifestPath = Join-Path $petDirectory "pet.json"
    $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $manifest.spritesheetPath = $atlasName
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + "`n", $utf8NoBom)

    $validationPath = Join-Path $petDirectory "validation.json"
    if (Test-Path -LiteralPath $validationPath) {
        $validation = [IO.File]::ReadAllText($validationPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $validation.file = $atlasName
        [IO.File]::WriteAllText($validationPath, ($validation | ConvertTo-Json -Depth 16) + "`n", $utf8NoBom)
    }

    $checksums = Get-ChildItem -LiteralPath $Stage -File -Recurse | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($Stage.Length + 1).Replace("\", "/")
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
        "$hash  ./$relative"
    }
    [IO.File]::WriteAllLines((Join-Path $Stage "CHECKSUMS-SHA256.txt"), $checksums, [Text.UTF8Encoding]::new($false))

    Compress-Archive -LiteralPath $Stage -DestinationPath $Output -CompressionLevel Optimal
    Write-Output $Output
}

if (-not $CodexOnlyRelease) {
    New-ReleasePackage -Stage $FullStage -Output $FullOutput -CodexOnly $false
}
New-ReleasePackage -Stage $CodexOnlyStage -Output $CodexOnlyOutput -CodexOnly $true
