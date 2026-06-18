# Lightweight DNS fix without Docker — https_dns_proxy (DoH) + dnsmasq

If you don't want to run AdGuard Home in Docker (low RAM, no docker, or you just want minimal), a tiny
**DoH proxy** does the same anti-poisoning job: it resolves over encrypted HTTPS so RU DPI can't inject fakes.

`https_dns_proxy` (C, ~100 KB) is in Entware and as a routerich build.

## Install (via Entware — see ../entware/)
```sh
export PATH=/opt/bin:/opt/sbin:$PATH
opkg update && opkg install https-dns-proxy        # name may be https_dns_proxy / https-dns-proxy
# run it on a local port pointing at clean DoH resolvers:
/opt/sbin/https_dns_proxy -a 127.0.0.1 -p 5353 \
    -r 'https://1.1.1.1/dns-query' -r 'https://8.8.8.8/dns-query' &
```
Persist it the same way as the Entware mount (a `/data/*.sh` + cron line, since `/etc` is ramfs).

## Point dnsmasq at it
Same as the AGH recipe, just a different port:
```sh
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

## AGH vs https_dns_proxy
- **AGH**: web UI, filtering, fallback resolvers, query log, fakeip-friendly. Heavier (docker). Recommended if you have it.
- **https_dns_proxy**: tiny, no UI, just clean DoH forwarding. Best for minimal/no-docker setups.
Both kill the DNS poisoning. Pick one.
