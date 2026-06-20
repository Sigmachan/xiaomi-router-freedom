# blockctl — блокировка рекламы/трекеров/малвари на весь LAN

Один скрипт. Ставится в одну команду. Режет рекламу, трекеры, малварь и фишинг **для всех устройств в сети** (телефоны, телевизоры, гости) прямо на роутере — через `dnsmasq`, **без прошивки, без `opkg`, без overlay**. Работает на стоковых **Xiaomi на Qualcomm** (IPQ5424 / IPQ9554, MiWiFi OpenWrt-форк).

Источник списка — [`dns.malw.link`](https://dns.malw.link) (ImMALWARE). **Берём только блокирующие записи** `0.0.0.0 <домен>` и **выкидываем гео-прокси пины** — те самые, что роняют AI-сервисы/сайты в «недоступно в регионе», когда у тебя свой туннель (подробно — [`../dns/fix-poisoning.md`](../dns/fix-poisoning.md)).

---

## Установка (30 секунд)

По SSH на роутер (`root`):

```sh
wget -O /tmp/blockctl https://raw.githubusercontent.com/Sigmachan/xiaomi-router-freedom/main/blocklist/blockctl.sh
sh /tmp/blockctl install
```

Всё. Спросит про авто-обновление — согласись, и список будет освежаться сам раз в сутки.

```
  ┌────────────────────────────────────────────┐
  │  Xiaomi Router Freedom · blockctl  v1.0.0   │
  └────────────────────────────────────────────┘
  реклама / трекеры / малварь — блок на весь LAN

:: скачиваю: https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/.../hosts
:: перезапуск dnsmasq
✓  блок работает: 0.0.0.0.hpyrdr.com -> 0.0.0.0
✓  хороший домен резолвится: github.com -> 140.82.121.4
✓  установлено. Заблокировано доменов: 29863
✓  авто-обновление включено (ежедневно 05:17)
```

> Нужен рабочий DNS на роутере, чтобы скачать список с GitHub. На стоке он есть.
> Если GitHub режется — скачай файл на чистой машине и передай: `SRC=... ` (см. `--help`).

---

## Команды

```sh
blockctl status      # что стоит, сколько доменов, когда обновлялось
blockctl update      # обновить список вручную
blockctl auto on     # вкл авто-обновление (cron, ежедневно)
blockctl auto off    # выкл
blockctl disable     # временно отключить (список сохраняется)
blockctl enable      # включить обратно
blockctl uninstall   # снести всё подчистую
```

После установки бинарь лежит в `/data/blockctl` (переживает ребут). Если есть Entware — будет и в `PATH` как `blockctl`.

Флаги: `--en` (вывод на английском), `--yes` (без вопросов), `--no-color`.

---

## Как это устроено (и почему переживает ребут)

На этих роутерах `/etc` — это **ramfs** (обнуляется при перезагрузке), поэтому обычные «положил файл в /etc + cron» хаки ненадёжны. blockctl кладёт всё на **ubifs-разделы**, которые персистентны:

| Что | Куда | Персистентность |
|---|---|---|
| Список доменов | `/data/blocklist/block.hosts` | ubifs ✓ |
| Указатель `dnsmasq` (`addnhosts`) | `/etc/config/dhcp` (UCI) | ubifs ✓ |
| Авто-обновление | `crontab` (`/etc/crontabs`) | ubifs ✓ |

→ **никакого cron-костыля для восстановления после ребута не нужно.** Подключение к `dnsmasq` идёт штатно через `uci add_list ...addnhosts`, так что остальной DNS/split-DNS не ломается.

## Безопасность

- **Только `0.0.0.0`-блоки.** Прокси-пины (которые перехватывают домены на чужие IP) отбрасываются — поэтому твой туннель/Reality ничего не теряет.
- **Allow-list по умолчанию:** AI/dev (`anthropic.com`, `openai.com`, `x.ai`, `claude.ai`, `github*`) **+ ядро Google Play / Android** (`android.clients.google.com`, `dl.google.com`, `play.googleapis.com`, `connectivitycheck.*`, `mtalk.google.com`, `fcm.googleapis.com` …) — чтобы обновления из Play **не висели в «Download pending»** и работали push/проверка сети. Эти домены не заблокируются, даже если попадут в источник. (Сам список malw путь доставки Play и так не трогает — режется только телеметрия вроде `beacons.gvt2.com`.)
- Свои исключения — в `/data/blocklist/allowlist` (по домену в строке), затем `blockctl update`.
- Каждое изменение `dnsmasq` бэкапится в `/data/blocklist/dhcp.bak-*`, и при сбое (если `dnsmasq` не поднимется/не резолвит) — **автоматический откат**.

## Откат вручную

```sh
blockctl uninstall        # или точечно:
uci del_list dhcp.@dnsmasq[0].addnhosts='/data/blocklist/block.hosts'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

---

## English (short)

LAN-wide ad/tracker/malware DNS blocking for stock-firmware Qualcomm Xiaomi routers, via `dnsmasq` — no reflash, no opkg. Pulls `dns.malw.link`, keeps **only** the `0.0.0.0` null-routes, **drops the geo-unblock proxy pins**. Install:

```sh
wget -O /tmp/blockctl https://raw.githubusercontent.com/Sigmachan/xiaomi-router-freedom/main/blocklist/blockctl.sh
sh /tmp/blockctl install --en
```

Everything lives on ubifs (`/data` + `/etc/config` + `/etc/crontabs`) so it **survives reboot with no ramfs/cron hacks**. Commands: `status | update | auto on|off | disable | enable | uninstall`. Critical AI/dev domains are allow-listed; every dnsmasq change is backed up with auto-rollback on failure.

*Research/educational. Use on hardware you own.*
