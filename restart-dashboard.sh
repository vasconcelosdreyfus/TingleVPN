#!/bin/bash
launchctl bootout system/com.tinglevpn.dashboard 2>/dev/null
sleep 1
launchctl bootstrap system /Library/LaunchDaemons/com.tinglevpn.dashboard.plist
echo "Dashboard restarted"
