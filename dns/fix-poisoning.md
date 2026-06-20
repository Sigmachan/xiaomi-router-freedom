# Fixing "unavailable in your region" — it's DNS poisoning, not your VPN

## Symptom
A site (e.g. claude.ai, an AI service, a blocked resource) shows **"not available in your region"** even though
your tunnel works for other sites. `getent hosts claude.ai` returns a bogus IP (often a Russian block-server,
labelled with an unrelated CN) instead of the real one.

## Localize first — `dig` vs `getent`

Run both before assuming DPI:
- `dig +short claude.ai`   — bypasses /etc/hosts, asks the resolver directly.
- `getent hosts claude.ai` — reads /etc/hosts FIRST (so do curl, browsers, systemd-resolved).

`dig` clean but `getent` poisoned → it's a stale **/etc/hosts** entry (Cause B), NOT poisoning.
Both poisoned → it's on the wire (Cause A). A hosts entry is read before the router/AGH/tunnel, so no
DNS fix below helps until you remove it.

## Cause A — RU DPI poisons plaintext :53
RU DPI **injects fake DNS answers** on plaintext UDP/53 for censored domains — regardless of which upstream
resolver you set (8.8.8.8 OR a local RU resolver both get poisoned on the wire). The fake IP points at a
block page → "unavailable in region". Your tunnel is fine; you never reach the real server.

## Cause B — stale `/etc/hosts` unblocker (GeoHide / comss / malw lists)
A DNS-unblock service (e.g. `dns.geohide.ru`, `info.dns.malw.link`) ships a **hosts file** that pins hundreds
of domains (claude.ai, openai/chatgpt, deepl, spotify, gemini, ...) to ITS OWN proxy IPs. If you later switch
to your own tunnel and that proxy lapses/blocks, those pins return 403 "unavailable" — and because /etc/hosts
wins over everything, it masquerades as DNS poisoning. Tell-tale: `getent`/`curl` poisoned but `dig` clean;
the block is usually wrapped in markers like `### dns.geohide.ru: hosts file` ... `### dns.geohide.ru: end hosts file`.

Fix — remove the proxy-IP pins from the client's /etc/hosts (back it up first):
```sh
sudo cp -a /etc/hosts /etc/hosts.bak-$(date +%F)
# delete every line pinned to the unblocker proxy IPs (use the IPs from YOUR file's header):
sudo sed -i '/45\.155\.204\.190/d; /37\.230\.192\.51/d' /etc/hosts
sudo resolvectl flush-caches 2>/dev/null || true
```
Keep unrelated curated entries (ad/telemetry `0.0.0.0` blocks, manual unblocks, LAN hostnames). Check for an
updater (cron/timer) that regenerates the block, or it will come back.

## Fix: encrypted DNS in the path (AdGuard Home with DoH)
1. Run **AdGuard Home** on the router (docker is easiest on these immutable-root boxes).
2. Set AGH upstreams to **clean foreign DoH** (un-poisonable):
   `https://1.1.1.1/dns-query`, `https://8.8.8.8/dns-query`, `quic://dns.adguard-dns.com`.
   - Avoid RU resolvers as *primary* (some return the censored IP even over DoT). Put RU-unblock DoH
     (e.g. `https://dns.comss.one/dns-query`) only in **fallback** if you want unblock-as-safety-net.
3. Point the router's dnsmasq at AGH: see `setup-dnsmasq-agh.sh`.
4. Flush AGH cache (it may have cached a poisoned answer): AGH UI → "Clear cache", or `/control/cache_clear`.
5. **Force LAN clients that hardcode their own resolver** (e.g. a desktop pinned to 8.8.8.8) onto AGH:
   run `force-dns.sh` (NAT-redirects all LAN :53 back to the router). Without it such a client bypasses 1–4.

Verify: `nslookup claude.ai <router-ip>` should return the real IP; the site loads.
