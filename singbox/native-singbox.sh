#!/bin/sh
# Native sing-box via Entware (/opt) with a docker<->native switch — for Xiaomi Qualcomm vendor-OpenWrt boxes.
# Hard-won gotchas baked in:
#  * The system is MUSL; the official sing-box binary is GLIBC-dynamic. Entware ships glibc → run sing-box
#    through Entware's loader via a wrapper. (DO NOT patchelf the binary — it SEGFAULTS Go binaries.)
#  * The wrapper makes the process show as 'ld-linux-*', so Entware rc.func can't track it → use a PIDFILE.
#  * sing-box rule_set .srs paths in a docker config are container-internal (/etc/sing-box/rs/...) → rewrite
#    them to the native location and copy the .srs over.
#  * On switch, set the docker container restart policy so the two don't fight for the redirect port on boot.
# Prereq: Entware installed (../entware/). Run as root. Usage: native-singbox.sh {install|use-native|use-docker|status}
set -e
SB_VER="${SB_VER:-1.13.13}"; ARCH="${ARCH:-linux-arm64}"
SB_DIR=/opt/etc/sing-box; PIDF=/var/run/singbox-native.pid
DOCKER_BIN="${DOCKER_BIN:-/mnt/usb-XXXX/mi_docker/docker-binaries/docker}"
DOCKER_SOCK="${DOCKER_SOCK:-unix:///var/run/docker1.sock}"; DOCKER_CT="${DOCKER_CT:-sing-box}"
# where your working (docker) config + rs/ live, to seed the native copy:
SRC_CFG="${SRC_CFG:-/mnt/usb-XXXX/mi_docker/sing-box-data/config.json}"
SRC_RS="${SRC_RS:-/mnt/usb-XXXX/mi_docker/sing-box-data/rs}"
DK="$DOCKER_BIN -H $DOCKER_SOCK"; BIN=/opt/bin/sing-box; PATH=/opt/sbin:/opt/bin:$PATH

install() {
  [ -x /opt/bin/opkg ] || { echo "install Entware first"; exit 1; }
  opkg list-installed 2>/dev/null | grep -q '^wget-ssl' || opkg install wget-ssl ca-bundle >/dev/null 2>&1 || true
  LDR=$(ls /opt/lib/ld-linux-aarch64.so.1 2>/dev/null | head -1)
  [ -n "$LDR" ] || { echo "Entware glibc loader not found at /opt/lib"; exit 1; }
  cd /tmp; /opt/bin/wget -O sb.tgz "https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/sing-box-${SB_VER}-${ARCH}.tar.gz"
  rm -rf sbx; mkdir sbx; gzip -dc sb.tgz | tar x -C sbx
  cp "$(find sbx -name sing-box -type f|head -1)" /opt/bin/sing-box.real; chmod +x /opt/bin/sing-box.real
  printf '#!/bin/sh\nexec %s --library-path /opt/lib /opt/bin/sing-box.real "$@"\n' "$LDR" > "$BIN"; chmod +x "$BIN"
  mkdir -p "$SB_DIR"
  [ -f "$SRC_CFG" ] && cp "$SRC_CFG" "$SB_DIR/config.json"
  [ -d "$SRC_RS" ] && cp -a "$SRC_RS" "$SB_DIR/"
  sed -i 's#/etc/sing-box/#/opt/etc/sing-box/#g' "$SB_DIR/config.json" 2>/dev/null || true
  echo "✓ $($BIN version | head -1)"; $BIN check -c "$SB_DIR/config.json" && echo "✓ config valid" || echo "⚠ edit $SB_DIR/config.json"
}
use_native() {
  $BIN check -c "$SB_DIR/config.json" || { echo "config invalid — aborting"; exit 1; }
  $DK update --restart=no "$DOCKER_CT" >/dev/null 2>&1 || true; $DK stop "$DOCKER_CT" >/dev/null 2>&1 || true
  "$BIN" run -c "$SB_DIR/config.json" >/dev/null 2>&1 & echo $! > "$PIDF"; sleep 2
  kill -0 "$(cat $PIDF)" 2>/dev/null && echo "✓ NATIVE active (docker stopped). rollback: $0 use-docker" \
    || { echo "native failed — reverting to docker"; use_docker; }
}
use_docker() {
  [ -f "$PIDF" ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f "$PIDF"; pkill -f sing-box.real 2>/dev/null || true; sleep 1
  $DK update --restart=always "$DOCKER_CT" >/dev/null 2>&1 || true; $DK start "$DOCKER_CT" >/dev/null 2>&1 && echo "✓ DOCKER active"
}
status() { { [ -f "$PIDF" ] && kill -0 "$(cat $PIDF)" 2>/dev/null && echo "native: RUNNING"; } || echo "native: stopped"
           echo -n "docker: "; $DK ps --filter name="$DOCKER_CT" --format '{{.Status}}' 2>/dev/null; }
case "$1" in install) install;; use-native) use_native;; use-docker) use_docker;; status) status;;
  *) echo "Usage: $0 {install|use-native|use-docker|status}"; exit 1;; esac
