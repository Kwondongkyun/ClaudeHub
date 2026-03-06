#!/bin/bash
set -euo pipefail

APP_NAME="ClaudeHub"
BUNDLE_ID="com.claudehub.app"
VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

echo "=== ClaudeHub Build ==="
echo ""

# [1/5] Release 빌드
echo "[1/5] Building release binary..."
swift build -c release 2>&1
BINARY="$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME"

if [ ! -f "$BINARY" ]; then
    BINARY="$BUILD_DIR/release/$APP_NAME"
fi

# [2/5] .app 번들 생성
echo "[2/5] Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>ClaudeHub needs permission to control terminal apps for session resume.</string>
</dict>
</plist>
PLIST

# [3/5] Ad-hoc 코드 서명
echo "[3/5] Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1

# [4/5] DMG 생성
echo "[4/5] Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" 2>&1

rm -rf "$DMG_STAGING"

# [5/5] 완료
echo ""
echo "[5/5] Done!"
echo "  App: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"
echo ""
read -p "Install to /Applications? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    echo "Installed to /Applications/$APP_NAME.app"
fi
