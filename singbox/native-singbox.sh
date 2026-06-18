#!/bin/sh
# Native sing-box via Entware (/opt) with a docker<->native switch.
# For Xiaomi Qualcomm vendor-OpenWrt boxes where sing-box usually runs in docker — this gives a
# native alternative on the same redirect port, so you can flip between them.
# Prereq: Entware installed (see ../entware/). Run as root.
# Usage: native-singbox.sh {install|use-native|use-docker|status}
set -e
SB_VER="${SB_VER:-1.13.13}"
ARCH="${ARCH:-linux-arm64}"
SB_DIR=/opt/etc/sing-box
DOCKER_BIN="${DOCKER_BIN:-/mnt/usb-XXXX/mi_docker/docker-binaries/docker}"
DOCKER_SOCK="${DOCKER_SOCK:-unix:///var/run/docker1.sock}"
DOCKER_CT="${DOCKER_CT:-sing-box}"
DK="$DOCKER_BIN -H $DOCKER_SOCK"
PATH=/opt/sbin:/opt/bin:$PATH

install() {
  [ -x /opt/bin/opkg ] || { echo "Entware /opt not found — install Entware first"; exit 1; }
  mkdir -p "$SB_DIR" /opt/etc/init.d
  opkg list-installed 2>/dev/null | grep -q '^wget-ssl' || opkg install wget-ssl ca-bundle 2>/dev/null || true
  WGET=/opt/bin/wget; [ -x "$WGET" ] || WGET=wget
  URL="https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/sing-box-${SB_VER}-${ARCH}.tar.gz"
  echo "↓ $URL"
  cd /tmp && $WGET -O /tmp/sb.tgz "$URL" && tar xzf /tmp/sb.tgz
  cp "/tmp/sing-box-${SB_VER}-${ARCH}/sing-box" /opt/bin/sing-box && chmod +x /opt/bin/sing-box
  if [ ! -f "$SB_DIR/config.json" ]; then
    echo "⚠ put your config at $SB_DIR/config.json (copy your working one, or use config.template.json)"
  fi
  cat > /opt/etc/init.d/S99sing-box <<'EOS'
#!/bin/sh
ENABLED=yes
PROCS=sing-box
ARGS="run -c /opt/etc/sing-box/config.json"
PREARGS=""
DESC="sing-box"
PATH=/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin
. /opt/etc/init.d/rc.func
EOS
  chmod +x /opt/etc/init.d/S99sing-box
  echo "✓ installed: $(/opt/bin/sing-box version | head -1)"
  echo "  Persistence: Entware's rc.unslung (started by the /data/entware-mount.sh hook) runs S99sing-box on boot."
}
check() { /opt/bin/sing-box check -c "$SB_DIR/config.json" && echo "config OK"; }
use_native() {
  check
  $DK stop "$DOCKER_CT" 2>/dev/null && echo "docker sing-box stopped" || true
  /opt/etc/init.d/S99sing-box restart
  echo "✓ NATIVE sing-box active (docker stopped). Rollback: $0 use-docker"
}
use_docker() {
  /opt/etc/init.d/S99sing-box stop 2>/dev/null && echo "native stopped" || true
  $DK start "$DOCKER_CT" && echo "✓ DOCKER sing-box active (native stopped)."
}
status() {
  echo -n "native: "; pgrep -f "/opt/bin/sing-box" >/dev/null && echo "RUNNING" || echo "stopped"
  echo -n "docker: "; $DK ps --filter name="$DOCKER_CT" --format '{{.Status}}' 2>/dev/null || echo "?"
}
case "$1" in
  install) install ;;
  use-native) use_native ;;
  use-docker) use_docker ;;
  status) status ;;
  *) echo "Usage: $0 {install|use-native|use-docker|status}"; exit 1 ;;
esac
