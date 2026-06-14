#!/bin/bash
# Build GameBoost.app — a double-clickable macOS app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="GameBoost"
BUNDLE_ID="com.morgangamble.gameboost"
VERSION="1.3.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
OUT_DIR="dist"

# Mode: ""/--zip = ad-hoc signing; --release = Developer ID sign + notarize + staple.
MODE="${1:-}"
# Override with env vars if needed; otherwise auto-detect the Developer ID cert.
DEVID_IDENTITY="${DEVID_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
NOTARY_PROFILE="${NOTARY_PROFILE:-gameboost-notary}"
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
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>$APP_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Morgan Gamble. MIT License.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>GameBoost uses AppleScript to request admin rights for purge and mdutil, and to toggle Focus via Shortcuts.</string>
</dict>
</plist>
PLIST

ZIP_PATH="$OUT_DIR/$APP_NAME-$VERSION.zip"

if [ "$MODE" = "--release" ]; then
  if [ -z "$DEVID_IDENTITY" ]; then
    echo "✗ No 'Developer ID Application' certificate found in your keychain." >&2
    echo "  1. Create one: Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application" >&2
    echo "     (requires the paid Apple Developer Program)" >&2
    echo "  2. Store notarization credentials once:" >&2
    echo "       xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\" >&2
    echo "         --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>" >&2
    echo "  3. Re-run: ./build-app.sh --release" >&2
    exit 1
  fi

  ENTITLEMENTS="Resources/$APP_NAME.entitlements"
  if [ ! -f "$ENTITLEMENTS" ]; then
    echo "✗ Missing entitlements file: $ENTITLEMENTS" >&2
    exit 1
  fi

  echo "→ Stripping extended attributes..."
  xattr -cr "$APP_DIR"

  echo "→ Signing with Developer ID + hardened runtime: $DEVID_IDENTITY"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVID_IDENTITY" "$MACOS_DIR/$APP_NAME"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVID_IDENTITY" "$APP_DIR"
  codesign --verify --strict --verbose=2 "$APP_DIR"

  echo "→ Packaging for notarization..."
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

  echo "→ Submitting to Apple notary service (a few minutes)..."
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "→ Stapling ticket..."
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"

  echo "→ Re-packaging stapled app..."
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

  echo ""
  echo "✓ Notarized + stapled: $ZIP_PATH ($APP_NAME $VERSION, build $BUILD)"
  echo "  Downloaders can open it with no Gatekeeper warning."
else
  echo "→ Ad-hoc signing..."
  codesign --force --deep --sign - "$APP_DIR" 2>&1 | sed 's/^/   /'

  if [ "$MODE" = "--zip" ]; then
    echo "→ Packaging $ZIP_PATH..."
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
  fi

  echo ""
  echo "✓ Built $APP_DIR ($APP_NAME $VERSION, build $BUILD)"
  echo "  Open with:  open \"$APP_DIR\""
  echo "  Install to Applications:  cp -R \"$APP_DIR\" /Applications/"
  echo "  Release zip (ad-hoc):  ./build-app.sh --zip"
  echo "  Notarized release:     ./build-app.sh --release  (needs Developer ID cert)"
fi
