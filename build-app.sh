#!/bin/bash
# Build GameBoost.app — a double-clickable macOS app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="GameBoost"
BUNDLE_ID="com.morgangamble.gameboost"
OUT_DIR="dist"
APP_DIR="$OUT_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "→ Generating icon..."
swift tools/make-icon.swift

echo "→ Building release binary..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
  echo "Binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "→ Assembling bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [ -f "Resources/$APP_NAME.icns" ]; then
  cp "Resources/$APP_NAME.icns" "$RES_DIR/$APP_NAME.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>$APP_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>GameBoost uses AppleScript to request admin rights for purge and mdutil, and to toggle Focus via Shortcuts.</string>
</dict>
</plist>
PLIST

echo "→ Ad-hoc signing..."
codesign --force --deep --sign - "$APP_DIR" 2>&1 | sed 's/^/   /'

echo ""
echo "✓ Built $APP_DIR"
echo "  Open with:  open \"$APP_DIR\""
echo "  Install to Applications:  cp -R \"$APP_DIR\" /Applications/"
