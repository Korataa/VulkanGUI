#!/bin/bash

# DeckRPG Build Environment Setup Script
# This script helps set up the build environment for both Linux and Windows (via WSL/MSYS2)

set -e  # Exit on any error

echo "🚀 DeckRPG Build Environment Setup"
echo "=================================="

# Detect platform
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORM="linux"
    echo "📍 Detected platform: Linux"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    PLATFORM="windows"
    echo "📍 Detected platform: Windows (MSYS2/Cygwin)"
else
    echo "❌ Unsupported platform: $OSTYPE"
    echo "   This script supports Linux and Windows (via MSYS2/Cygwin)"
    exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install packages on Linux
install_linux_deps() {
    echo "📦 Installing Linux dependencies..."
    
    # Detect Linux distribution
    if command_exists apt-get; then
        # Ubuntu/Debian
        echo "   Using apt-get (Ubuntu/Debian)"
        sudo apt-get update
        sudo apt-get install -y \
            swift \
            libsdl3-dev \
            libvulkan-dev \
            vulkan-tools \
            vulkan-validationlayers-dev \
            pkg-config \
            build-essential
            
    elif command_exists dnf; then
        # Fedora
        echo "   Using dnf (Fedora)"
        sudo dnf install -y \
            swift-lang \
            SDL3-devel \
            vulkan-devel \
            vulkan-tools \
            vulkan-validation-layers-devel \
            pkgconfig \
            gcc-c++
            
    elif command_exists pacman; then
        # Arch Linux
        echo "   Using pacman (Arch Linux)"
        sudo pacman -S --needed \
            swift \
            sdl3 \
            vulkan-devel \
            vulkan-tools \
            vulkan-validation-layers \
            pkgconf \
            base-devel
            
    else
        echo "❌ Unsupported Linux distribution"
        echo "   Please install the following packages manually:"
        echo "   - Swift toolchain"
        echo "   - SDL3 development packages"
        echo "   - Vulkan development packages"
        echo "   - pkg-config"
        echo "   - C++ build tools"
        exit 1
    fi
}

# Function to setup Windows environment
setup_windows_env() {
    echo "📦 Setting up Windows environment..."
    
    # Check for vcpkg
    if [[ -z "$VCPKG_ROOT" ]]; then
        echo "❌ VCPKG_ROOT environment variable not set"
        echo "   Please install vcpkg and set VCPKG_ROOT"
        echo "   Example:"
        echo "     git clone https://github.com/Microsoft/vcpkg.git C:/vcpkg"
        echo "     cd C:/vcpkg"
        echo "     ./bootstrap-vcpkg.bat"
        echo "     export VCPKG_ROOT=C:/vcpkg"
        exit 1
    fi
    
    echo "   Found vcpkg at: $VCPKG_ROOT"
    
    # Install required packages via vcpkg
    echo "   Installing packages via vcpkg..."
    "$VCPKG_ROOT/vcpkg.exe" install \
        sdl3:x64-windows \
        vulkan:x64-windows
        
    # Set environment variables
    export VCPKG_INSTALLED_DIR="$VCPKG_ROOT/installed/x64-windows"
    echo "   Set VCPKG_INSTALLED_DIR=$VCPKG_INSTALLED_DIR"
}

# Main setup logic
case "$PLATFORM" in
    "linux")
        if ! command_exists swift; then
            echo "❌ Swift not found. Installing dependencies..."
            install_linux_deps
        else
            echo "✅ Swift found: $(swift --version | head -n1)"
        fi
        
        # Verify libraries
        if pkg-config --exists sdl3 vulkan; then
            echo "✅ SDL3 and Vulkan found via pkg-config"
        else
            echo "⚠️  SDL3 or Vulkan not found via pkg-config"
            echo "   Attempting to install..."
            install_linux_deps
        fi
        ;;
        
    "windows")
        setup_windows_env
        ;;
esac

# Test build
echo ""
echo "🔨 Testing build..."
if swift build; then
    echo "✅ Build successful!"
    echo ""
    echo "🎮 To run your game:"
    echo "   swift run DeckRPG"
    echo ""
    echo "🐛 To build in debug mode:"
    echo "   swift build -c debug"
    echo ""
    echo "🚀 To build in release mode:"
    echo "   swift build -c release"
else
    echo "❌ Build failed!"
    echo ""
    echo "🔍 Troubleshooting:"
    echo "   1. Check that all dependencies are installed"
    echo "   2. Verify environment variables (VCPKG_ROOT on Windows)"
    echo "   3. Check Package.swift for correct library paths"
    echo "   4. Run 'swift build --verbose' for detailed error messages"
    exit 1
fi

echo ""
echo "🎉 Setup complete!"
