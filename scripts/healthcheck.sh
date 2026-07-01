#!/usr/bin/env bash
# TingleVPN Health Check - verifica e corrige tunel, IP forwarding e NAT
# Roda a cada 2 minutos via LaunchDaemon
# NB: NAO usa set -e para garantir que todas as verificacoes rodem mesmo com falhas parciais

export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin:$PATH

WG_DIR="/usr/local/etc/wireguard"
LOG="/var/log/tinglevpn-health.log"
FIXED=0
WG_RUN_DIR="/var/run/wireguard"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [HEALTH] $1" >> "$LOG"
}

# --- Funcao auxiliar: reinicia o tunel via LaunchDaemon supervisor ---
# O tunel e de propriedade do LaunchDaemon com.tinglevpn.wg, que roda wg-daemon.sh
# (RunAtLoad + AbandonProcessGroup). NAO subimos o tunel diretamente aqui: um
# "wg-quick up" lancado por este script morreria assim que o health check
# terminasse. Fazemos: (1) "wg-quick down" para forcar recriacao limpa -- isso
# tambem conserta o cenario de rotas migradas para en0, que so se resolve
# recriando a interface; (2) "launchctl kickstart" para o daemon subir de novo,
# ja com a protecao do AbandonProcessGroup.
restart_tunnel() {
    local reason="$1"
    log "ALERTA: $reason"

    # Derruba o tunel atual (wg-quick resolve wg0 -> utunN via wg0.name).
    wg-quick down wg0 >> "$LOG" 2>&1 || true

    if launchctl kickstart -k system/com.tinglevpn.wg >> "$LOG" 2>&1; then
        # Aguarda o tunel voltar antes dos checks seguintes (ate ~10s).
        # NB: "wg show wg0" NAO funciona no userspace do macOS (a interface real
        # e utunN); consultamos o utunN lido do wg0.name.
        local i iface=""
        for i in 1 2 3 4 5 6 7 8 9 10; do
            iface=$(cat "$WG_RUN_DIR/wg0.name" 2>/dev/null) || true
            if [[ -n "$iface" ]] && wg show "$iface" >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        wg_iface="$iface"
        if [[ -n "$wg_iface" ]] && wg show "$wg_iface" >/dev/null 2>&1; then
            log "CORRIGIDO: Tunel reiniciado via daemon com.tinglevpn.wg ($wg_iface)"
        else
            log "ERRO: Tunel nao voltou apos kickstart do daemon"
        fi
        FIXED=$((FIXED + 1))
        return 0
    fi

    log "ERRO: Falha ao solicitar restart do daemon com.tinglevpn.wg (esta carregado?)"
    return 1
}

# --- 1. Verifica tunel WireGuard ---

wg_iface=""
if [[ -f "$WG_RUN_DIR/wg0.name" ]]; then
    wg_iface=$(cat "$WG_RUN_DIR/wg0.name" 2>/dev/null) || true
fi

# Valida que a interface realmente existe e responde
tunnel_ok=false
if [[ -n "$wg_iface" ]]; then
    if wg show "$wg_iface" >/dev/null 2>&1; then
        tunnel_ok=true
    else
        # Interface no arquivo mas nao responde - stale
        wg_iface=""
    fi
fi

if [[ -z "$wg_iface" ]]; then
    # Fallback: procura utun com IP 10.10.10.1
    wg_iface=$(ifconfig -l 2>/dev/null | tr ' ' '\n' | while read -r iface; do
        ifconfig "$iface" 2>/dev/null | grep -q "inet 10.10.10.1 " && echo "$iface" && break
    done) || true
    if [[ -n "$wg_iface" ]]; then
        tunnel_ok=true
    fi
fi

if ! $tunnel_ok; then
    restart_tunnel "Tunel WireGuard inativo. Reiniciando..."
fi

# --- 2. Verifica rotas dos peers ---
# Apos queda de energia/rede, as rotas dos peers podem apontar para en0
# ao inves de utun, quebrando o retorno do trafego pelo tunel.

if [[ -n "$wg_iface" ]]; then
    route_iface=$(route -n get 10.10.10.2 2>/dev/null | grep 'interface:' | awk '{print $2}') || true
    if [[ -n "$route_iface" && "$route_iface" != "$wg_iface" ]]; then
        restart_tunnel "Rotas dos peers apontando para $route_iface ao inves de $wg_iface"
    fi
fi

# --- 3. Verifica IP forwarding ---

fwd=$(sysctl -n net.inet.ip.forwarding 2>/dev/null || echo "0")
if [[ "$fwd" != "1" ]]; then
    log "ALERTA: IP forwarding desativado (valor: $fwd). Reativando..."
    sysctl -w net.inet.ip.forwarding=1 >> "$LOG" 2>&1
    log "CORRIGIDO: IP forwarding reativado"
    FIXED=1
fi

# --- 4. Verifica regras NAT no pfctl ---

nat_rules=$(pfctl -a com.apple/wireguard -s nat 2>/dev/null || true)
if [[ -z "$nat_rules" ]]; then
    log "ALERTA: Regras NAT ausentes no anchor pfctl. Reaplicando..."

    # Detecta interface de rede padrao (mesma logica do postup.sh)
    DEFAULT_IF=$(route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}') || true

    if [[ -z "$DEFAULT_IF" ]]; then
        log "ERRO: Nao foi possivel detectar interface de rede padrao"
    else
        if echo "nat on $DEFAULT_IF from 10.10.10.0/24 to any -> ($DEFAULT_IF)" | \
            pfctl -a com.apple/wireguard -f - 2>> "$LOG"; then
            log "CORRIGIDO: Regras NAT reaplicadas na interface $DEFAULT_IF"
            FIXED=1
        else
            log "ERRO: Falha ao reaplicar regras NAT"
        fi

        # Garante que pfctl esta habilitado
        pfctl -e 2>/dev/null || true
    fi
fi

# Saida silenciosa quando tudo OK (nao polui o log)
if [[ $FIXED -gt 0 ]]; then
    log "Health check concluido - $FIXED correcao(oes) aplicada(s)"
fi
