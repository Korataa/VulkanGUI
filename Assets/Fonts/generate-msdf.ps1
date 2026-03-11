param(
    [string]$FontFile = "JetBrainsMono-Regular.ttf",
    [string]$Charset = "32-126",
    [int]$Size = 48,
    [int]$AtlasWidth = 1024,
    [int]$AtlasHeight = 1024,
    [double]$PxRange = 6.0,
    [string]$OutputBase = "JetBrainsMono-msdf"
)

$ErrorActionPreference = "Stop"

$msdfGen = Get-Command msdf-atlas-gen -ErrorAction SilentlyContinue
if (-not $msdfGen) {
    Write-Error "msdf-atlas-gen not found in PATH. Install it first: https://github.com/Chlumsky/msdf-atlas-gen"
}

$fontPath = Join-Path $PSScriptRoot $FontFile
if (-not (Test-Path $fontPath)) {
    Write-Error "Font file not found: $fontPath"
}

$outImage = Join-Path $PSScriptRoot ("$OutputBase.png")
$outJson = Join-Path $PSScriptRoot ("$OutputBase.json")

Write-Host "Generating MSDF atlas..."
Write-Host "  Font: $fontPath"
Write-Host "  Image: $outImage"
Write-Host "  JSON: $outJson"

& msdf-atlas-gen `
    -font "$fontPath" `
    -type msdf `
    -format png `
    -size $Size `
    -pxrange $PxRange `
    -dimensions $AtlasWidth $AtlasHeight `
    -charset $Charset `
    -imageout "$outImage" `
    -json "$outJson"

if ($LASTEXITCODE -ne 0) {
    Write-Error "msdf-atlas-gen failed with exit code $LASTEXITCODE"
}

Write-Host "Done."
