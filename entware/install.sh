#!/bin/sh
# Entware installer for Xiaomi Qualcomm vendor-OpenWrt routers (read-only squashfs /opt).
# Installs Entware into /opt bind-mounted onto a USB drive, preserving any firmware /opt contents
# (e.g. /opt/filetunnel). Run as root over SSH:  sh install.sh
# Reversible:  sh uninstall.sh
set -e

# ---- CONFIG: set this to your USB mount ----
USB_ROOT="${USB_ROOT:-/mnt/usb-XXXX}"          # <-- EDIT or export USB_ROOT=...
ENTWARE_VARIANT="${ENTWARE_VARIANT:-aarch64-k3.10}"  # aarch64-k3.10 for IPQ5424/9554 (musl)
# --------------------------------------------

USB="$USB_ROOT/entware"
FT_BACKUP=/tmp/opt-orig

[ "$(id -u)" = "0" ] || { echo "run as root"; exit 1; }
[ -d "$USB_ROOT" ] || { echo "USB '$USB_ROOT' not mounted — set USB_ROOT"; exit 1; }

echo "[1/6] save existing /opt (firmware, from squashfs) before we shadow it"
rm -rf "$FT_BACKUP"; mkdir -p "$FT_BACKUP"; cp -a /opt/. "$FT_BACKUP"/ 2>/dev/null || true

echo "[2/6] empty entware dir + bind-mount over /opt"
mkdir -p "$USB"
grep -q " /opt " /proc/mounts || mount -o bind "$USB" /opt

echo "[3/6] restore firmware /opt contents into the new (writable) /opt"
cp -a "$FT_BACKUP"/. /opt/ 2>/dev/null || true

echo "[4/6] fetch + run Entware generic installer (http: busybox wget has no TLS)"
cd /tmp
wget -O /tmp/generic.sh "http://bin.entware.net/$ENTWARE_VARIANT/installer/generic.sh"
sh /tmp/generic.sh

echo "[5/6] persistence (/etc is ramfs and resets on boot; /data + /etc/crontabs are persistent)"
cat > /data/entware-mount.sh <<EOS
#!/bin/sh
grep -q " /opt " /proc/mounts || mount -o bind "$USB" /opt
[ -x /opt/etc/init.d/rc.unslung ] && /opt/etc/init.d/rc.unslung start 2>/dev/null
EOS
chmod +x /data/entware-mount.sh
CRON=/etc/crontabs/root; touch "$CRON"
grep -q entware-mount "$CRON" || echo '* * * * * /data/entware-mount.sh >/dev/null 2>&1' >> "$CRON"
{ /etc/init.d/cron restart || /etc/init.d/crond restart; } 2>/dev/null || true

echo "[6/6] verify"
/opt/bin/opkg update && echo "ENTWARE OK" && /opt/bin/opkg --version | head -1
echo "Add to PATH:  export PATH=/opt/bin:/opt/sbin:\$PATH"
echo "Note: Entware aarch64 repo has xray-core (not sing-box). For native sing-box, drop the official"
echo "      linux-arm64 static binary from github.com/SagerNet/sing-box/releases into /opt/bin/sing-box."
