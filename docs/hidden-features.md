# Hidden / undocumented features — Xiaomi BE10000 Pro (RP04, IPQ5424)

Observed on the live unit (MiWiFi OpenWrt 18.06 fork, kernel 6.6) and cross-checked against
the unpacked stock rootfs. Applies broadly to the IPQ5424 RDP466 family (RP04/RP08).

## Dev / debug unlocks

| Flag (`nvram get …`) | This unit | Meaning |
|---|---|---|
| `uart_en` | `1` | **UART serial console** active (115200 on the board header) — full bootloader + root shell |
| `factory_mode` | `1` | Factory/engineering mode (also in `/proc/cmdline`: `factory_mode=1 uart_en=1`) |
| `telnet_en` | `1` | telnet daemon allowed |
| `ssh_en` | `1` | dropbear allowed … **but** the init gate disables SSH on `channel=release`: |
| `boot_wait` | `on` | bootloader waits (eases TFTP recovery) |

```sh
# /etc/init.d/dropbear gate — release channel forces SSH off even if ssh_en=1
flg_ssh=`nvram get ssh_en`
if [ "$flg_ssh" != "1" -o "$channel" = "release" ]; then ... ; fi
```
→ Stock SSH on a release build is closed; it's unlocked via the `xmir-patcher` stok
exploit (sets the gate + a persistent dropbear). On this unit SSH is `root:root`.

## Region control (bdata)

Region/regulatory, MAC, SN, color live in the **`bdata`** partition (`mtd17`), managed by
`/usr/sbin/bdata`:
```sh
bdata get CountryCode        # -> CN here
bdata set CountryCode=RU      # switch region (RU/EU/US/SG/JP/KR/… present in region_mapping)
bdata commit && reboot
```
`/etc/config/region_mapping` (region→CountryCode) and `/etc/config/country_mapping`
(country→region, +GDPR flags) show the firmware is multi-region; the marketed CN lock is
just the bdata value.

## Boot / storage internals

- **A/B dual boot**: `rootfs` + `rootfs_1`, switched by `flag_boot_rootfs`,
  `flag_try_sys1_failed`, `flag_try_sys2_failed`, `flag_boot_success` — auto-failover to the
  other slot after failed boots. A built-in brick-recovery.
- **Crash capture**: dedicated `crash` + `crash_syslog` mtd partitions + `minidump`.
- **Built-in Docker**: a dedicated `docker` UBI partition (`mtd24`/`ubi_docker`) — Xiaomi
  ships a docker runtime (`/data/docker/docker`); that's how AdGuard/mihomo/Portainer run.
- Persistent vs volatile: `/etc` is **ramfs** (resets on boot); `/data`, `/etc/config`,
  `/etc/crontabs` are ubifs (persist). Firewall rules in iptables reset on reboot.

## Local MiWiFi API

stok-token web API (`stok`/`nonce`/`deviceId` auth) under LuCI controllers `api`, `mipctl`,
`sec_center`, `service`, `web`, `diagnosis`, `anti_attack`. Endpoints like
`/api/xqnetwork/*`, `/api/misystem/*` drive the app; the same surface is what rooting tools
abuse for command injection.

## Other shipped tooling

`tcpdump`, the Mi service stack (`miio*`, `miqosd`, `miwifi-roam`, `ssid-steering`,
`aimesh`), Samba/`timemachine` (USB NAS), `nfc`, `parentalctl`, `miniupnpd`. `nft_tproxy`
kmod is **absent** (can't transparently tproxy → use TUN/REDIRECT instead).

## Practical takeaways

- You already have the full set of unlocks (UART + SSH + factory). Keep UART access — it's
  the ultimate recovery path.
- Region is one `bdata set CountryCode=…` away; no reflash needed just to change region.
- Don't fight `/etc` ramfs — persist via `/data` + cron + fw3 includes (see `mihomo/`).
