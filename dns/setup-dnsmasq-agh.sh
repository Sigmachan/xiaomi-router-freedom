#!/bin/sh
# Point the router's dnsmasq at a local AdGuard Home (with encrypted DoH upstreams) for the whole LAN.
# Defeats RU DPI DNS-poisoning (sites reading "unavailable in region" due to faked A records on plain UDP/53).
# Prereq: AdGuard Home running on the router (e.g. docker) listening on AGH_ADDR, with clean DoH upstreams
# (e.g. https://1.1.1.1/dns-query, https://8.8.8.8/dns-query, quic://dns.adguard-dns.com).
# Find your dnsmasq UCI section name with:  uci show dhcp | grep dnsmasq
set -e
AGH_ADDR="${AGH_ADDR:-127.0.0.1#5300}"          # where AdGuard Home DNS listens
DNSMASQ_SECTION="${DNSMASQ_SECTION:-@dnsmasq[0]}"  # or the cfgXXXXXX name on vendor firmware

echo "Backing up: uci show dhcp.$DNSMASQ_SECTION"
uci -q show "dhcp.$DNSMASQ_SECTION" | grep -E 'server|noresolv' || true
uci add_list "dhcp.$DNSMASQ_SECTION.server=$AGH_ADDR"
uci set    "dhcp.$DNSMASQ_SECTION.noresolv=1"
uci commit dhcp
/etc/init.d/dnsmasq restart
echo "Done. dnsmasq now forwards ALL queries to AdGuard Home at $AGH_ADDR."
echo "WARNING: noresolv=1 means dnsmasq uses ONLY AGH. If AGH is down at boot, LAN DNS is down until it starts."
echo "Rollback: uci del_list dhcp.$DNSMASQ_SECTION.server='$AGH_ADDR'; uci set dhcp.$DNSMASQ_SECTION.noresolv=0; uci commit dhcp; /etc/init.d/dnsmasq restart"
