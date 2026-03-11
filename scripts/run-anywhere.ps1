param(
    [switch]$SkipBuild,
    [switch]$NoRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Delegate to the existing runner while preserving flags.
$runner = Join-Path $PSScriptRoot "run-windows.ps1"
if (-not (Test-Path $runner)) {
    throw "Missing runner script: $runner"
}

& $runner @PSBoundParameters
