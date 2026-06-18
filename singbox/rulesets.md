# Auto-updating domain rule-sets (recommended over the static lists)

`singbox/domains/*.txt` are hand-curated snapshots — fine, but they go stale. The **better** approach is
sing-box **remote `rule_set`** pointing at **[itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains)**
prebuilt `.srs` — community-maintained, comprehensive (RU-focused), and **auto-updated** by sing-box on a timer.

## Add to your sing-box config
Requires `experimental.cache_file.enabled = true` (already in `config.template.json`).

```json
"route": {
  "rule_set": [
    { "tag": "youtube",  "type": "remote", "format": "binary", "url": "https://github.com/itdoginfo/allow-domains/releases/latest/download/youtube.srs",  "download_detour": "direct", "update_interval": "3d" },
    { "tag": "discord",  "type": "remote", "format": "binary", "url": "https://github.com/itdoginfo/allow-domains/releases/latest/download/discord.srs",  "download_detour": "direct", "update_interval": "3d" },
    { "tag": "meta",     "type": "remote", "format": "binary", "url": "https://github.com/itdoginfo/allow-domains/releases/latest/download/meta.srs",     "download_detour": "direct", "update_interval": "3d" },
    { "tag": "twitter",  "type": "remote", "format": "binary", "url": "https://github.com/itdoginfo/allow-domains/releases/latest/download/twitter.srs",  "download_detour": "direct", "update_interval": "3d" },
    { "tag": "hdrezka",  "type": "remote", "format": "binary", "url": "https://github.com/itdoginfo/allow-domains/releases/latest/download/hdrezka.srs",  "download_detour": "direct", "update_interval": "3d" },
    { "tag": "tiktok",   "type": "remote", "format": "binary", "url": "https://github.com/itdoginfo/allow-domains/releases/latest/download/tiktok.srs",   "download_detour": "direct", "update_interval": "3d" },
    { "tag": "geoblock", "type": "remote", "format": "binary", "url": "https://github.com/itdoginfo/allow-domains/releases/latest/download/geoblock.srs", "download_detour": "direct", "update_interval": "3d" }
  ],
  "rules": [
    { "action": "sniff" },
    { "protocol": "dns", "action": "hijack-dns" },
    { "protocol": "quic", "action": "reject" },
    { "ip_is_private": true, "outbound": "direct" },
    { "domain_suffix": ["__paste domains/direct.txt__"], "outbound": "direct" },
    { "rule_set": ["youtube","discord","meta","twitter","hdrezka","tiktok","geoblock"], "outbound": "proxy" },
    { "domain_suffix": ["__paste domains/ai.txt — AI services aren't in allow-domains__"], "outbound": "proxy" }
  ],
  "final": "direct"
}
```

## Notes
- `download_detour: "direct"` fetches the `.srs` directly (GitHub releases). If GitHub is blocked for you, set it
  to your proxy outbound, or pin `raw.githubusercontent.com`/`objects.githubusercontent.com` in the router hosts.
- Keep the **`domains/ai.txt`** static list as an explicit `domain_suffix` rule — AI services (OpenAI/Claude/etc)
  aren't in allow-domains, and they're the most useful to route. (`anthropic.com` spelled correctly here.)
- The `.txt` lists remain the **offline fallback** if you can't fetch remote rule-sets.

## Available allow-domains rule-sets
`geoblock` (services geoblocking RU), `block` (RKN), `youtube`, `discord`, `meta`, `twitter`, `hdrezka`,
`tiktok`, `news`, `anime`, `porn`, + `personal` (your own). Pick what you actually need.
