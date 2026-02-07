#!/usr/bin/env bash
# PostDown script for WireGuard - deactivates NAT
set -euo pipefail

# Flush NAT rules from anchor
pfctl -a com.apple/wireguard -F all 2>/dev/null || true

# Release pfctl token if saved
TOKEN_FILE="/usr/local/etc/wireguard/.pfctl_token"
if [[ -f "$TOKEN_FILE" ]]; then
    PFCTL_TOKEN=$(cat "$TOKEN_FILE")
    if [[ -n "$PFCTL_TOKEN" ]]; then
        pfctl -X "$PFCTL_TOKEN" 2>/dev/null || true
    fi
    rm -f "$TOKEN_FILE"
fi

# Disable IP forwarding
sysctl -w net.inet.ip.forwarding=0

echo "NAT desativado com sucesso"
