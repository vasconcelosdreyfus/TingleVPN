#!/usr/bin/env bash
# Atualiza IP publico no DuckDNS
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env from the same directory as this script or /usr/local/etc/wireguard
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
elif [[ -f /usr/local/etc/wireguard/.env ]]; then
    source /usr/local/etc/wireguard/.env
fi

if [[ -z "${DUCKDNS_DOMAIN:-}" ]] || [[ -z "${DUCKDNS_TOKEN:-}" ]]; then
    echo "$(date): ERRO - DUCKDNS_DOMAIN e DUCKDNS_TOKEN devem estar definidos no .env" >&2
    exit 1
fi

RESPONSE=$(curl -s "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=")

if [[ "$RESPONSE" == "OK" ]]; then
    echo "$(date): DuckDNS atualizado com sucesso para ${DUCKDNS_DOMAIN}.duckdns.org"
else
    echo "$(date): ERRO ao atualizar DuckDNS - resposta: $RESPONSE" >&2
fi
