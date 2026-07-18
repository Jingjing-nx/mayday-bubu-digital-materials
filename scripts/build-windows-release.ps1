param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Version = "1.0.0"
$StageRoot = Join-Path $Root "build\release"
$Stage = Join-Path $StageRoot "卜卜-Windows"
$Output = Join-Path $Root "dist\卜卜-Windows-10-11-v$Version.zip"

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

$checksums = Get-ChildItem -LiteralPath $Stage -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($Stage.Length + 1).Replace("\", "/")
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    "$hash  ./$relative"
}
[IO.File]::WriteAllLines((Join-Path $Stage "CHECKSUMS-SHA256.txt"), $checksums, [Text.UTF8Encoding]::new($false))

Compress-Archive -LiteralPath $Stage -DestinationPath $Output -CompressionLevel Optimal
Write-Output $Output
