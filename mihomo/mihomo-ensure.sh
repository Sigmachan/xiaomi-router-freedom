#!/bin/sh
# mihomo TUN ensure (replaces sing-box). Container up + FORWARD ACCEPT LAN->Meta.
. /etc/profile.d/docker.sh 2>/dev/null
export DOCKER_HOST=unix:///var/run/docker1.sock
docker ps --format '{{.Names}}' 2>/dev/null | grep -qx mihomo || docker start mihomo 2>/dev/null
if ip link show Meta >/dev/null 2>&1; then
  iptables -C FORWARD -s 192.168.31.0/24 -o Meta -j ACCEPT 2>/dev/null || iptables -I FORWARD -s 192.168.31.0/24 -o Meta -j ACCEPT
fi
