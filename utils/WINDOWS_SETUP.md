# Windows Build Setup Guide

## Prerequisites Installation

### 1. Swift Toolchain
Since winget is blocked by group policy, download and install manually:

**Option A: Official Installer (Recommended)**
1. Go to https://www.swift.org/install/windows/
2. Download the latest Swift installer (.exe)
3. Run the installer as administrator
4. During installation, check "Add to PATH"

**Option B: Portable Installation**
If you can't run installers:
1. Download the Swift toolchain .zip
2. Extract to `C:\swift`
3. Add to PATH manually (see "Manual PATH Setup" below)

### 2. Vulkan SDK
1. Download from: https://vulkan.lunarg.com/sdk/home
2. Install to default location (e.g., `C:\VulkanSDK\1.3.xxx`)
3. Installer should set `VULKAN_SDK` environment variable automatically

If not set automatically, add these environment variables:
```
VULKAN_SDK_INCLUDE = C:\VulkanSDK\1.3.xxx\Include
VULKAN_SDK_LIB = C:\VulkanSDK\1.3.xxx\Lib
```

### 3. SDL3 Library
**Option A: vcpkg (Recommended)**
```powershell
# Install vcpkg if you don't have it
git clone https://github.com/Microsoft/vcpkg.git C:\vcpkg
cd C:\vcpkg
.\bootstrap-vcpkg.bat

# Install SDL3
.\vcpkg install sdl3:x64-windows
```

**Option B: Manual Installation**
1. Download SDL3 from: https://github.com/libsdl-org/SDL/releases
2. Extract to a location (e.g., `C:\SDL3`)
3. Set environment variables pointing to the lib and include folders

### 4. Required Build Tools
- **Visual Studio Build Tools** (if not already installed):
  ```powershell
  winget install Microsoft.VisualStudio.2022.BuildTools
  ```
  OR download from: https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022
  
  Make sure to install "Desktop development with C++"

## Environment Variables Setup

### Using vcpkg (Easier)
If you install SDL3 via vcpkg, update Package.swift or set:
```powershell
setx VULKAN_SDK_INCLUDE "C:\vcpkg\installed\x64-windows\include"
setx VULKAN_SDK_LIB "C:\vcpkg\installed\x64-windows\lib"
```

### Manual Setup
```powershell
# Set these environment variables (use your actual paths)
setx VULKAN_SDK_INCLUDE "C:\VulkanSDK\1.3.xxx\Include"
setx VULKAN_SDK_LIB "C:\VulkanSDK\1.3.xxx\Lib"

# If you installed SDL3 manually, copy SDL3.lib to the Vulkan SDK lib folder
# OR adjust the Package.swift to point to your SDL3 location
```

### Manual PATH Setup (if needed)
```powershell
# Add Swift to PATH
setx PATH "%PATH%;C:\Program Files\Swift\bin"

# Restart PowerShell after setting environment variables
```

## Verification Steps

```powershell
# 1. Verify Swift
swift --version

# 2. Verify Vulkan
echo $env:VULKAN_SDK_INCLUDE
echo $env:VULKAN_SDK_LIB

# 3. Check if libraries exist
Test-Path "$env:VULKAN_SDK_LIB\vulkan-1.lib"
Test-Path "$env:VULKAN_SDK_LIB\SDL3.lib"
```

## Building the Project

```powershell
cd C:\GameDev\DeckRPG

# Clean build
swift package clean

# Build
swift build

# Run
swift run DeckRPG
```

## One-Command Run Helper (Windows)

Use the helper script to build, stage `SDL3.dll`, and run the game:

```powershell
cd C:\GameDev\DeckRPG
powershell -ExecutionPolicy Bypass -File .\scripts\run-windows.ps1
```

Run from any current directory:

```powershell
powershell -ExecutionPolicy Bypass -File C:\GameDev\DeckRPG\scripts\run-anywhere.ps1
```

Useful switches:

```powershell
# Build + stage DLL, but do not launch
powershell -ExecutionPolicy Bypass -File .\scripts\run-windows.ps1 -NoRun

# Stage + run without rebuilding
powershell -ExecutionPolicy Bypass -File .\scripts\run-windows.ps1 -SkipBuild

# Same as above, but callable from anywhere
powershell -ExecutionPolicy Bypass -File C:\GameDev\DeckRPG\scripts\run-anywhere.ps1 -SkipBuild
```

## One-Command Build Helper (Windows)

Build from any current directory without path issues:

```powershell
powershell -ExecutionPolicy Bypass -File C:\GameDev\DeckRPG\scripts\build-windows.ps1
```

Release build:

```powershell
powershell -ExecutionPolicy Bypass -File C:\GameDev\DeckRPG\scripts\build-windows.ps1 -Configuration release
```

## Safe Swift Run (Windows)

If `swift run` crashes with duplicate `vcruntime` module paths (typically caused by mixed path casing like `DeckRPG` vs `Deckrpg`), use the safe wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File C:\GameDev\DeckRPG\scripts\swift-run-safe.ps1
```

Pass through normal `swift run` arguments:

```powershell
powershell -ExecutionPolicy Bypass -File C:\GameDev\DeckRPG\scripts\swift-run-safe.ps1 --skip-build DeckRPG
```

## Troubleshooting

### Swift Installation Issues
- If group policy blocks installation, extract the .zip version and add to PATH manually
- Ensure Visual C++ Redistributables are installed

### Linking Errors
- Verify `VULKAN_SDK_LIB` contains both `vulkan-1.lib` and `SDL3.lib`
- Check that environment variables are set in System Properties (not just PowerShell session)
- Restart PowerShell/terminal after setting environment variables

### vcpkg Path Issues
If you prefer the old vcpkg setup at `Z:\dev\vcpkg`:
- Either install vcpkg there, or
- Update Package.swift line 7 and 16 to use your new vcpkg location
