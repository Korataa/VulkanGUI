param(
    [ValidateSet("debug", "release")]
    [string]$Configuration = "debug"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve repository root relative to this script so caller CWD does not matter.
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

Write-Host "Building DeckRPG ($Configuration)..." -ForegroundColor Cyan
swift build -c $Configuration
