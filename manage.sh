#!/usr/bin/env bash
# CLI de gerenciamento do TingleVPN
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WG_DIR="/usr/local/etc/wireguard"
WG_CONF="$WG_DIR/wg0.conf"
KEYS_DIR="$SCRIPT_DIR/keys"
CONFIGS_DIR="$SCRIPT_DIR/configs"

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
        erro "Este script deve ser executado como root. Use: sudo $0 $*"
    fi
}

usage() {
    cat << 'EOF'
TingleVPN - Gerenciamento do servidor WireGuard

Uso: sudo ./manage.sh <comando>

Comandos:
  start       Inicia o WireGuard e ativa os LaunchDaemons
  stop        Para o WireGuard e desativa os LaunchDaemons
  restart     Reinicia o WireGuard
  status      Mostra status do tunel e peers conectados
  list        Lista todos os clientes configurados
  add <nome>  Adiciona um novo cliente (atalho para generate-client.sh)
  remove <nome>  Remove um cliente
  logs        Mostra logs recentes do WireGuard
  ip          Mostra o IP publico atual
  duckdns     Forca atualizacao do DuckDNS agora
  dashboard   Inicia/para/reinicia o dashboard web (start|stop|restart|status)
EOF
    exit 1
}

# --- Comandos ---

cmd_start() {
    check_root
    info "Iniciando WireGuard..."

    if wg show wg0 &>/dev/null; then
        info "WireGuard ja esta rodando"
    else
        wg-quick up wg0
        info "WireGuard iniciado"
    fi

    # Ativa LaunchDaemons
    if [[ -f /Library/LaunchDaemons/com.tinglevpn.wg.plist ]]; then
        launchctl load -w /Library/LaunchDaemons/com.tinglevpn.wg.plist 2>/dev/null || true
    fi
    if [[ -f /Library/LaunchDaemons/com.tinglevpn.duckdns.plist ]]; then
        launchctl load -w /Library/LaunchDaemons/com.tinglevpn.duckdns.plist 2>/dev/null || true
    fi

    info "LaunchDaemons ativados"
}

cmd_stop() {
    check_root
    info "Parando WireGuard..."

    # Desativa LaunchDaemons
    launchctl unload -w /Library/LaunchDaemons/com.tinglevpn.wg.plist 2>/dev/null || true
    launchctl unload -w /Library/LaunchDaemons/com.tinglevpn.duckdns.plist 2>/dev/null || true

    if wg show wg0 &>/dev/null; then
        wg-quick down wg0
        info "WireGuard parado"
    else
        info "WireGuard nao estava rodando"
    fi
}

cmd_restart() {
    check_root
    info "Reiniciando WireGuard..."

    if wg show wg0 &>/dev/null; then
        wg-quick down wg0
    fi
    wg-quick up wg0

    info "WireGuard reiniciado"
}

cmd_status() {
    echo "=== Status do WireGuard ==="
    echo ""

    if wg show wg0 &>/dev/null; then
        echo "Tunel: ATIVO"
        echo ""
        wg show wg0
    else
        echo "Tunel: INATIVO"
    fi

    echo ""
    echo "=== IP Forwarding ==="
    sysctl net.inet.ip.forwarding

    echo ""
    echo "=== NAT (pfctl anchor) ==="
    pfctl -a com.apple/wireguard -s nat 2>/dev/null || echo "Sem regras NAT ativas"

    echo ""
    echo "=== LaunchDaemons ==="
    if launchctl list com.tinglevpn.wg &>/dev/null; then
        echo "WireGuard daemon: carregado"
    else
        echo "WireGuard daemon: nao carregado"
    fi
    if launchctl list com.tinglevpn.duckdns &>/dev/null; then
        echo "DuckDNS daemon: carregado"
    else
        echo "DuckDNS daemon: nao carregado"
    fi
    if launchctl list com.tinglevpn.dashboard &>/dev/null; then
        echo "Dashboard daemon: carregado"
    else
        echo "Dashboard daemon: nao carregado"
    fi
}

cmd_list() {
    echo "=== Clientes Configurados ==="
    echo ""

    if [[ ! -f "$WG_CONF" ]]; then
        erro "Config do servidor nao encontrada"
    fi

    # Extrai nomes dos clientes dos comentarios no wg0.conf
    local count=0
    while IFS= read -r line; do
        local name
        name=$(echo "$line" | sed 's/# Cliente: //')
        local ip=""

        # Le a proxima linha de AllowedIPs
        ip=$(grep -A3 "# Cliente: $name" "$WG_CONF" | grep "AllowedIPs" | awk '{print $3}' | head -1)

        echo "  $name  ($ip)"
        count=$((count + 1))
    done < <(grep "^# Cliente:" "$WG_CONF")

    if [[ $count -eq 0 ]]; then
        echo "  Nenhum cliente configurado"
    fi

    echo ""
    echo "Total: $count cliente(s)"
}

cmd_add() {
    check_root
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        erro "Uso: $0 add <nome-do-cliente>"
    fi
    "$SCRIPT_DIR/generate-client.sh" "$name"
}

cmd_remove() {
    check_root
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        erro "Uso: $0 remove <nome-do-cliente>"
    fi

    # Verifica se cliente existe
    if ! grep -q "# Cliente: $name$" "$WG_CONF"; then
        erro "Cliente '$name' nao encontrado"
    fi

    # Obtem a chave publica do cliente
    local pubkey
    pubkey=$(grep -A1 "# Cliente: $name$" "$WG_CONF" | grep "PublicKey" | awk '{print $3}')

    if [[ -z "$pubkey" ]]; then
        erro "Nao foi possivel encontrar a chave publica do cliente '$name'"
    fi

    # Remove peer do tunel ativo
    if wg show wg0 &>/dev/null; then
        wg set wg0 peer "$pubkey" remove
        info "Peer removido do tunel ativo"
    fi

    # Remove bloco do peer do arquivo de config
    # Usa awk para remover o bloco do cliente (comentario + [Peer] + 3 linhas)
    local temp_conf
    temp_conf=$(mktemp)
    awk -v name="$name" '
        /^# Cliente: / { if ($3 == name) { skip=1; next } }
        skip && /^\[Peer\]/ { next }
        skip && /^(PublicKey|PresharedKey|AllowedIPs) =/ { next }
        skip && /^$/ { skip=0; next }
        { print }
    ' "$WG_CONF" > "$temp_conf"
    mv "$temp_conf" "$WG_CONF"
    chmod 600 "$WG_CONF"

    # Remove arquivos do cliente
    rm -f "$KEYS_DIR/${name}_private.key"
    rm -f "$KEYS_DIR/${name}_public.key"
    rm -f "$KEYS_DIR/${name}_psk.key"
    rm -f "$CONFIGS_DIR/${name}.conf"

    info "Cliente '$name' removido com sucesso"
}

cmd_logs() {
    echo "=== Logs do WireGuard ==="
    if [[ -f /var/log/tinglevpn-wg.log ]]; then
        tail -30 /var/log/tinglevpn-wg.log
    else
        echo "Nenhum log encontrado"
    fi

    echo ""
    echo "=== Logs do DuckDNS ==="
    if [[ -f /var/log/tinglevpn-duckdns.log ]]; then
        tail -10 /var/log/tinglevpn-duckdns.log
    else
        echo "Nenhum log encontrado"
    fi
}

cmd_ip() {
    echo "IP publico atual:"
    curl -s ifconfig.me
    echo ""
}

cmd_duckdns() {
    info "Forcando atualizacao do DuckDNS..."
    "$WG_DIR/duckdns-update.sh"
}

cmd_dashboard() {
    check_root
    local subcmd="${1:-status}"
    local plist="/Library/LaunchDaemons/com.tinglevpn.dashboard.plist"
    local src_plist="$SCRIPT_DIR/templates/com.tinglevpn.dashboard.plist"

    case "$subcmd" in
        start)
            if [[ ! -f "$plist" ]]; then
                cp "$src_plist" "$plist"
            fi
            launchctl load -w "$plist" 2>/dev/null || true
            info "Dashboard iniciado"
            ;;
        stop)
            launchctl unload -w "$plist" 2>/dev/null || true
            info "Dashboard parado"
            ;;
        restart)
            launchctl unload -w "$plist" 2>/dev/null || true
            launchctl load -w "$plist" 2>/dev/null || true
            info "Dashboard reiniciado"
            ;;
        status)
            if launchctl list com.tinglevpn.dashboard &>/dev/null; then
                echo "Dashboard daemon: carregado"
            else
                echo "Dashboard daemon: nao carregado"
            fi
            ;;
        *)
            erro "Uso: $0 dashboard (start|stop|restart|status)"
            ;;
    esac
}

# --- Main ---

[[ $# -lt 1 ]] && usage

COMMAND="$1"
shift

case "$COMMAND" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    restart) cmd_restart ;;
    status)  cmd_status ;;
    list)    cmd_list ;;
    add)     cmd_add "$@" ;;
    remove)  cmd_remove "$@" ;;
    logs)    cmd_logs ;;
    ip)      cmd_ip ;;
    duckdns)    cmd_duckdns ;;
    dashboard)  cmd_dashboard "$@" ;;
    *)          usage ;;
esac
