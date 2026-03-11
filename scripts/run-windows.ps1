param(
    [switch]$SkipBuild,
    [switch]$NoRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot
Set-Location ..

if (-not $SkipBuild) {
    Write-Host "Building DeckRPG..." -ForegroundColor Cyan
    swift build -c debug
}

$binPath = (swift build --show-bin-path).Trim()
if (-not (Test-Path $binPath)) {
    throw "Build output path not found: $binPath"
}

$exePath = Join-Path $binPath "DeckRPG.exe"
if (-not (Test-Path $exePath)) {
    throw "Executable not found: $exePath"
}

$sdlCandidates = @(
    $env:SDL3_DLL_PATH,
    "C:\vcpkg\installed\x64-windows\bin\SDL3.dll"
) | Where-Object { $_ -and $_.Trim().Length -gt 0 }

$sdlSource = $sdlCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $sdlSource) {
    throw "SDL3.dll not found. Set SDL3_DLL_PATH or install via vcpkg to C:\vcpkg\installed\x64-windows\bin\SDL3.dll"
}

$sdlTarget = Join-Path $binPath "SDL3.dll"
Copy-Item -Path $sdlSource -Destination $sdlTarget -Force
Write-Host "Staged SDL3.dll: $sdlTarget" -ForegroundColor Green

if ($NoRun) {
    Write-Host "Skipping launch due to -NoRun." -ForegroundColor Yellow
    exit 0
}

Write-Host "Launching DeckRPG..." -ForegroundColor Cyan
& $exePath
