# Swift Portable Setup Script
# Run this after extracting Swift ZIP to C:\Swift

param(
    [string]$SwiftPath = "C:\Swift"
)

Write-Host "Setting up Swift portable installation..." -ForegroundColor Cyan

# Verify Swift exists
if (-not (Test-Path "$SwiftPath\usr\bin\swift.exe")) {
    Write-Host "ERROR: Swift not found at $SwiftPath\usr\bin\swift.exe" -ForegroundColor Red
    Write-Host "Please extract the Swift toolchain ZIP to $SwiftPath first" -ForegroundColor Yellow
    exit 1
}

# Add to PATH for current session
$env:Path = "$SwiftPath\usr\bin;$SwiftPath\usr\lib\swift\windows;$env:Path"

# Add to system PATH permanently (requires admin)
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$SwiftPath\usr\bin*") {
    Write-Host "Adding Swift to user PATH..." -ForegroundColor Yellow
    [Environment]::SetEnvironmentVariable(
        "Path", 
        "$SwiftPath\usr\bin;$SwiftPath\usr\lib\swift\windows;$currentPath", 
        "User"
    )
    Write-Host "Swift added to PATH. You'll need to restart PowerShell." -ForegroundColor Green
} else {
    Write-Host "Swift already in PATH" -ForegroundColor Green
}

# Test Swift
Write-Host "`nTesting Swift installation..." -ForegroundColor Cyan
& "$SwiftPath\usr\bin\swift.exe" --version

Write-Host "`nSwift setup complete!" -ForegroundColor Green
Write-Host "Restart PowerShell for PATH changes to take effect." -ForegroundColor Yellow
