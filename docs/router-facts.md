# Platform facts — Xiaomi Qualcomm WiFi-7 vendor-OpenWrt routers (IPQ5424 / IPQ9554 class)

Hard facts gathered on an IPQ5424 (RDP466-class) running the stock vendor OpenWrt **18.06-SNAPSHOT** fork.
Very similar on IPQ9554 (e.g. Xiaomi BE7000). Useful before you try to add software.

## Filesystem / flash
- `/` is **read-only squashfs** (`mtdblockNN`). It always shows **100% full** — that's normal for squashfs,
  NOT a "disk is clogged" problem. Nothing to clean there.
- There is **no writable overlay on `/`** → you **cannot `opkg install` into the system**. The vendor
  `/bin/opkg` is an old (2019) stub against the vendor feed; effectively useless for new software.
- Writable storage that DOES exist:
  - `/etc/config`, `/data` → **ubifs (persistent)**, tens of MB free.
  - a large empty ubifs volume (e.g. `/data/other_vol`, ~200 MB).
  - the **USB drive** (the big one — put docker / Entware / configs here).
  - `/etc` itself is **ramfs** → changes there are LOST on reboot. Persist via `/data` + `/etc/crontabs`.

## Consequences for proxy/DPI software
- **podkop won't install**: needs OpenWrt ≥24.10 + native opkg into `/` (immutable here). Wrong gen + no overlay.
- **Native packages** → **Entware on USB** (`/opt` bind-mounted). Note Entware aarch64 repo has **xray-core**
  but **not sing-box** (grab sing-box's static linux-arm64 binary from GitHub instead).
- **Docker** also runs on these (vendor "mi_docker" daemon on a separate socket) and is a common home for
  sing-box + AdGuard Home, kept on USB. `restart=always` gives boot persistence.
- **`nft_tproxy` kernel module is absent** and can't be added (immutable root, no matching kmod) →
  use **REDIRECT + fakeip + QUIC-reject** instead of tproxy.

## DNS
- RU DPI poisons plaintext UDP/53 → blocked sites read "unavailable in region". Fix = AdGuard Home with
  encrypted DoH upstreams, dnsmasq pointed at it. See `../dns/`.

## Access
- SSH on these is frequently `root` / `root` out of the box on the vendor firmware — **change it**.
