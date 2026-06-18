# Fixing "unavailable in your region" — it's DNS poisoning, not your VPN

## Symptom
A site (e.g. claude.ai, an AI service, a blocked resource) shows **"not available in your region"** even though
your tunnel works for other sites. `getent hosts claude.ai` returns a bogus IP (often a Russian block-server,
labelled with an unrelated CN) instead of the real one.

## Cause
RU DPI **injects fake DNS answers** on plaintext UDP/53 for censored domains — regardless of which upstream
resolver you set (8.8.8.8 OR a local RU resolver both get poisoned on the wire). The fake IP points at a
block page → "unavailable in region". Your tunnel is fine; you never reach the real server.

## Fix: encrypted DNS in the path (AdGuard Home with DoH)
1. Run **AdGuard Home** on the router (docker is easiest on these immutable-root boxes).
2. Set AGH upstreams to **clean foreign DoH** (un-poisonable):
   `https://1.1.1.1/dns-query`, `https://8.8.8.8/dns-query`, `quic://dns.adguard-dns.com`.
   - Avoid RU resolvers as *primary* (some return the censored IP even over DoT). Put RU-unblock DoH
     (e.g. `https://dns.comss.one/dns-query`) only in **fallback** if you want unblock-as-safety-net.
3. Point the router's dnsmasq at AGH: see `setup-dnsmasq-agh.sh`.
4. Flush AGH cache (it may have cached a poisoned answer): AGH UI → "Clear cache", or `/control/cache_clear`.

Verify: `nslookup claude.ai <router-ip>` should return the real IP; the site loads.
