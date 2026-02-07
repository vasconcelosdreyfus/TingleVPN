#!/usr/bin/env bash
# Gera configuracao de novo cliente WireGuard
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WG_DIR="/usr/local/etc/wireguard"
KEYS_DIR="$SCRIPT_DIR/keys"
CONFIGS_DIR="$SCRIPT_DIR/configs"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
SUBNET="10.10.10"

# --- Funcoes auxiliares ---

usage() {
    echo "Uso: $0 <nome-do-cliente>"
    echo ""
    echo "Exemplos:"
    echo "  $0 iphone"
    echo "  $0 notebook-trabalho"
    echo "  $0 android"
    exit 1
}

erro() {
    echo "ERRO: $1" >&2
    exit 1
}

check_deps() {
    for cmd in wg qrencode; do
        if ! command -v "$cmd" &>/dev/null; then
            erro "'$cmd' nao encontrado. Rode 'brew install wireguard-tools qrencode' primeiro."
        fi
    done
}

# Encontra o proximo IP disponivel na subnet 10.10.10.0/24
# O .1 e reservado para o servidor, clientes usam .2 a .254
next_available_ip() {
    local used_ips=()

    # Coleta IPs ja usados dos peers no wg0.conf
    if [[ -f "$WG_DIR/wg0.conf" ]]; then
        while IFS= read -r line; do
            local ip
            ip=$(echo "$line" | grep -oE '10\.10\.10\.[0-9]+' || true)
            if [[ -n "$ip" ]]; then
                used_ips+=("$ip")
            fi
        done < <(grep "AllowedIPs" "$WG_DIR/wg0.conf")
    fi

    for i in $(seq 2 254); do
        local candidate="${SUBNET}.${i}"
        local found=false
        for used in "${used_ips[@]+"${used_ips[@]}"}"; do
            if [[ "$used" == "$candidate" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            echo "$candidate"
            return
        fi
    done

    erro "Sem IPs disponiveis na subnet ${SUBNET}.0/24"
}

# --- Validacoes ---

[[ $# -lt 1 ]] && usage

CLIENT_NAME="$1"

# Valida nome do cliente (alfanumerico, hifens e underscores)
if [[ ! "$CLIENT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    erro "Nome do cliente deve conter apenas letras, numeros, hifens e underscores"
fi

check_deps

# Verifica se o servidor esta configurado
[[ -f "$WG_DIR/wg0.conf" ]] || erro "Servidor nao configurado. Rode './setup-server.sh' primeiro."
[[ -f "$KEYS_DIR/server_public.key" ]] || erro "Chave publica do servidor nao encontrada em $KEYS_DIR/"

# Verifica se cliente ja existe
[[ -f "$CONFIGS_DIR/${CLIENT_NAME}.conf" ]] && erro "Cliente '$CLIENT_NAME' ja existe"

# --- Carrega .env para o endpoint ---

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
fi

if [[ -z "${DUCKDNS_DOMAIN:-}" ]]; then
    erro "DUCKDNS_DOMAIN nao definido. Crie o arquivo .env com DUCKDNS_DOMAIN=seu-dominio"
fi

ENDPOINT="${DUCKDNS_DOMAIN}.duckdns.org"

# --- Gera chaves do cliente ---

echo "Gerando chaves para '$CLIENT_NAME'..."

mkdir -p "$KEYS_DIR"
mkdir -p "$CONFIGS_DIR"

CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
PRESHARED_KEY=$(wg genpsk)

# Salva chaves
echo "$CLIENT_PRIVATE_KEY" > "$KEYS_DIR/${CLIENT_NAME}_private.key"
echo "$CLIENT_PUBLIC_KEY" > "$KEYS_DIR/${CLIENT_NAME}_public.key"
echo "$PRESHARED_KEY" > "$KEYS_DIR/${CLIENT_NAME}_psk.key"
chmod 600 "$KEYS_DIR/${CLIENT_NAME}"_*.key

# --- Aloca IP ---

CLIENT_IP=$(next_available_ip)
echo "IP alocado: $CLIENT_IP"

# --- Gera config do cliente ---

SERVER_PUBLIC_KEY=$(cat "$KEYS_DIR/server_public.key")

sed -e "s|__CLIENT_IP__|${CLIENT_IP}|g" \
    -e "s|__CLIENT_PRIVATE_KEY__|${CLIENT_PRIVATE_KEY}|g" \
    -e "s|__SERVER_PUBLIC_KEY__|${SERVER_PUBLIC_KEY}|g" \
    -e "s|__PRESHARED_KEY__|${PRESHARED_KEY}|g" \
    -e "s|__ENDPOINT__|${ENDPOINT}|g" \
    "$TEMPLATES_DIR/client.conf.template" > "$CONFIGS_DIR/${CLIENT_NAME}.conf"

chmod 600 "$CONFIGS_DIR/${CLIENT_NAME}.conf"

# --- Adiciona peer ao servidor ---

cat >> "$WG_DIR/wg0.conf" << EOF

# Cliente: $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = ${CLIENT_IP}/32
EOF

echo "Peer adicionado ao servidor"

# --- Hot-reload se o WireGuard estiver rodando ---

if wg show wg0 &>/dev/null; then
    echo "Aplicando configuracao (hot-reload)..."
    wg set wg0 peer "$CLIENT_PUBLIC_KEY" \
        preshared-key <(echo "$PRESHARED_KEY") \
        allowed-ips "${CLIENT_IP}/32"
    echo "Peer adicionado ao tunel ativo"
else
    echo "WireGuard nao esta rodando. O peer sera ativado no proximo 'wg-quick up wg0'."
fi

# --- Gera QR Code ---

echo ""
echo "========================================"
echo " Config do cliente: $CONFIGS_DIR/${CLIENT_NAME}.conf"
echo "========================================"
echo ""
echo "QR Code (escaneie com o app WireGuard):"
echo ""
qrencode -t ansiutf8 < "$CONFIGS_DIR/${CLIENT_NAME}.conf"
echo ""
echo "Cliente '$CLIENT_NAME' criado com sucesso!"
echo "  IP: $CLIENT_IP"
echo "  Endpoint: $ENDPOINT:51820"
echo "  Config: $CONFIGS_DIR/${CLIENT_NAME}.conf"
