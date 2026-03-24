#!/usr/bin/env bash
#
# build_macos.sh — Export "The Vault" as a macOS .app bundle for local beta testing.
#
# Prerequisites:
#   1. Godot 4.5 .NET editor installed at /Applications/Godot_mono.app
#   2. .NET 8 SDK (dotnet --version >= 8.0)
#   3. Godot 4.5 .NET export templates installed
#      (see install_templates step below, or install via Editor → Export → Manage Templates)
#
# Usage:
#   ./build_macos.sh            # release build
#   ./build_macos.sh --debug    # debug build
#

set -euo pipefail

# ---------- Configuration ----------
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
GODOT="/Applications/Godot_mono.app/Contents/MacOS/Godot"
TEMPLATE_VERSION="4.5.stable.mono"
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/$TEMPLATE_VERSION"
BUILD_DIR="$PROJECT_DIR/build/macos"
APP_NAME="The Vault"
PRESET_NAME="macOS"

DEBUG=false
if [[ "${1:-}" == "--debug" ]]; then
    DEBUG=true
fi

# ---------- Preflight checks ----------
echo "==> Preflight checks"

if [[ ! -x "$GODOT" ]]; then
    echo "ERROR: Godot .NET editor not found at $GODOT"
    echo "  Install it from https://godotengine.org/download/archive/4.5-stable/"
    echo "  (download the '.NET' variant for macOS)"
    exit 1
fi

if ! command -v dotnet &>/dev/null; then
    echo "ERROR: dotnet CLI not found. Install the .NET 8 SDK."
    exit 1
fi

# ---------- Install export templates if missing ----------
if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo ""
    echo "==> Export templates not found at:"
    echo "      $TEMPLATE_DIR"
    echo ""
    echo "  You need to install them before exporting. Two options:"
    echo ""
    echo "  OPTION A — From the Godot Editor:"
    echo "    1. Open The Vault project in Godot_mono.app"
    echo "    2. Editor menu → Manage Export Templates → Download and Install"
    echo ""
    echo "  OPTION B — Download manually:"
    echo "    1. Download from: https://github.com/godotengine/godot/releases/tag/4.5-stable"
    echo "       File: Godot_v4.5-stable_export_templates.tpz"
    echo "    2. Extract (it's a zip):"
    echo "         unzip Godot_v4.5-stable_export_templates.tpz -d /tmp/godot_templates"
    echo "    3. Move into place:"
    echo "         mkdir -p \"$TEMPLATE_DIR\""
    echo "         mv /tmp/godot_templates/templates/* \"$TEMPLATE_DIR/\""
    echo ""
    echo "  After installing templates, re-run this script."
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
echo "==> Exporting macOS application ($( $DEBUG && echo "debug" || echo "release" ))"
if $DEBUG; then
    "$GODOT" --headless --path "$PROJECT_DIR" --export-debug "$PRESET_NAME" "$BUILD_DIR/$APP_NAME.app"
else
    "$GODOT" --headless --path "$PROJECT_DIR" --export-release "$PRESET_NAME" "$BUILD_DIR/$APP_NAME.app"
fi

# ---------- Ad-hoc code sign ----------
echo "==> Replacing app icon"
cp "$PROJECT_DIR/assets/icon.icns" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/icon.icns"

echo "==> Registering .map and .sav document bundle types"
PLIST="$BUILD_DIR/$APP_NAME.app/Contents/Info.plist"

# Register UTExportedTypeDeclarations so macOS treats .map/.sav dirs as opaque files
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations array" "$PLIST"

/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:0 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:0:UTTypeIdentifier string com.everstonekeep.thevault.map" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:0:UTTypeDescription string 'The Vault Map Bundle'" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:0:UTTypeConformsTo array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:0:UTTypeConformsTo:0 string com.apple.package" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:0:UTTypeConformsTo:1 string public.data" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:0:UTTypeTagSpecification dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:0 string map" "$PLIST"

/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:1 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:1:UTTypeIdentifier string com.everstonekeep.thevault.sav" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:1:UTTypeDescription string 'The Vault Save Bundle'" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:1:UTTypeConformsTo array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:1:UTTypeConformsTo:0 string com.apple.package" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:1:UTTypeConformsTo:1 string public.data" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:1:UTTypeTagSpecification dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:1:UTTypeTagSpecification:public.filename-extension array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UTExportedTypeDeclarations:1:UTTypeTagSpecification:public.filename-extension:0 string sav" "$PLIST"

# Register CFBundleDocumentTypes so Finder associates .map/.sav with the app
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes array" "$PLIST"

/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string 'The Vault Map'" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSTypeIsPackage bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string com.everstonekeep.thevault.map" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0 string map" "$PLIST"

/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:CFBundleTypeName string 'The Vault Save'" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:CFBundleTypeRole string Editor" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:LSTypeIsPackage bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:LSItemContentTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:LSItemContentTypes:0 string com.everstonekeep.thevault.sav" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:CFBundleTypeExtensions array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:CFBundleTypeExtensions:0 string sav" "$PLIST"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME.app"

# ---------- Remove quarantine flag (for local testing) ----------
echo "==> Removing quarantine attribute"
xattr -dr com.apple.quarantine "$BUILD_DIR/$APP_NAME.app" 2>/dev/null || true

# ---------- Done ----------
echo ""
echo "=========================================="
echo "  Build complete!"
echo "  $BUILD_DIR/$APP_NAME.app"
echo "=========================================="
echo ""
echo "To run:"
echo "  open \"$BUILD_DIR/$APP_NAME.app\""
echo ""
echo "To distribute to another Mac:"
echo "  1. Zip it:  cd \"$BUILD_DIR\" && zip -r \"The Vault.zip\" \"The Vault.app\""
echo "  2. Send the zip file"
echo "  3. On the target Mac, unzip and run:"
echo "       xattr -dr com.apple.quarantine \"The Vault.app\""
echo "       open \"The Vault.app\""
