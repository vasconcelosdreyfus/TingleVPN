#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TingleVPN"
TARGET_APP="$HOME/Applications/${APP_NAME}.app"
PLIST_PATH="$HOME/Library/LaunchAgents/com.tinglevpn.tray.plist"

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"
rm -rf "$TARGET_APP"

echo "Removido: $TARGET_APP"
echo "Removido: $PLIST_PATH"
echo "Iniciar no login: DESATIVADO"
