#!/bin/sh
# fw3 include: re-apply LAN->Meta FORWARD ACCEPT on every firewall (re)load/boot.
iptables -C FORWARD -s 192.168.31.0/24 -o Meta -j ACCEPT 2>/dev/null || iptables -I FORWARD -s 192.168.31.0/24 -o Meta -j ACCEPT
