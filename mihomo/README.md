# mihomo TUN — replacing sing-box

Cherry-pick migration from native sing-box (selective `iptables REDIRECT`, TCP-only)
to **mihomo (Clash.Meta) in TUN mode** running as a Docker container on the router.

## Why

The router kernel has **no `tproxy` support**, so sing-box could only redirect TCP.
UDP/QUIC (HTTP/3, YouTube, game traffic) leaked direct and broke on throttled paths.
mihomo TUN attaches a virtual interface (`Meta`) and intercepts **TCP *and* UDP/QUIC**
with no `REDIRECT`/`tproxy` needed — it only needs `NET_ADMIN` + `/dev/net/tun`
(works under a restrictive docker-authz/OPA policy that forbids `--privileged`).

## Routing logic (top-down, first match wins)

```
torrent trackers (rutracker/nnm/kinozal/rutor/1337x/…)  -> Proxy   (above RU-direct)
.ru / .su / .рф + vk / ozon / wb / yandex               -> DIRECT  (above CF rules)
re:filter domains + ips (blocked-in-RU lists)            -> Proxy
GEOSITE category-ai-!cn                                   -> Proxy
Cloudflare / Fastly CIDRs (RKN volumetric IP-throttle)   -> Proxy
GEOIP RU / CN, everything else                            -> DIRECT
```

RU-direct rules sit **above** the Cloudflare/Fastly IP rules on purpose: a RU site
fronted by Cloudflare stays direct instead of being dragged through the tunnel.

## DNS — untouched

mihomo DNS listens on **loopback only** (`127.0.0.1:1053`, `redir-host`) and does
**not** hijack LAN DNS. The existing pipeline stays intact:

```
dnsmasq:53  ->  AdGuard Home  ->  unbound (recursion + DNSSEC)
```

## Deploy

1. Put `config.template.yaml` -> `config.yaml` on persistent storage
   (e.g. USB `/mnt/usb-XXXX/mihomo/config.yaml`) and fill in the `YOUR_*` VLESS
   placeholders. Drop `geoip.dat`, `geosite.dat` and `ruleset/refilter_*.txt` next to it.
2. Validate before running:
   ```sh
   docker run --rm -v /mnt/usb-XXXX/mihomo:/root/.config/mihomo \
     metacubex/mihomo:Alpha -t -d /root/.config/mihomo
   ```
3. Run (host net, no privileged):
   ```sh
   docker run -d --name mihomo --restart always --network host \
     --cap-add NET_ADMIN --device /dev/net/tun \
     -v /mnt/usb-XXXX/mihomo:/root/.config/mihomo metacubex/mihomo:Alpha
   ```
4. Allow LAN -> tunnel (FORWARD policy is DROP on this router):
   ```sh
   iptables -I FORWARD -s 192.168.31.0/24 -o Meta -j ACCEPT
   ```

## Persistence (survives reboot)

- config + geo + rulesets live on USB (persistent), container `--restart always`.
- **`mihomo-fw.sh`** registered as a fw3 firewall include (`uci add firewall include`,
  `reload=1`) re-applies the `FORWARD -o Meta ACCEPT` immediately on every fw3
  (re)load/boot — no outage window. iptables accepts the rule even before `Meta`
  exists (matched once the interface appears).
- **`mihomo-ensure.sh`** as a `*/2` cron is the belt-and-suspenders fallback
  (container up + FORWARD present).

## Web dashboard (yacd, zero-click)

mihomo exposes its controller on `external-controller: 0.0.0.0:9010`. Serve a
dashboard from it with `external-ui: ui`.

**yacd-meta auto-connects** when you set the default backend in its `index.html`:

```html
<div id="app" data-base-url="http://192.168.31.1:9010"></div>
```

Then `http://192.168.31.1:9010/ui/` opens straight to the live dashboard — no setup
form, no clicks. (metacubexd v1.258 forces a manual "add backend" form even with
`defaultBackendURL`, so yacd is the smoother pick for a fixed-IP router.)

> The controller is LAN-only (WAN input is firewalled). If you have untrusted
> devices/guests on the LAN, set a `secret:` in `config.yaml` instead of leaving it empty.

## Scripts

| file | purpose |
|---|---|
| `config.template.yaml` | mihomo config with VLESS creds redacted (`YOUR_*`) |
| `stack-status.sh` | one-command health board: containers, TUN, FORWARD, node latency, DNS chain, ad-block, rule counts |
| `mihomo-ensure.sh` | cron `*/2`: container up + FORWARD ACCEPT |
| `mihomo-fw.sh` | fw3 include: re-apply FORWARD on every firewall reload/boot |
