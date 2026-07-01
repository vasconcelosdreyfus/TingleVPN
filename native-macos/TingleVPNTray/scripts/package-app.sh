#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="TingleVPN"
EXEC_NAME="TingleVPNTray"
DIST_DIR="$APP_DIR/dist"
BUNDLE_DIR="$DIST_DIR/${APP_NAME}.app"
BUILD_STAMP="$(date +%Y%m%d%H%M%S)"
SHORT_STAMP="$(date +%Y.%m.%d)"
APP_BUILD_VERSION="${BUILD_STAMP}"
APP_SHORT_VERSION="1.0.${SHORT_STAMP}"

cd "$APP_DIR"

swift build -c release

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"

cp ".build/release/$EXEC_NAME" "$BUNDLE_DIR/Contents/MacOS/$EXEC_NAME"
chmod +x "$BUNDLE_DIR/Contents/MacOS/$EXEC_NAME"

cat > "$BUNDLE_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.tinglevpn.tray</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_SHORT_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${EXEC_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -f "$APP_DIR/../dashboard/public/logo.png" ]]; then
  cp "$APP_DIR/../dashboard/public/logo.png" "$BUNDLE_DIR/Contents/Resources/logo.png"
fi

ICON_SRC=""
if [[ -f "$APP_DIR/../assets/images/tinglevpn.png" ]]; then
  ICON_SRC="$APP_DIR/../assets/images/tinglevpn.png"
elif [[ -f "$APP_DIR/../dashboard/public/logo.png" ]]; then
  ICON_SRC="$APP_DIR/../dashboard/public/logo.png"
fi

if [[ -n "$ICON_SRC" ]]; then
  TMP_ICONSET="$DIST_DIR/AppIcon.iconset"
  rm -rf "$TMP_ICONSET"
  mkdir -p "$TMP_ICONSET"

  sips -z 16 16 "$ICON_SRC" --out "$TMP_ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SRC" --out "$TMP_ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SRC" --out "$TMP_ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SRC" --out "$TMP_ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SRC" --out "$TMP_ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$TMP_ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$TMP_ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$TMP_ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$TMP_ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SRC" --out "$TMP_ICONSET/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$TMP_ICONSET" -o "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
  rm -rf "$TMP_ICONSET"
fi

echo "App empacotado em: $BUNDLE_DIR"
echo "CFBundleVersion: $APP_BUILD_VERSION"
echo "CFBundleShortVersionString: $APP_SHORT_VERSION"
