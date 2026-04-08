#!/bin/bash
set -euo pipefail

APP_NAME="ClaudeCodeMonitor"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

echo "==> Building release binary..."
swift build -c release

echo "==> Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Info.plist" "${APP_BUNDLE}/Contents/"

# Copy app icon
cp "Resources/app-icon.png" "${APP_BUNDLE}/Contents/Resources/"

# Copy SPM bundled resources (includes menu bar icon)
RESOURCE_BUNDLE="${BUILD_DIR}/ClaudeCodeMonitor_ClaudeCodeMonitor.bundle"
if [ -d "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
fi

# Ad-hoc code sign
echo "==> Signing..."
codesign --force --sign - "${APP_BUNDLE}"

APP_SIZE=$(du -sh "${APP_BUNDLE}" | cut -f1)
echo "==> Done! ${APP_BUNDLE} (${APP_SIZE})"
echo "==> Run with: open ${APP_BUNDLE}"
