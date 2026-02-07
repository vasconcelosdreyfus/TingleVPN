#!/usr/bin/env bash
# PostUp script for WireGuard - activates NAT via pfctl
set -euo pipefail

# Detect default route interface (en0, en1, etc.)
DEFAULT_IF=$(route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}')
if [[ -z "$DEFAULT_IF" ]]; then
    echo "ERRO: Nao foi possivel detectar a interface de rede padrao" >&2
    exit 1
fi

echo "Interface detectada: $DEFAULT_IF"

# Enable IP forwarding
sysctl -w net.inet.ip.forwarding=1

# Configure NAT via pfctl anchor (does not modify system files)
echo "nat on $DEFAULT_IF from 10.10.10.0/24 to any -> ($DEFAULT_IF)" | \
    pfctl -a com.apple/wireguard -f -

# Enable pfctl (get token for cleanup)
PFCTL_TOKEN=$(pfctl -E 2>&1 | grep -oE 'Token\s*:\s*[0-9]+' | awk '{print $NF}')
echo "$PFCTL_TOKEN" > /usr/local/etc/wireguard/.pfctl_token

echo "NAT ativado com sucesso na interface $DEFAULT_IF"
