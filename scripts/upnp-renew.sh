#!/bin/zsh
# Renova no Nokia (Giganet) o encaminhamento 51820/UDP para o WAN do Google Wifi.
# O painel userAdmin bloqueia Port Forwarding e o Nokia limita o lease UPnP a 7 dias.
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
IGD=http://192.168.1.254:49153/gatedesc.xml
PORT=51820
PUCK=$(curl -s -m 5 http://192.168.86.1/api/v1/status | python3 -c 'import sys,json;print(json.load(sys.stdin)["wan"]["localIpAddress"])' 2>/dev/null)
[ -n "$PUCK" ] || { echo "$(date '+%F %T') ERRO: sem IP WAN do puck"; exit 1; }
upnpc -u $IGD -e tinglevpn -a "$PUCK" $PORT $PORT UDP 2>&1 | grep -Ei 'redirected|error|fail' | sed "s/^/$(date '+%F %T') /"
