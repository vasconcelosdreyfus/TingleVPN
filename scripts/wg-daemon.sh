#!/usr/bin/env bash
# TingleVPN - Sobe o tunel WireGuard (wg0). One-shot idempotente.
#
# Rodado por:
#   - LaunchDaemon com.tinglevpn.wg (RunAtLoad) no boot / no start;
#   - health check, via "launchctl kickstart", quando detecta o tunel caido.
#
# O ponto critico e a chave <AbandonProcessGroup>true</AbandonProcessGroup> no
# plist: sem ela, o launchd mata o wireguard-go que o wg-quick lanca em background
# (daemonizado) ~70ms depois de subir -- era a causa raiz do crash-loop. Com ela,
# o wireguard-go sobrevive como processo abandonado (reparentado ao launchd),
# exatamente como acontece quando rodamos "wg-quick up wg0" no terminal.
#
# Este script NAO fica em foreground: sobe o tunel e sai. Quem cuida de reiniciar
# em caso de queda e o health check (com.tinglevpn.health, a cada 2 min).
#
# NB: NAO usa "set -e" -- queremos controle explicito sobre falhas.

export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin:$PATH

WG_IF="wg0"
WG_RUN_DIR="/var/run/wireguard"
LOG="/var/log/tinglevpn-wg.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WG-DAEMON] $1" >> "$LOG"
}

# Verifica se o tunel esta no ar. ATENCAO: no WireGuard userspace do macOS a
# interface real e utunN, e "wg show <nome>" procura <nome>.sock -- ou seja,
# "wg show wg0" SEMPRE falha. O correto e ler o wg0.name (mapa wg0 -> utunN,
# escrito pelo wg-quick) e consultar "wg show <utunN>" (mesma logica do health
# check e do manage.sh status).
tunnel_up() {
    local iface=""
    if [[ -f "$WG_RUN_DIR/${WG_IF}.name" ]]; then
        iface=$(cat "$WG_RUN_DIR/${WG_IF}.name" 2>/dev/null) || true
    fi
    [[ -n "$iface" ]] && wg show "$iface" >/dev/null 2>&1
}

# Ja esta no ar? Nada a fazer (idempotente).
if tunnel_up; then
    log "Tunel $WG_IF ja esta ativo. Nada a fazer."
    exit 0
fi

# Limpa estado stale que causa "Address already in use" no restart.
log "Tunel $WG_IF inativo. Limpando estado e subindo..."
wg-quick down "$WG_IF" >> "$LOG" 2>&1 || true
pkill -f 'wireguard-go' >> "$LOG" 2>&1 || true
rm -f "$WG_RUN_DIR/${WG_IF}.name" "$WG_RUN_DIR"/*.sock

if wg-quick up "$WG_IF" >> "$LOG" 2>&1; then
    log "Tunel $WG_IF ativo."
    exit 0
fi

log "ERRO: 'wg-quick up $WG_IF' falhou."
exit 1
