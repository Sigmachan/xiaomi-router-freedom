# xiaomi-router-freedom

Make Xiaomi **Qualcomm WiFi-7 routers** (IPQ5424 / IPQ9554 / RDP466-class, e.g. Xiaomi BE-series on the
stock **vendor OpenWrt 18.06 fork**) usable for transparent VLESS routing + un-poisonable DNS, **without
reflashing** and without fighting the read-only firmware.

> Research/educational. Use on hardware you own.

## Why this exists
These routers ship a vendor OpenWrt fork with a **read-only squashfs rootfs** (`/` is always "100% full" —
that's normal, it's an immutable image) and **no writable `/` overlay**. So you **cannot `opkg install`**
into the system, and OpenWrt-24.10 tools like **podkop won't install** (version + immutable-root). The
working pattern (used in the wild on these boxes) is:

- **Docker on the USB drive** for sing-box / AdGuard Home, **or**
- **Entware on the USB drive** (its own `opkg` in `/opt`) for native userspace packages.

This kit packages both paths + the DNS-poisoning fix + curated routing domain lists.

## What's inside
| Path | What |
|------|------|
| `entware/install.sh` | Install Entware into `/opt` bind-mounted to USB (preserves firmware `/opt/filetunnel`). Persistent across reboot via `/data` + cron (because `/etc` is ramfs). |
| `entware/uninstall.sh` | Full clean rollback. |
| `dns/fix-poisoning.md` | Why RU DNS-poisoning makes sites read "unavailable in region" and the fix. |
| `dns/setup-dnsmasq-agh.sh` | Point the router's dnsmasq at a local AdGuard Home (encrypted DoH upstreams) for the whole LAN. |
| `singbox/config.template.json` | Sanitized sing-box template (fill in YOUR VLESS node). |
| `singbox/domains/` | Curated `domain_suffix` lists (YouTube/Discord/Telegram/AI-services/hdrezka/…) for proxy/direct routing. |
| `docs/router-facts.md` | Hard facts about the platform (partitions, squashfs, Entware, kmods). |
| `docs/fakeip-migration.md` | Plan to move to the cleaner fakeip+tproxy model. |

## Quick start
1. Have a USB drive mounted (these routers expose it, e.g. `/mnt/usb-XXXX`). Set `USB_ROOT` in the scripts.
2. `sh entware/install.sh`  (over SSH as root)
3. Wire DNS: `sh dns/setup-dnsmasq-agh.sh`  (after you have AdGuard Home running on the box)
4. Drop your VLESS node into `singbox/config.template.json` and run sing-box (docker or `/opt/bin`).

## Hardware notes
- `aarch64_cortex-a55` (IPQ5424) / `-a53` (some). musl libc. Kernel 6.6.x vendor build.
- `nft_tproxy` kmod is usually **absent** and can't be added (immutable root) → prefer **REDIRECT + fakeip**, not tproxy.
- SSH default on these is often `root` / `root` (CHANGE IT).

## Credits
This kit synthesizes ideas and data from several community projects (no code copied verbatim; domain lists and
config patterns adapted):

- [stdcion/digital-freedom](https://github.com/stdcion/digital-freedom) — fakeip + tproxy + nftables reference for OpenWrt.
- [youtubediscord/zapret-kvn](https://github.com/youtubediscord/zapret-kvn) — per-service domain catalogs + Xray routing model.
- [StressOzz/Z2R-Manager](https://github.com/StressOzz/Z2R-Manager) — Zapret2/ZeroBlock manager; community routing taxonomy.
- [itdoginfo/podkop](https://github.com/itdoginfo/podkop) & [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains) — the mature OpenWrt fakeip+tproxy solution and maintained domain/subnet lists.
- [vernette/singbox-tproxy-fakeip](https://github.com/vernette/singbox-tproxy-fakeip), [Davoyan/router-xray-fakeip-installation](https://github.com/Davoyan/router-xray-fakeip-installation) — upstream fakeip configs.
- [Entware](https://github.com/Entware/Entware) — the /opt package system that makes the read-only-rootfs problem tractable.

The DNS-poisoning fix, the Entware-on-USB installer for the immutable vendor firmware, the platform facts, and
the ported config features (QUIC-reject, HTTPS-RR reject, anti-auto-DoH) are this repo's contribution.
