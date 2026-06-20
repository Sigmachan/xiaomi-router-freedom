# CN → Global rebase: Xiaomi BE10000 Pro (RP04) ⇄ BE19000 Pro (RP08)

Hands-on analysis of whether the **China** Xiaomi BE10000 Pro (`RP04`) can run the
**Global/International** BE19000 Pro (`RP08`) firmware. Both are the same Qualcomm
**IPQ5424 / RDP466** platform; the marketing speed number differs (BE10000 vs BE19000).

> Research/educational. Cross-region flashing can brick. You own the risk.

## Method

Pulled the global INT firmware `miwifi_rp08_firmware_d7403_1.0.37_INT.bin` (48.76 MB,
md5 verified against the server `content-md5`), carved the `HDR1` container → UBI image
(offset `0x310`), extracted volumes (`kernel`, `ubi_rootfs`), `unsquashfs`'d the rootfs,
and compared against the live RP04 unit over SSH.

## Verified facts

| Check | RP04 (CN, this unit) | RP08 (Global INT) | Verdict |
|---|---|---|---|
| SoC / board | IPQ5424 `qcom,ipq5424-rdp466` | same; kernel ships **rdp466 DTB** (13 DTBs incl. `rdp466`, `rdp466-c2/c3/rffe`) | ✅ boots on this board |
| OpenWrt target / arch | `ipq54xx/generic`, `aarch64_cortex-a55` | identical | ✅ |
| U-Boot / kernel | UBOOT 1.0.2 / Linux 6.6 | UBOOT 1.0.2 / Linux 6.6 | ✅ |
| **Signing keys** `public.pem` | `e33cea3a…` | `e33cea3a…` | ✅ **identical** |
| `plugin_public.pem` | `b7d89cfc…` | `b7d89cfc…` | ✅ identical |
| `verify_extra_mtd.pem` | `77f93c3c…` | `77f93c3c…` | ✅ identical |
| rootfs size vs partition | rootfs part = 64 MB | UBI payload 48.76 MB | ✅ fits |
| ROM ver | 1.0.89 (2026-01-12) | 1.0.37 (2025-12-01) | — |
| Secure Version (anti-rollback) | no `SV` field exposed; APPSBLENV shows only `bootdelay`, `model=RP04` | **`SV '1.3'`** | ⚠️ see risks |
| Region table | CN-centric | CN/DE/GB/ID/IN/JP/KR/MY/**RU** | ✅ RU available |
| 6 GHz radio | **PA hardware absent** (per xmir-patcher #129) | firmware expects 6 GHz (71× `6g`, ch. 5955) | ❌ no 6 GHz |

**Identical signing keys** is the key result: the secure-boot chain accepts the global
image — it is the same Xiaomi key, so the bootloader will boot a cross-region rootfs/kernel.

## Verdict

**Technically feasible — it will boot — but you do NOT get BE19000 performance.**

What you gain:
- English/global UI, global Mi cloud (better outside China).
- Correct regulatory region incl. **RU** (more 5 GHz channels / proper power) by setting bdata.

What you do **not** gain:
- **6 GHz band.** The CN BE10000 Pro physically omits the 6 GHz power amplifiers. Global
  firmware enables the 6 GHz radio in software, but with no PAs the band stays dead. You
  remain a 2.4 + 5 GHz device. The "BE19000" number is unreachable on this hardware.

## Risks / gotchas

1. **Official upgrade refuses it** — model check (`RP04 ≠ RP08`). Flash via SSH
   (`ubiformat`/`mtd write` the UBI) or **`xmir-patcher`**, which bypasses the model check.
2. **Anti-rollback (`SV`)** — global is `SV 1.3`. The CN build exposes no SV in userspace
   and no burned SV was visible in APPSBLENV, so the bootloader likely won't refuse it,
   but this is the one item that could hard-brick if an eFuse SV is higher. `xmir-patcher`
   reads/handles this — check before writing.
3. **SSH closes after flash** — stock `dropbear` init gate:
   ```sh
   flg_ssh=`nvram get ssh_en`
   if [ "$flg_ssh" != "1" -o "$channel" = "release" ]; then  # release => SSH OFF
   ```
   A stock release image disables SSH. Re-root with `xmir-patcher` after rebasing.
4. **Per-unit data is preserved** — WiFi calibration (`ART`, mtd13) and `bdata`
   (MAC/SN/region) are not touched by a kernel+rootfs reflash. Region stays `CN` until you
   change it: `bdata set CountryCode=RU` (or EU) → `bdata commit` → reboot.
5. **Recovery nets if it goes wrong** — A/B dual boot (`rootfs`/`rootfs_1`), `uart_en=1`
   serial console, bootloader TFTP recovery, and IPQ5424 EDL.

## Recommended path

1. Root current firmware / keep SSH (already done here).
2. Back up **every** mtd (esp. `bdata`, `ART`, both `rootfs`) over SSH first.
3. Use `xmir-patcher` to flash the global UBI (model-check bypass) — or `ubiformat` manually.
4. After boot: `bdata set CountryCode=RU; bdata commit`, re-enable SSH, reapply the
   Docker/mihomo/DNS stack.

Bottom line: do it for **global UI + RU regulatory region**, not for 6 GHz/“BE19000” speed.
