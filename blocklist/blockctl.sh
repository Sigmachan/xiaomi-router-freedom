#!/bin/sh
# ============================================================================
#  blockctl — Xiaomi Router Freedom · LAN-wide DNS blocklist manager
# ----------------------------------------------------------------------------
#  Ad / tracker / malware / phishing blocking for STOCK-firmware Xiaomi
#  (Qualcomm / MiWiFi OpenWrt-fork) routers — no reflash, no opkg, no overlay.
#
#  Pulls the dns.malw.link list, keeps ONLY the "0.0.0.0 <domain>" null-routes
#  (junk blocking) and DROPS the geo-unblock proxy pins (which hijack domains
#  onto third-party proxies and masquerade as DNS poisoning — see ../dns/
#  fix-poisoning.md). Wires the result into dnsmasq via UCI `addnhosts`.
#
#  Persistence: list -> $BL_HOME (ubifs), dnsmasq pointer -> /etc/config (also
#  ubifs on these boxes), cron -> /etc/crontabs (ubifs). Survives reboot with
#  NO ramfs/cron hacks. Idempotent. Backups + auto-rollback on failure.
#
#  Usage:  blockctl <install|update|status|enable|disable|auto|uninstall>
#  Run on the router as root.  Research/educational — use on hardware you own.
# ============================================================================
set -eu

VERSION="1.0.0"
REPO_RAW="https://raw.githubusercontent.com/Sigmachan/xiaomi-router-freedom/main"
SELF_URL="$REPO_RAW/blocklist/blockctl.sh"

# ---------------------------------------------------------------- defaults ---
BL_HOME="${BL_HOME:-/data/blocklist}"
CONFIG="$BL_HOME/config"
HOSTS="$BL_HOME/block.hosts"
ALLOWFILE="$BL_HOME/allowlist"          # user: one domain per line = never block
LOG="$BL_HOME/blocklist.log"
SELF="/data/blockctl"
CRON_LINE="17 5 * * * $SELF update >/dev/null 2>&1"   # daily 05:17 auto-refresh

DNSMASQ_SECTION="${DNSMASQ_SECTION:-}"  # autodetected if empty
SOURCES_DEFAULT="https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/refs/heads/master/hosts"
ALLOW_EXACT_DEFAULT="api.anthropic.com api.console.anthropic.com console.anthropic.com claude.ai api.openai.com chatgpt.com openai.com console.x.ai api.x.ai x.ai raw.githubusercontent.com github.com api.github.com"
MIN_ENTRIES=100

BL_LANG="${BL_LANG:-ru}"
ASSUME_YES="${ASSUME_YES:-0}"

# ------------------------------------------------------------------ colors ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	c_r=$(printf '\033[31m'); c_g=$(printf '\033[32m'); c_y=$(printf '\033[33m')
	c_b=$(printf '\033[36m'); c_d=$(printf '\033[2m'); c_w=$(printf '\033[1m'); c_0=$(printf '\033[0m')
else
	c_r=; c_g=; c_y=; c_b=; c_d=; c_w=; c_0=
fi
pr() { printf '%s\n' "$*"; }

# -------------------------------------------------------------------- i18n ---
# L <ru> <en>  -> prints the active-language string (no newline)
L() { if [ "$BL_LANG" = en ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

# ------------------------------------------------------------ log / output ---
ts()   { date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '----'; }
log()  { mkdir -p "$BL_HOME" 2>/dev/null || true; printf '%s %s\n' "$(ts)" "$*" >>"$LOG" 2>/dev/null || true; }
info() { pr "${c_b}::${c_0} $*"; log "INFO $*"; }
ok()   { pr "${c_g}✓${c_0}  $*"; log "OK $*"; }
warn() { pr "${c_y}!${c_0}  $*" >&2; log "WARN $*"; }
die()  { pr "${c_r}✗${c_0}  $*" >&2; log "ERR $*"; exit 1; }

banner() {
	pr "${c_w}${c_b}"
	pr "  ┌────────────────────────────────────────────┐"
	pr "  │  Xiaomi Router Freedom · blockctl  v$VERSION   │"
	pr "  └────────────────────────────────────────────┘${c_0}"
	pr "  ${c_d}$(L 'реклама / трекеры / малварь — блок на весь LAN' 'ad / tracker / malware blocking for the whole LAN')${c_0}"
	pr ""
}

# ----------------------------------------------------------------- helpers ---
need_root() { [ "$(id -u 2>/dev/null || echo 0)" = 0 ] || die "$(L 'нужен root' 'root required')"; }

have() { command -v "$1" >/dev/null 2>&1; }

fetch() { # fetch <url> <out>
	if   have curl;           then curl -fsSL --max-time 90 "$1" -o "$2"
	elif have wget;           then wget -qO "$2" "$1"
	elif have uclient-fetch;  then uclient-fetch -qO "$2" "$1"
	else return 127; fi
}

load_config() {
	[ -f "$CONFIG" ] && . "$CONFIG" || true
	: "${SOURCES:=$SOURCES_DEFAULT}"
	: "${ALLOW_EXACT:=$ALLOW_EXACT_DEFAULT}"
}

detect_section() {
	[ -n "$DNSMASQ_SECTION" ] && { printf '%s' "$DNSMASQ_SECTION"; return; }
	s=$(uci show dhcp 2>/dev/null | sed -n 's/^dhcp\.\([^.=]*\)=dnsmasq$/\1/p' | head -1)
	[ -n "$s" ] && printf '%s' "$s" || printf '%s' "@dnsmasq[0]"
}

confirm() { # confirm <prompt>
	[ "$ASSUME_YES" = 1 ] && return 0
	[ -t 0 ] || return 0
	printf '%s [y/N] ' "$1"; read -r a 2>/dev/null || a=n
	case "$a" in y|Y|yes|YES|да|Да) return 0;; *) return 1;; esac
}

write_default_config() {
	[ -f "$CONFIG" ] && return 0
	mkdir -p "$BL_HOME"
	cat >"$CONFIG" <<CFG
# blockctl config — edit then: blockctl update
# Источники (через пробел/перенос; берутся только строки 0.0.0.0). Sources (only 0.0.0.0 lines used):
SOURCES="$SOURCES_DEFAULT"
# Доп. популярные (раскомментируй при желании) / extra optional lists:
#   https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
#   https://small.oisd.nl/hosts
# Никогда не блокировать (точное совпадение) / never block (exact match):
ALLOW_EXACT="$ALLOW_EXACT_DEFAULT"
# Секция dnsmasq в UCI (пусто = автоопределение) / dnsmasq UCI section (empty = autodetect):
DNSMASQ_SECTION=""
CFG
	[ -f "$ALLOWFILE" ] || printf '# blockctl: домены-исключения, по одному в строке / one allow-domain per line\n' >"$ALLOWFILE"
}

dnsmasq_running() { pgrep dnsmasq >/dev/null 2>&1; }

# Resolve a name via the local resolver; print first A record.
qa() { nslookup "$1" 127.0.0.1 2>/dev/null | awk '/^Address[ 0-9]*:/{a=$NF} END{print a}'; }

# ============================================================ build + apply ==
build_list() { # builds $HOSTS, sets global BUILT_COUNT
	load_config
	tmp=$(mktemp 2>/dev/null || echo "/tmp/bl.$$"); raw="$tmp.raw"; body="$tmp.body"
	: >"$raw"
	got=0
	for url in $SOURCES; do
		[ -n "$url" ] || continue
		case "$url" in \#*) continue;; esac
		info "$(L 'скачиваю' 'fetching'): $url"
		if fetch "$url" "$tmp"; then
			if [ -s "$tmp" ]; then cat "$tmp" >>"$raw"; got=$((got+1)); else warn "$(L 'пустой ответ' 'empty response')"; fi
		else
			rc=$?; [ "$rc" = 127 ] && die "$(L 'нет curl/wget/uclient-fetch' 'no curl/wget/uclient-fetch')"
			warn "$(L 'не скачалось' 'download failed'): $url"
		fi
	done
	[ "$got" -gt 0 ] || die "$(L 'ни один источник не скачался (проверь DNS — настрой setup-dnsmasq-agh.sh)' 'no source fetched (check DNS — run setup-dnsmasq-agh.sh)')"

	# build allow alternation (exact match) from config + user allowlist file
	allow_terms="$ALLOW_EXACT"
	[ -f "$ALLOWFILE" ] && allow_terms="$allow_terms $(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$ALLOWFILE" 2>/dev/null | tr '\n' ' ')" || true
	# join into one anchored alternation (busybox has no `paste`, so tr+sed)
	allow_re=$(printf '%s' "$allow_terms" | tr ' ' '\n' | grep -vE '^[[:space:]]*$' | sed 's/\./\\./g' | tr '\n' '|' | sed 's/|$//')
	[ -n "$allow_re" ] || allow_re='__none__'

	# KEEP ONLY 0.0.0.0 blocks, normalize, drop localhost + allowlist, dedupe
	grep -E '^[[:space:]]*0\.0\.0\.0[[:space:]]' "$raw" \
		| awk '{print "0.0.0.0 "$2}' \
		| grep -vEi "^0\.0\.0\.0 (localhost|${allow_re})$" \
		| sort -u >"$body"

	n=$(wc -l <"$body" | tr -d ' ')
	[ "$n" -ge "$MIN_ENTRIES" ] || die "$(L 'подозрительно мало записей' 'suspiciously few entries'): $n"

	mkdir -p "$BL_HOME"
	{
		printf '### blockctl — dns.malw.link block-list (0.0.0.0 only) — %s — %s entries\n' "$(ts)" "$n"
		cat "$body"
		printf '### end\n'
	} >"$HOSTS.new"
	mv "$HOSTS.new" "$HOSTS"
	rm -f "$tmp" "$raw" "$body"
	BUILT_COUNT="$n"
}

wire_dnsmasq() {
	need_root
	sec=$(detect_section)
	bak="$BL_HOME/dhcp.bak-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
	cp -a /etc/config/dhcp "$bak" 2>/dev/null || true
	if uci -q get "dhcp.$sec.addnhosts" | tr ' ' '\n' | grep -qx "$HOSTS"; then
		uci del_list "dhcp.$sec.addnhosts=$HOSTS" 2>/dev/null || true
	fi
	uci add_list "dhcp.$sec.addnhosts=$HOSTS"
	uci commit dhcp
	info "$(L 'перезапуск dnsmasq' 'restarting dnsmasq')"
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
	sleep 2
	# health: a good name must still resolve, a junk name must be sinkholed
	good=$(qa github.com)
	test_block=$(awk 'NR==2{print $2}' "$HOSTS")   # line 1 is the header comment
	blk=$(qa "$test_block")
	if [ -z "$good" ] || ! dnsmasq_running; then
		warn "$(L 'dnsmasq не резолвит — откатываю' 'dnsmasq not resolving — rolling back')"
		cp -a "$bak" /etc/config/dhcp 2>/dev/null || true
		/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
		die "$(L 'откат выполнен' 'rolled back')"
	fi
	if [ "$blk" = "0.0.0.0" ]; then
		ok "$(L 'блок работает' 'block active'): $test_block -> 0.0.0.0"
	else
		warn "$(L 'проверка блока не дала 0.0.0.0' 'block check did not return 0.0.0.0'): $test_block -> ${blk:-?}"
	fi
	ok "$(L 'хороший домен резолвится' 'good domain resolves'): github.com -> $good"
}

# ================================================================ commands ===
cmd_update() {
	banner; need_root
	build_list; n="$BUILT_COUNT"
	wire_dnsmasq
	ok "$(L 'готово — заблокировано доменов' 'done — domains blocked'): ${c_w}$n${c_0}"
}

cmd_install() {
	banner; need_root
	mkdir -p "$BL_HOME"
	# place self at $SELF (from local file if possible, else download)
	if [ -f "$0" ] && [ "$0" != "$SELF" ] && head -1 "$0" 2>/dev/null | grep -q '/bin/sh'; then
		cp "$0" "$SELF"
	elif [ ! -f "$SELF" ]; then
		info "$(L 'скачиваю blockctl' 'downloading blockctl')"
		fetch "$SELF_URL" "$SELF" || die "$(L 'не смог получить blockctl' 'could not fetch blockctl')"
	fi
	chmod +x "$SELF" 2>/dev/null || true
	# convenience symlink into a writable bin dir if one exists (Entware etc.)
	for d in /opt/bin /usr/local/bin; do
		[ -d "$d" ] && [ -w "$d" ] && ln -sf "$SELF" "$d/blockctl" 2>/dev/null && break
	done
	write_default_config
	build_list; n="$BUILT_COUNT"
	wire_dnsmasq
	pr ""
	ok "$(L 'установлено. Заблокировано доменов' 'installed. Domains blocked'): ${c_w}$n${c_0}"
	pr "   ${c_d}$(L 'команды' 'commands'):${c_0} ${c_w}$SELF${c_0} status | update | auto | disable | uninstall"
	if confirm "$(L 'Включить авто-обновление списка раз в сутки?' 'Enable daily auto-update?')"; then
		cmd_auto on
	else
		pr "   ${c_d}$(L 'позже' 'later'): $SELF auto on${c_0}"
	fi
}

cmd_status() {
	banner
	load_config
	sec=$(detect_section)
	pr "  ${c_w}$(L 'версия' 'version')${c_0}      : $VERSION"
	if [ -f "$HOSTS" ]; then
		cnt=$(grep -c '^0\.0\.0\.0 ' "$HOSTS" 2>/dev/null || echo 0)
		when=$(date -r "$HOSTS" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')
		pr "  ${c_w}$(L 'список' 'list')${c_0}       : $HOSTS"
		pr "  ${c_w}$(L 'доменов' 'domains')${c_0}     : ${c_g}$cnt${c_0}   ($(L 'обновлён' 'updated') $when)"
	else
		pr "  ${c_w}$(L 'список' 'list')${c_0}       : ${c_y}$(L 'не создан' 'not built')${c_0}"
	fi
	if uci -q get "dhcp.$sec.addnhosts" | tr ' ' '\n' | grep -qx "$HOSTS"; then
		pr "  ${c_w}dnsmasq${c_0}      : ${c_g}$(L 'подключён' 'wired')${c_0} (dhcp.$sec.addnhosts)"
	else
		pr "  ${c_w}dnsmasq${c_0}      : ${c_y}$(L 'не подключён' 'not wired')${c_0}"
	fi
	crontab -l 2>/dev/null | grep -qF "$SELF update" \
		&& pr "  ${c_w}$(L 'авто-обновление' 'auto-update')${c_0} : ${c_g}on${c_0}" \
		|| pr "  ${c_w}$(L 'авто-обновление' 'auto-update')${c_0} : ${c_d}off${c_0}"
	if dnsmasq_running; then
		t=$(grep -m1 '^0\.0\.0\.0 ' "$HOSTS" 2>/dev/null | awk '{print $2}')
		[ -n "$t" ] && pr "  ${c_w}$(L 'тест' 'test')${c_0}         : $t -> $(qa "$t")"
	fi
}

cmd_enable()  { banner; need_root; [ -f "$HOSTS" ] || die "$(L 'сначала install/update' 'run install/update first')"; wire_dnsmasq; ok "$(L 'включено' 'enabled')"; }

cmd_disable() {
	banner; need_root
	sec=$(detect_section)
	uci del_list "dhcp.$sec.addnhosts=$HOSTS" 2>/dev/null || true
	uci commit dhcp
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
	ok "$(L 'выключено (список сохранён, dnsmasq отключён)' 'disabled (list kept, dnsmasq detached)')"
}

cmd_auto() { # auto on|off
	need_root
	case "${1:-on}" in
		on)
			( crontab -l 2>/dev/null | grep -vF "$SELF update"; echo "$CRON_LINE" ) | crontab - 2>/dev/null \
				&& ok "$(L 'авто-обновление включено (ежедневно 05:17)' 'auto-update enabled (daily 05:17)')" \
				|| warn "$(L 'не удалось поставить cron' 'could not set cron')" ;;
		off)
			( crontab -l 2>/dev/null | grep -vF "$SELF update" ) | crontab - 2>/dev/null || true
			ok "$(L 'авто-обновление выключено' 'auto-update disabled')" ;;
		*) die "auto on|off" ;;
	esac
}

cmd_uninstall() {
	banner; need_root
	confirm "$(L 'Полностью удалить blockctl и список?' 'Completely remove blockctl and the list?')" || { info "$(L 'отмена' 'cancelled')"; return 0; }
	sec=$(detect_section)
	uci del_list "dhcp.$sec.addnhosts=$HOSTS" 2>/dev/null || true
	uci commit dhcp
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
	cmd_auto off >/dev/null 2>&1 || true
	rm -rf "$BL_HOME" 2>/dev/null || true
	for d in /opt/bin /usr/local/bin; do [ -L "$d/blockctl" ] && rm -f "$d/blockctl"; done
	rm -f "$SELF" 2>/dev/null || true
	ok "$(L 'удалено' 'removed')"
}

usage() {
	banner
	cat <<USAGE
  $(L 'Использование' 'Usage'): blockctl <$(L 'команда' 'command')>

    install      $(L 'установить и применить (по умолчанию)' 'install and apply (default)')
    update       $(L 'обновить список с источников' 'refresh the list from sources')
    status       $(L 'показать состояние' 'show status')
    enable       $(L 'подключить к dnsmasq' 'attach to dnsmasq')
    disable      $(L 'отключить (список сохраняется)' 'detach (list kept)')
    auto on|off  $(L 'авто-обновление по cron' 'cron auto-update')
    uninstall    $(L 'удалить всё' 'remove everything')
    version      $(L 'версия' 'version')

  $(L 'Флаги' 'Flags'): --en ($(L 'английский вывод' 'English output'))  --yes ($(L 'без вопросов' 'non-interactive'))  --no-color
  $(L 'Конфиг' 'Config'): $CONFIG   $(L 'Лог' 'Log'): $LOG
USAGE
}

# ================================================================== main =====
CMD=""; SUBARG=""
for a in "$@"; do
	case "$a" in
		--en) BL_LANG=en ;;
		--ru) BL_LANG=ru ;;
		--yes|-y) ASSUME_YES=1 ;;
		--no-color) c_r=; c_g=; c_y=; c_b=; c_d=; c_w=; c_0= ;;
		-h|--help) CMD=help ;;
		--*) ;;
		*) if [ -z "$CMD" ]; then CMD="$a"; elif [ -z "$SUBARG" ]; then SUBARG="$a"; fi ;;
	esac
done

case "${CMD:-install}" in
	install)        cmd_install ;;
	update|refresh) cmd_update ;;
	status|st)      cmd_status ;;
	enable)         cmd_enable ;;
	disable)        cmd_disable ;;
	auto)           cmd_auto "${SUBARG:-on}" ;;
	uninstall|rm)   cmd_uninstall ;;
	version|-v)     echo "blockctl $VERSION" ;;
	help|*)         usage ;;
esac
