param(
    [switch]$CodexOnlyRelease
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Version = "29"
$StageRoot = Join-Path $Root "build\release"
$FullStage = Join-Path $StageRoot "橙色卜卜-Windows"
$CodexOnlyStage = Join-Path $StageRoot "橙色卜卜-Windows-仅Codex额度"
$FullOutput = Join-Path $Root "dist\Orange-Bubu-Windows-10-11-$Version.zip"
$CodexOnlyOutput = Join-Path $Root "dist\Orange-Bubu-Windows-10-11-Codex-Only-$Version.zip"

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

    $petStage = Join-Path $Stage "pet\bubu-orange"
    New-Item -ItemType Directory -Force -Path $petStage | Out-Null
    @("pet.json", "spritesheet.webp", "validation.json") | ForEach-Object {
        Copy-Item -LiteralPath (Join-Path $Root "shared\pet\bubu-orange\$_") -Destination $petStage
    }
    Copy-Item -LiteralPath (Join-Path $Root "shared\pet\bubu-orange\qa\release-freeze-v29.json") -Destination $petStage
    $previewStage = Join-Path $Stage "preview"
    New-Item -ItemType Directory -Force -Path $previewStage | Out-Null
    @(
        "orange-bubu-static.png",
        "橙色卜卜-左拖回到那一天-宠物动作.gif",
        "橙色卜卜-右拖椅边主唱Live.gif"
    ) | ForEach-Object {
        Copy-Item -LiteralPath (Join-Path $Root "shared\preview\$_") -Destination $previewStage -Force
    }
    Copy-Item -LiteralPath (Join-Path $Root "windows\BubuQuotaPanel") -Destination (Join-Path $Stage "windows") -Recurse
    Copy-Item -Path (Join-Path $Root "windows\package\*") -Destination $Stage -Force
    Copy-Item -LiteralPath (Join-Path $Root "windows\README.md") -Destination (Join-Path $Stage "README.md")
    Copy-Item -LiteralPath (Join-Path $Root "windows\VERSION.txt") -Destination (Join-Path $Stage "VERSION.txt")
    Copy-Item -LiteralPath (Join-Path $Root "LICENSE") -Destination $Stage
    Copy-Item -LiteralPath (Join-Path $Root "ASSET-NOTICE.md") -Destination $Stage
    Copy-Item -LiteralPath (Join-Path $Root "PRIVACY.md") -Destination $Stage
    Copy-Item -LiteralPath (Join-Path $Root "ORANGE-BUBU-PROJECT.txt") -Destination $Stage
    if ($CodexOnly) {
        Copy-Item -LiteralPath (Join-Path $Root "windows\CODEX-ONLY.txt") -Destination (Join-Path $Stage "CODEX-ONLY.txt")
    }

    # A versioned atlas path prevents the desktop app from reusing the previous
    # custom-pet texture after an in-place Windows upgrade.
    # Tie the cache-busting atlas name to the same integer release number used
    # by the installer and compatibility checker.
    $atlasName = "spritesheet-win-$Version.webp"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    foreach ($petDirectory in @(Get-ChildItem -LiteralPath (Join-Path $Stage "pet") -Directory)) {
        $oldAtlas = Join-Path $petDirectory.FullName "spritesheet.webp"
        $manifestPath = Join-Path $petDirectory.FullName "pet.json"
        if (-not (Test-Path -LiteralPath $oldAtlas -PathType Leaf) -or
            -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }

        $newAtlas = Join-Path $petDirectory.FullName $atlasName
        Move-Item -LiteralPath $oldAtlas -Destination $newAtlas -Force

        $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $manifest.spritesheetPath = $atlasName
        [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + "`n", $utf8NoBom)

        $validationPath = Join-Path $petDirectory.FullName "validation.json"
        if (Test-Path -LiteralPath $validationPath) {
            $validation = [IO.File]::ReadAllText($validationPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $validation.file = $atlasName
            [IO.File]::WriteAllText($validationPath, ($validation | ConvertTo-Json -Depth 16) + "`n", $utf8NoBom)
        }
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
