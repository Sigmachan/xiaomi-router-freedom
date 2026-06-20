#!/bin/sh
# Единый статус-пульт домашней сети (mihomo TUN + AGH + unbound + portainer)
. /etc/profile.d/docker.sh 2>/dev/null
export DOCKER_HOST=unix:///var/run/docker1.sock
CFG=/mnt/usb-b9363656/mihomo/config.yaml
SECRET=$(awk -F'"' '/^secret:/{print $2}' "$CFG" 2>/dev/null)
CTRL=127.0.0.1:9010
RIP=192.168.31.1
api(){ curl -s --max-time 4 -H "Authorization: Bearer $SECRET" "http://$CTRL$1"; }
jget(){ grep -o "\"$1\":[^,}]*" | head -1 | cut -d: -f2- | tr -d '"'; }
bar(){ printf '\033[1;36m%s\033[0m\n' "$1"; }
ok(){ printf '  \033[1;32m✓\033[0m %s\n' "$1"; }
no(){ printf '  \033[1;31m✗\033[0m %s\n' "$1"; }

bar "============ HOME NET STACK ============"
bar "-- containers --"
for c in mihomo adguardhome unbound portainer; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
  [ "$st" = running ] && ok "$c: $st" || no "$c: ${st:-missing}"
done

bar "-- tunnel (mihomo TUN) --"
if ip link show Meta >/dev/null 2>&1; then ok "Meta(TUN) up"; else no "Meta(TUN) DOWN"; fi
n=$(iptables -S FORWARD 2>/dev/null | grep -c 'o Meta')
[ "$n" -ge 1 ] && ok "FORWARD br-lan->Meta ($n)" || no "FORWARD rule MISSING"

bar "-- proxy node --"
d=$(api '/proxies/upstream/delay?timeout=3000&url=http://www.gstatic.com/generate_204' | jget delay)
case "$d" in ''|*[!0-9]*) no "upstream delay: timeout/err";; *) [ "$d" -lt 1500 ] && ok "upstream delay: ${d}ms" || no "upstream delay HIGH: ${d}ms";; esac
sel=$(api /proxies/Proxy | jget now); [ -n "$sel" ] && ok "Proxy -> $sel"
cn=$(api /connections | grep -o '"id"' | wc -l); ok "active connections: $cn"
ver=$(api /version | jget version); [ -n "$ver" ] && ok "mihomo $ver"

bar "-- dns chain (dnsmasq->AGH->unbound) --"
nslookup github.com 127.0.0.1 >/dev/null 2>&1 && ok "resolve github.com: ok" || no "resolve FAIL"
if nslookup 00go.com 127.0.0.1 2>/dev/null | grep -q '0.0.0.0\|NXDOMAIN\|can.t find'; then ok "ad-block (00go.com): blocked"; else no "ad-block: LEAK"; fi

bar "-- routing rules --"
ok "total rules: $(grep -cE '^\s+- (DOMAIN|IP-CIDR|GEOIP|GEOSITE|RULE-SET|MATCH)' "$CFG")"
ok "trackers->Proxy: $(grep -c 'rutracker\|nnm\|kinozal\|rutor\|1337x\|piratebay\|nyaa' "$CFG")"

bar "-- dashboard --"
ok "yacd: http://192.168.31.1:9010/ui/ (zero-click)"
bar "======================================="
