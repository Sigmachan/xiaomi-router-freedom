#!/bin/sh
# Captive DNS: force ALL LAN plaintext DNS (:53) through the router's dnsmasq -> AdGuard Home (DoH).
# Why: setup-dnsmasq-agh.sh only makes the *router's own* resolver use AGH. A LAN client that hardcodes
# its own resolver (e.g. a desktop pinned to 8.8.8.8) bypasses it and stays exposed to RU DPI :53 poisoning.
# This NAT-redirects every :53 query that isn't already aimed at the router back to the router -> AGH.
#
# NOTE (scope): this only catches *plaintext* :53. Encrypted client DNS (DoT :853 / DoH :443) is NOT
# redirected here on purpose -- transparently proxying TLS DNS isn't possible, and blocking :853 breaks
# strict-DoT clients. If a client uses its own DoT/DoH, fix it on that client. A client doing DoT to a
# clean foreign resolver is already un-poisonable, so it does not need this anyway.
#
# Persistence: /etc is ramfs on these boxes, so install this on persistent storage (e.g. /data/force-dns.sh)
# and re-apply every minute from cron:  * * * * * /data/force-dns.sh >/dev/null 2>&1
# IDEMPOTENT: purge any existing copies (canonical spec incl. -m <proto>) then add exactly one.
LAN="${LAN:-br-lan}"          # LAN bridge interface
RIP="${RIP:-192.168.31.1}"    # router LAN IP (where dnsmasq -> AGH listens on :53)
for P in udp tcp; do
  SPEC="! -d $RIP -i $LAN -p $P -m $P --dport 53 -j DNAT --to-destination $RIP:53"
  while iptables -w -t nat -C PREROUTING $SPEC 2>/dev/null; do iptables -w -t nat -D PREROUTING $SPEC; done
  iptables -w -t nat -A PREROUTING $SPEC
done
