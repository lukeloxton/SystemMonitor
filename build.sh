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

if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
    echo "App icon installed."
else
    echo "Warning: AppIcon.icns not found. Run 'swift generate-icon.swift' first."
fi

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
