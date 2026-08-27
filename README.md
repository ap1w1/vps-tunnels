# VPS Tunnels

Единый установщик выходных туннелей для VPS с Remnawave: **WARP, Psiphon,
Tor** и **Selfsteal**. Проект объединяет проверенные сценарии
[`vps-warp`](https://github.com/tagashi666/vps-warp),
[`vps-psiphon`](https://github.com/Chara-Freedom/vps-psiphon) и
[`remnawave-scripts`](https://github.com/DigneZzZ/remnawave-scripts), но
устанавливает Psiphon в специально изолированном режиме.

## Особенности

- одно меню и неинтерактивный CLI для всех компонентов;
- WARP и Tor устанавливаются через зафиксированную ревизию `wtm.sh`;
- Selfsteal (Caddy или Nginx) — через зафиксированную ревизию upstream;
- Psiphon запускается с `--network host`: Docker не создаёт DNAT, bridge и
  правила для RFC1918, поэтому правила Remnawave не ломают туннель;
- SOCKS/HTTP Psiphon закрыты отдельной таблицей nftables: доступны только с
  loopback, снаружи пакеты отбрасываются **до** остальных правил;
- systemd автоматически запускает контейнер и восстанавливает firewall.

## Требования

Ubuntu/Debian или совместимый Linux с systemd, запуск от `root`. Для Psiphon
нужны Docker, nftables и curl. У WARP/Tor есть собственная установка
зависимостей. Перед Selfsteal домен должен указывать на VPS.

## Быстрый старт

```bash
git clone https://github.com/OWNER/vps-tunnels.git
cd vps-tunnels
sudo ./install.sh
```

Неинтерактивно:

```bash
sudo ./install.sh all --domain reality.example.com --selfsteal nginx
sudo ./install.sh psiphon --region NL
sudo ./install.sh warp
sudo ./install.sh tor
```

Команды: `menu`, `all`, `warp`, `tor`, `psiphon`, `selfsteal`, `status`,
`uninstall`. Общие параметры:

| Параметр | Назначение |
|---|---|
| `--region CC` | страна выхода Psiphon |
| `--socks-port N` | SOCKS5 Psiphon (1080) |
| `--http-port N` | HTTP proxy Psiphon (8080) |
| `--no-http` | не запускать HTTP proxy |
| `--domain DOMAIN` | домен Selfsteal |
| `--selfsteal nginx\|caddy` | сервер маскировки (nginx) |

## Интеграция с Remnawave/Xray

Psiphon доступен Xray, работающему в host network, по `127.0.0.1:1080`:

```json
{
  "tag": "psiphon-out",
  "protocol": "socks",
  "settings": { "servers": [{ "address": "127.0.0.1", "port": 1080 }] }
}
```

Только TCP следует направлять в этот outbound. Контейнер Remnanode должен
использовать `network_mode: host`; bridge-контейнер намеренно не получает доступ
к SOCKS. Это исключает публикацию proxy в Docker/RFC1918-сетях.

Готовые сниппеты WARP и Tor после установки находятся в
`/etc/wireguard/warp-xray-outbound.json` и выводятся командой `wtm
xray-examples`. Для Selfsteal установщик использует Nginx по умолчанию;
инструкцию с `target`, `xver` и Unix socket покажет `selfsteal guide`.

## Проверка безопасности Psiphon

```bash
systemctl status vps-psiphon vps-psiphon-firewall
nft list table inet vps_psiphon
curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me
ss -lntp | grep -E ':1080|:8080'
```

Даже если процесс слушает `0.0.0.0`, цепочка `input` с приоритетом `-200`
разрешает эти порты только через `lo`, а остальные входящие подключения
отбрасывает. Конфигурация: `/etc/vps-psiphon.env`; управление:
`systemctl restart vps-psiphon` и `journalctl -u vps-psiphon`.

## Удаление

```bash
sudo ./install.sh uninstall              # интерактивный выбор
sudo ./scripts/install-psiphon-host.sh uninstall
sudo wtm remove-warp
sudo wtm remove-tor
sudo selfsteal uninstall
```

Upstream-файлы скачиваются только по закреплённым commit URL и проверяются
SHA-256, чтобы изменение ветки `main` не подменило выполняемый root-скрипт.

## Лицензия

MIT. Загружаемые компоненты сохраняют лицензии и авторство их проектов.
