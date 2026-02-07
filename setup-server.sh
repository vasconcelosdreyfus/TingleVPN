#!/usr/bin/env bash
# Provisionamento inicial do servidor TingleVPN (WireGuard no macOS)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WG_DIR="/usr/local/etc/wireguard"
KEYS_DIR="$SCRIPT_DIR/keys"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

# --- Funcoes auxiliares ---

erro() {
    echo "ERRO: $1" >&2
    exit 1
}

info() {
    echo ">>> $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        erro "Este script deve ser executado como root. Use: sudo $0"
    fi
}

# --- Verificacoes iniciais ---

check_root

info "Iniciando setup do TingleVPN..."

# --- Instala dependencias via Homebrew ---

if ! command -v brew &>/dev/null; then
    erro "Homebrew nao encontrado. Instale em https://brew.sh"
fi

info "Verificando dependencias..."

DEPS=(wireguard-tools qrencode)
for dep in "${DEPS[@]}"; do
    if ! brew list "$dep" &>/dev/null; then
        info "Instalando $dep..."
        # Homebrew nao deve rodar como root, usa o usuario original
        SUDO_USER_HOME=$(eval echo "~${SUDO_USER}")
        sudo -u "$SUDO_USER" brew install "$dep"
    else
        info "$dep ja instalado"
    fi
done

# --- Gera chaves do servidor ---

mkdir -p "$KEYS_DIR"

if [[ -f "$KEYS_DIR/server_private.key" ]]; then
    info "Chaves do servidor ja existem, reutilizando"
else
    info "Gerando chaves do servidor..."
    wg genkey | tee "$KEYS_DIR/server_private.key" | wg pubkey > "$KEYS_DIR/server_public.key"
    chmod 600 "$KEYS_DIR/server_private.key"
    chmod 644 "$KEYS_DIR/server_public.key"
fi

SERVER_PRIVATE_KEY=$(cat "$KEYS_DIR/server_private.key")
SERVER_PUBLIC_KEY=$(cat "$KEYS_DIR/server_public.key")

# --- Cria diretorio do WireGuard ---

mkdir -p "$WG_DIR"

# --- Gera config do servidor ---

if [[ -f "$WG_DIR/wg0.conf" ]]; then
    info "Config do servidor ja existe em $WG_DIR/wg0.conf"
    info "Para recriar, remova o arquivo e rode novamente"
else
    info "Gerando config do servidor..."
    sed "s|__SERVER_PRIVATE_KEY__|${SERVER_PRIVATE_KEY}|g" \
        "$TEMPLATES_DIR/wg0.conf.template" > "$WG_DIR/wg0.conf"
    chmod 600 "$WG_DIR/wg0.conf"
fi

# --- Copia scripts de NAT ---

info "Instalando scripts de NAT..."
cp "$SCRIPT_DIR/scripts/postup.sh" "$WG_DIR/postup.sh"
cp "$SCRIPT_DIR/scripts/postdown.sh" "$WG_DIR/postdown.sh"
chmod 755 "$WG_DIR/postup.sh" "$WG_DIR/postdown.sh"

# --- Copia script DuckDNS ---

info "Instalando script DuckDNS..."
cp "$SCRIPT_DIR/duckdns-update.sh" "$WG_DIR/duckdns-update.sh"
chmod 755 "$WG_DIR/duckdns-update.sh"

# --- Copia .env se existir ---

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    cp "$SCRIPT_DIR/.env" "$WG_DIR/.env"
    chmod 600 "$WG_DIR/.env"
    info "Arquivo .env copiado para $WG_DIR/"
else
    info "AVISO: .env nao encontrado. Crie-o antes de usar o DuckDNS."
    info "  Exemplo:"
    info "    DUCKDNS_DOMAIN=meudominio"
    info "    DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
fi

# --- Instala LaunchDaemons ---

info "Instalando LaunchDaemons..."

PLIST_DIR="/Library/LaunchDaemons"

# WireGuard auto-start
cp "$TEMPLATES_DIR/com.tinglevpn.wg.plist" "$PLIST_DIR/"
chown root:wheel "$PLIST_DIR/com.tinglevpn.wg.plist"
chmod 644 "$PLIST_DIR/com.tinglevpn.wg.plist"

# DuckDNS auto-update
cp "$TEMPLATES_DIR/com.tinglevpn.duckdns.plist" "$PLIST_DIR/"
chown root:wheel "$PLIST_DIR/com.tinglevpn.duckdns.plist"
chmod 644 "$PLIST_DIR/com.tinglevpn.duckdns.plist"

info "LaunchDaemons instalados (nao ativados ainda)"

# --- Resumo ---

echo ""
echo "========================================"
echo " TingleVPN - Setup Concluido!"
echo "========================================"
echo ""
echo "Chave publica do servidor: $SERVER_PUBLIC_KEY"
echo "Config do servidor: $WG_DIR/wg0.conf"
echo ""
echo "Proximos passos:"
echo ""
echo "  1. Crie o arquivo .env (se ainda nao criou):"
echo "     echo 'DUCKDNS_DOMAIN=seu-dominio' > $SCRIPT_DIR/.env"
echo "     echo 'DUCKDNS_TOKEN=seu-token' >> $SCRIPT_DIR/.env"
echo ""
echo "  2. Configure o port forwarding no roteador:"
echo "     Porta 51820/UDP -> IP local deste Mac"
echo ""
echo "  3. Inicie o WireGuard:"
echo "     sudo ./manage.sh start"
echo ""
echo "  4. Gere um cliente:"
echo "     sudo ./generate-client.sh iphone"
echo ""
echo "  5. Desabilite o sleep do Mac:"
echo "     sudo pmset -a sleep 0"
echo ""
