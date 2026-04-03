#!/usr/bin/env bash
#
# build_windows.sh — Cross-export "The Vault" as a Windows build from macOS.
#
# Prerequisites:
#   1. Godot 4.5 .NET editor installed at /Applications/Godot_mono.app
#   2. .NET 8 SDK (dotnet --version >= 8.0)
#   3. Godot 4.5 .NET export templates installed
#
# Usage:
#   ./build_windows.sh            # release build
#   ./build_windows.sh --debug    # debug build
#

set -euo pipefail

# ---------- Configuration ----------
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
GODOT="/Applications/Godot_mono.app/Contents/MacOS/Godot"
TEMPLATE_VERSION="4.5.stable.mono"
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/$TEMPLATE_VERSION"
BUILD_DIR="$PROJECT_DIR/build/windows"
APP_NAME="The Vault"
PRESET_NAME="Windows Desktop"

DEBUG=false
if [[ "${1:-}" == "--debug" ]]; then
    DEBUG=true
fi

# ---------- Preflight checks ----------
echo "==> Preflight checks"

if [[ ! -x "$GODOT" ]]; then
    echo "ERROR: Godot .NET editor not found at $GODOT"
    exit 1
fi

if ! command -v dotnet &>/dev/null; then
    echo "ERROR: dotnet CLI not found. Install the .NET 8 SDK."
    exit 1
fi

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "ERROR: Export templates not found at $TEMPLATE_DIR"
    echo "  Install them via the Godot Editor or download from GitHub."
    exit 1
fi

# Verify Windows templates exist
if [[ ! -f "$TEMPLATE_DIR/windows_release_x86_64.exe" ]]; then
    echo "ERROR: Windows x86_64 export template not found."
    echo "  Expected at: $TEMPLATE_DIR/windows_release_x86_64.exe"
    exit 1
fi

# ---------- Build .NET assemblies ----------
echo "==> Building .NET project"
cd "$PROJECT_DIR"
dotnet build "The Vault.csproj" -c Release

# ---------- Create build directory ----------
echo "==> Preparing build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ---------- Export ----------
echo "==> Exporting Windows application ($( $DEBUG && echo "debug" || echo "release" ))"
if $DEBUG; then
    "$GODOT" --headless --path "$PROJECT_DIR" --export-debug "$PRESET_NAME" "$BUILD_DIR/$APP_NAME.exe"
else
    "$GODOT" --headless --path "$PROJECT_DIR" --export-release "$PRESET_NAME" "$BUILD_DIR/$APP_NAME.exe"
fi

# ---------- Bundle ffmpeg & ffprobe ----------
echo "==> Bundling ffmpeg and ffprobe for Windows"
FFMPEG_WIN_CACHE="$PROJECT_DIR/.cache/ffmpeg-windows"
# gyan.dev provides static Windows builds. Pin to release-7.1.1 for reproducibility.
FFMPEG_WIN_URL="https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-7.1.1-essentials_build.zip"

if [[ ! -f "$FFMPEG_WIN_CACHE/ffmpeg.exe" ]] || [[ ! -f "$FFMPEG_WIN_CACHE/ffprobe.exe" ]]; then
    echo "    Downloading static ffmpeg Windows build (one-time cache)…"
    mkdir -p "$FFMPEG_WIN_CACHE"
    curl -# -L -o "$FFMPEG_WIN_CACHE/ffmpeg-win.zip" "$FFMPEG_WIN_URL"
    # The zip contains a top-level dir like ffmpeg-7.1.1-essentials_build/bin/
    unzip -o -j -q "$FFMPEG_WIN_CACHE/ffmpeg-win.zip" "*/bin/ffmpeg.exe" "*/bin/ffprobe.exe" -d "$FFMPEG_WIN_CACHE"
fi

cp "$FFMPEG_WIN_CACHE/ffmpeg.exe"  "$BUILD_DIR/ffmpeg.exe"
cp "$FFMPEG_WIN_CACHE/ffprobe.exe" "$BUILD_DIR/ffprobe.exe"

# ---------- Done ----------
echo ""
echo "=========================================="
echo "  Build complete!"
echo "  $BUILD_DIR/"
echo "=========================================="
echo ""
echo "Contents:"
ls -lh "$BUILD_DIR/"
echo ""
echo "To distribute to a Windows PC:"
echo "  1. Zip the entire build/windows/ folder"
echo "  2. On the target PC, unzip and run \"$APP_NAME.exe\""
echo ""
echo "NOTE — .map / .sav bundle behaviour on Windows:"
echo "  Unlike macOS (where Info.plist registers them as opaque packages), Windows"
echo "  treats .map and .sav bundles as plain directories.  The app uses the native"
echo "  Windows folder-picker (OPEN_DIR mode) for 'Open Map' and 'Load Game' dialogs"
echo "  so the DM can select a .map/.sav directory directly.  Explorer double-click"
echo "  to open-with is not supported for directory bundles on Windows."
