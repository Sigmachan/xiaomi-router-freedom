#!/bin/sh
# Full rollback of install.sh — reverts /opt to firmware squashfs.
USB_ROOT="${USB_ROOT:-/mnt/usb-XXXX}"
sed -i '/entware-mount/d' /etc/crontabs/root 2>/dev/null || true
{ /etc/init.d/cron restart || /etc/init.d/crond restart; } 2>/dev/null || true
rm -f /data/entware-mount.sh
[ -x /opt/etc/init.d/rc.unslung ] && /opt/etc/init.d/rc.unslung stop 2>/dev/null || true
grep -q " /opt " /proc/mounts && umount /opt || echo "/opt not mounted"
rm -rf "$USB_ROOT/entware"
echo "DONE: /opt restored to firmware squashfs."
