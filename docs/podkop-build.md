# Building podkop for this hardware (the open LuCI fakeip+tproxy path)

ZeroBlock (routerich) is **closed-source** (binary-only feed, mediatek/cortex-a53) — you cannot build it for
a Qualcomm IPQ5424/IPQ9554. The open, maintainable equivalent is **podkop** (itdoginfo + the routerich fork),
a LuCI-managed sing-box **fakeip + tproxy** solution.

## Reality check first
- podkop's runtime needs **OpenWrt 24.10+**. The stock Xiaomi vendor fork here is **18.06** → podkop's LuCI app
  and deps will NOT satisfy on the vendor firmware. podkop is only realistic if you move this box to a clean
  OpenWrt 24.10 build for `qualcommax/ipq53xx` (nascent — check support first), OR run it on a different router.
- It also needs the `nft_tproxy` kmod, which the vendor firmware lacks. Clean OpenWrt 24.10 ships it.

## If you ARE on clean OpenWrt 24.10
Easiest — official installer:
```sh
sh <(wget -O - https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/install.sh)
```

## Building the .ipk yourself for a custom arch (Dockerfile-SDK)
Both `itdoginfo/podkop` and `routerich/podkop` ship a **`Dockerfile-SDK`** that builds the packages against the
OpenWrt SDK — so you can target any arch (incl. `aarch64_cortex-a55`) without a local toolchain:
```sh
git clone https://github.com/itdoginfo/podkop && cd podkop
# Edit Dockerfile-SDK to point at the SDK matching YOUR target+release
# (downloads.openwrt.org/.../<target>/<subtarget>/openwrt-sdk-...) then:
docker build -f Dockerfile-SDK -t podkop-sdk .
docker run --rm -v "$PWD/out:/out" podkop-sdk   # .ipk(s) land in ./out
```
Then `opkg install ./out/*.ipk` on the matching OpenWrt. The luci-app-podkop + podkop dirs are the source.

## Bottom line
For the vendor-18.06 boxes this kit targets, stay with the **docker sing-box + this kit's REDIRECT/fakeip**
approach. Treat podkop as the upgrade you adopt **if/when** you flash clean OpenWrt 24.10.
