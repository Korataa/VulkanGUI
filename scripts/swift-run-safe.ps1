param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$SwiftRunArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-SDLSource {
    $candidates = @(
        $env:SDL3_DLL_PATH,
        "C:\vcpkg\installed\x64-windows\bin\SDL3.dll"
    ) | Where-Object { $_ -and $_.Trim().Length -gt 0 }

    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

# Always run from script-relative repo path to avoid case-mismatch cache poisoning.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

# If Swift tooling is active, module cache cleanup can fail due to file locks.
Get-Process sourcekit-lsp, swift, swiftc, swift-frontend -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$moduleCache = Join-Path $repoRoot ".build\x86_64-unknown-windows-msvc\debug\ModuleCache"
if (Test-Path $moduleCache) {
    Remove-Item $moduleCache -Recurse -Force -ErrorAction SilentlyContinue
}

# Stage SDL3 so SwiftPM-launched executable has required runtime DLL.
$binPath = (swift build --show-bin-path).Trim()
if (-not (Test-Path $binPath)) {
    throw "Build output path not found: $binPath"
}

$sdlSource = Get-SDLSource
if ($sdlSource) {
    Copy-Item -Path $sdlSource -Destination (Join-Path $binPath "SDL3.dll") -Force
} else {
    Write-Host "Warning: SDL3.dll source not found. Set SDL3_DLL_PATH if runtime launch fails." -ForegroundColor Yellow
}

if (-not $SwiftRunArgs -or $SwiftRunArgs.Count -eq 0) {
    swift run
} else {
    swift run @SwiftRunArgs
}
