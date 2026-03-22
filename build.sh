#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="System Monitor"
BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"

echo "Building SystemMonitor (release)..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

BINARY="$(swift build -c release --show-bin-path)/SystemMonitor"

echo "Assembling ${APP_NAME}.app..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BINARY" "$BUNDLE/Contents/MacOS/SystemMonitor"
cp "$SCRIPT_DIR/Info.plist" "$BUNDLE/Contents/"

# Generate a simple .icns from SF Symbol via iconutil
ICONSET="/tmp/SystemMonitor.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Create a basic gauge icon at all required sizes
for SIZE in 16 32 64 128 256 512; do
    sips -z $SIZE $SIZE -s format png /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarUtilitiesFolderIcon.icns --out "$ICONSET/icon_${SIZE}x${SIZE}.png" > /dev/null 2>&1 || true
    DOUBLE=$((SIZE * 2))
    sips -z $DOUBLE $DOUBLE -s format png /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarUtilitiesFolderIcon.icns --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" > /dev/null 2>&1 || true
done

if iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    echo "App icon generated."
else
    echo "Skipped app icon (non-critical)."
fi
rm -rf "$ICONSET"

echo ""
echo "Built: ${BUNDLE}"
echo ""

# Install to /Applications
if [ -d "/Applications/${APP_NAME}.app" ]; then
    echo "Removing old installation..."
    rm -rf "/Applications/${APP_NAME}.app"
fi
cp -R "$BUNDLE" "/Applications/${APP_NAME}.app"
echo "Installed to /Applications/${APP_NAME}.app"

# Kill any running instance and relaunch
killall SystemMonitor 2>/dev/null || true
echo "Launching ${APP_NAME}..."
open "/Applications/${APP_NAME}.app"
