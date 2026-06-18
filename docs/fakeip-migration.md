# Router migration → fakeip (solve the ipset-coverage gap) — PREPARED 2026-06-18, NOT applied

## Why this plan (and why NOT podkop)
Goal: domain-exact routing without needing each domain's real IP in the refilter `vpn4` ipset
(the gap flagged all day). Reference: stdcion/digital-freedom + itdoginfo/podkop (fakeip+tproxy).

**podkop is RULED OUT on this router (corrected — NOT a disk-space problem):**
- rootfs `/` is **read-only squashfs** (vendor firmware, `mtdblock28`) with **NO writable overlay** → `opkg install`
  into `/` is impossible by design (that's why sing-box runs in docker on USB). The "100% full" on `/`,
  `/data/docker`, `/data/central` is normal squashfs (read-only images), NOT clutter — nothing to clean.
- Writable space is plentiful: `/data/other_vol` ubifs **215M (209M free)**, cfg 23M free, USB 109G free, tmpfs 900M.
- podkop needs OpenWrt **≥24.10**; router is **18.06-SNAPSHOT** (Qualcomm IPQ5424 vendor fork) — version blocker.
- `nft_tproxy` kernel module **absent** (`modprobe nft_tproxy` fails); can't add kmod to the immutable squashfs root.
- → fakeip-migration disk needs (cache.db / fakeip-store / rulesets) fit easily on `other_vol` or USB. No space concern.

**So: fakeip on top of the EXISTING redirect inbound — no podkop, no tproxy, no new kmod.**

## Current architecture (baseline to preserve)
- sing-box (docker container `sing-box`, network_mode host) inbound **type `redirect` :7896** + mixed :2080.
- Traffic reaches it via **iptables-legacy** `nat/PREROUTING → SINGBOX` chain (custom `/data/singbox-redirect.sh`,
  cron `*/2 * * * * singbox-redirect.sh ensure`), which REDIRECTs dst-IP ∈ ipset `vpn4` (refilter) → :7896.
- `/data/singbox-update-rules.sh` weekly rebuilds the refilter ipset/srs.
- DNS: dnsmasq(53) → **AGH :5300** (clean DoH, set today, `noresolv=1`). claude.ai etc. un-poisoned.
- Outbounds: `proxy` (VLESS+Reality Sweden), `direct`. ~162 curated proxy domain_suffix + refilter rule_sets.

## TARGET architecture (fakeip + redirect)
```
client → dnsmasq(53) → sing-box DNS(:5353)
            ├─ proxied domains (domain_suffix list + refilter rule_sets) → return FAKEIP 198.18.0.0/15
            └─ everything else → forward to AGH(:5300)  [keep today's anti-poison DoH]
client connects to a fakeip → iptables REDIRECTs 198.18.0.0/15 → sing-box :7896
            → sing-box knows the domain from the fakeip → routes to `proxy` outbound (real DNS via proxy)
QUIC (udp/443) → sing-box route `{protocol:quic, action:reject}` → client falls back to TCP (redirect-covered)
```
Result: ANY proxied domain routes exactly, regardless of real IP — ipset gap gone. No kmod, reuses redirect.

## STAGED change set (each reversible; back up first)

### 0. BACKUP (do first)
- `cp config.json config.json.bak-fakeip-<ts>`
- `cp /data/singbox-redirect.sh /data/singbox-redirect.sh.bak-fakeip`
- `uci show dhcp.cfg01411c > /tmp/dhcp-uci.bak`

### 1. sing-box config.json — add fakeip DNS (container path /etc/sing-box/config.json)
Add to `"dns"` (create block if absent — current config has NO dns block):
```json
"dns": {
  "strategy": "ipv4_only",
  "independent_cache": true,
  "fakeip": { "enabled": true, "inet4_range": "198.18.0.0/15" },
  "servers": [
    { "tag": "agh",   "address": "127.0.0.1:5300" },
    { "tag": "fakeip","address": "fakeip" }
  ],
  "rules": [
    { "query_type": ["HTTPS"], "action": "reject" },
    { "domain_suffix": ["use-application-dns.net"], "action": "reject" },
    { "server": "fakeip",
      "domain_suffix": [ "<all current proxy domain_suffix entries>" ],
      "rule_set": [ "<refilter/itdoginfo rule_sets currently routed to proxy>" ],
      "rewrite_ttl": 60 }
  ],
  "final": "agh"
}
```
NOTE sing-box 1.13.13: fakeip needs `experimental.cache_file.enabled=true`. Add:
```json
"experimental": { "cache_file": { "enabled": true, "path": "/etc/sing-box/cache.db", "store_fakeip": true } }
```

### 2. sing-box route — add DNS-hijack + QUIC reject (so dnsmasq's queries hit sing-box DNS, UDP avoided)
Prepend to route.rules:
```json
{ "action": "sniff" },
{ "protocol": "dns", "action": "hijack-dns" },
{ "protocol": "quic", "action": "reject" }
```
(Existing domain_suffix→proxy and refilter rule_set→proxy rules stay; they now match via fakeip-resolved domains.)

### 3. Redirect the fakeip range → sing-box (edit /data/singbox-redirect.sh)
Add to the SINGBOX iptables chain a rule to REDIRECT dst 198.18.0.0/15 → 7896 (same as the ipset match):
```sh
iptables -t nat -A SINGBOX -p tcp -d 198.18.0.0/15 -j REDIRECT --to-ports 7896
```
(Keep the existing ipset `vpn4` REDIRECT during transition — belt & suspenders.)

### 4. DNS path: dnsmasq → sing-box(:5353) instead of AGH directly
sing-box DNS must listen on :5353 — add a `direct` inbound type or use the DNS server listen.
In sing-box add inbound: `{ "tag":"dns-in","type":"direct","listen":"127.0.0.1","listen_port":5353 }`
Then UCI: `uci set dhcp.cfg01411c.server='127.0.0.1#5353'` (replace the #5300). AGH stays as sing-box's upstream (rule final→agh) so anti-poisoning is preserved for direct traffic.

### 5. VALIDATE → APPLY → TEST (per the safe pattern used today)
- stream new config via `cat | ssh "cat > config.json.test"` (dropbear chokes on >6KB cmdline — NO base64-in-args)
- `docker -H unix:///var/run/docker1.sock exec sing-box sing-box check -c /etc/sing-box/config.json.test`
- if OK: backup live, swap, restart sing-box, reload dnsmasq.
- TEST one domain first (e.g. add only `claude.ai` to fakeip rule), confirm: `nslookup claude.ai` returns a 198.18.x fakeip; curl claude.ai egress = Sweden. Then expand the domain list.

## ROLLBACK (full)
1. restore `config.json.bak-fakeip-<ts>` → restart sing-box.
2. restore `/data/singbox-redirect.sh.bak-fakeip` → run `singbox-redirect.sh ensure`.
3. `uci set dhcp.cfg01411c.server='127.0.0.1#5300'; uci commit dhcp; /etc/init.d/dnsmasq restart`.
Everything goes back to today's working REDIRECT+AGH state.

## OPEN QUESTIONS to resolve before applying
- Confirm sing-box 1.13.13 fakeip + redirect TCP path works without tproxy for UDP-less services (QUIC-reject handles it).
- Decide DNS layering: dnsmasq→sing-box→AGH (this plan) vs keep dnsmasq→AGH and run sing-box DNS separately. This plan routes through sing-box so fakeip works; AGH stays the clean upstream.
- itdoginfo/allow-domains rule_sets (auto-updating .srs) could REPLACE the static domain_suffix lists — optional upgrade, add `route.rule_set` + `experimental.cache_file`.

## Lower-effort alternative (if migration feels too heavy)
Keep current REDIRECT+ipset, just ensure proxied domains' IPs land in `vpn4`. The fakeip migration is the
clean fix; this alt is the status quo. Current setup WORKS — fakeip is an optimization, not a fix for a broken thing.
