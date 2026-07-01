#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="TingleVPN"
SOURCE_APP="$APP_DIR/dist/${APP_NAME}.app"
TARGET_DIR="$HOME/Applications"
TARGET_APP="$TARGET_DIR/${APP_NAME}.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/com.tinglevpn.tray.plist"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "App bundle nao encontrado em $SOURCE_APP"
  echo "Execute primeiro: $SCRIPT_DIR/package-app.sh"
  exit 1
fi

mkdir -p "$TARGET_DIR" "$LAUNCH_AGENTS_DIR"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tinglevpn.tray</string>
  <key>ProgramArguments</key>
  <array>
    <string>$TARGET_APP/Contents/MacOS/TingleVPNTray</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>/tmp/tinglevpn-tray.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/tinglevpn-tray.err.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"

echo "Instalado em: $TARGET_APP"
echo "Iniciar no login: ATIVO"
echo "LaunchAgent: $PLIST_PATH"
