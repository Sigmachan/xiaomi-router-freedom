# Ported features (from analysing Windows zapret/DPI GUIs) — and what was deliberately NOT ported

These are baked into `singbox/config.template.json` + the DNS recipe. Judgment: only port what's useful and
portable to a Linux router; skip Windows-desktop-only or vendor-monetized features.

## Ported ✅
- **QUIC reject** (`route.rules: {protocol: quic, action: reject}`). Forces clients off HTTP/3 (UDP/443) onto
  TCP, where transparent REDIRECT + DPI-bypass actually work. Avoids needing the `nft_tproxy` kmod (absent on
  these immutable-root boxes). Also the common "YouTube works on TCP but not QUIC" fix.
- **HTTPS-RR DNS reject** (`dns.rules: {query_type: [HTTPS], action: reject}`). Stops ECH/HTTPS resource
  records so the real SNI stays visible — keeps domain routing reliable.
- **Disable browser auto-DoH** (`reject use-application-dns.net`). Stops Firefox/Chrome silently doing their
  own encrypted DNS that bypasses your router's clean resolver.
- **Force clean DNS network-wide** = the AdGuard-Home-in-path recipe (`dns/`), the Linux/router equivalent of
  the GUI's "Force DNS" (which set one DoH server via Win32 API per adapter). Here it's the whole LAN.
- **fakeip-ready** scaffolding (toggle in template + cache_file) for the cleaner routing model — see
  `fakeip-migration.md`.

## NOT ported (with reasons) ❌
- **Orchestra auto-unlock** (auto-DPI-strategy orchestrator that relearns on RST): winws/Lua-specific, no
  Linux nfqws equivalent. The Linux analogue is `blockcheck` (zapret's own strategy finder) — run it to pick
  a working `nfqws` strategy for your ISP. Not auto-relearning, but the right tool here.
- **MTProxy server / Cloudflare-Worker upstream**: Telegram-specific; redundant if you already tunnel via VLESS.
- **Premium-gated themes (AMOLED / mascot backgrounds)**: cosmetic + the tool author's paid feature — not ours
  to bypass.
- **Tray / autostart-in-tray / WinAPI adapter toggles / AV-conflict detection**: Windows-desktop only.
  Linux autostart = docker `restart=always` or the Entware cron in this kit.
