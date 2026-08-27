#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WTM_COMMIT=d00c18443dbd66d8e55ef7245956d835205c9b6d
SELFSTEAL_COMMIT=d00c18443dbd66d8e55ef7245956d835205c9b6d
WTM_SHA256=06b0028212a79cff4737bcbf2e0ef7accfc063240f4b4df30db76552bc228ca4
SELFSTEAL_SHA256=3594f3a4ddae19582f9dde95fdf65edeaf2892dec662eadabba55e1f8faff4c4

die() { echo "Ошибка: $*" >&2; exit 1; }
need_root() { [[ $EUID == 0 ]] || die "запустите от root"; }
fetch_run() {
  local name=$1 commit=$2 sha=$3; shift 3
  local url="https://raw.githubusercontent.com/DigneZzZ/remnawave-scripts/$commit/$name.sh" tmp
  tmp=$(mktemp); trap 'rm -f "$tmp"' RETURN
  curl --fail --silent --show-error --location "$url" -o "$tmp"
  echo "$sha  $tmp" | sha256sum --check --status || die "неверная контрольная сумма $name.sh"
  bash "$tmp" @ "$@"
}
install_warp() { fetch_run wtm "$WTM_COMMIT" "$WTM_SHA256" install-warp; }
install_tor() { fetch_run wtm "$WTM_COMMIT" "$WTM_SHA256" install-tor; }

REGION=""; SOCKS_PORT=1080; HTTP_PORT=8080; HTTP=1; DOMAIN=""; SERVER=nginx
parse() {
  while (($#)); do case $1 in
    --region) REGION=${2:?}; shift 2;; --socks-port) SOCKS_PORT=${2:?}; shift 2;;
    --http-port) HTTP_PORT=${2:?}; shift 2;; --no-http) HTTP=0; shift;;
    --domain) DOMAIN=${2:?}; shift 2;; --selfsteal) SERVER=${2:?}; shift 2;;
    *) die "неизвестный параметр: $1";; esac; done
}
install_psiphon() {
  local a=(--socks-port "$SOCKS_PORT" --http-port "$HTTP_PORT")
  [[ -z $REGION ]] || a+=(--region "$REGION"); ((HTTP)) || a+=(--no-http)
  "$ROOT/scripts/install-psiphon-host.sh" install "${a[@]}"
}
install_selfsteal() {
  [[ -n $DOMAIN ]] || die "для Selfsteal нужен --domain"
  local a=(--force --domain "$DOMAIN"); [[ $SERVER == nginx ]] && a=(--nginx "${a[@]}")
  [[ $SERVER == nginx || $SERVER == caddy ]] || die "--selfsteal: nginx или caddy"
  fetch_run selfsteal "$SELFSTEAL_COMMIT" "$SELFSTEAL_SHA256" "${a[@]}" install
}
status() {
  systemctl --no-pager --full status wg-quick@warp tor vps-psiphon vps-psiphon-firewall 2>/dev/null || true
  command -v selfsteal >/dev/null && selfsteal status || true
}
menu() {
  echo "1) Всё  2) WARP  3) Psiphon  4) Tor  5) Selfsteal  6) Статус  0) Выход"
  read -rp "> " n
  case $n in 1) ACTION=all;; 2) ACTION=warp;; 3) ACTION=psiphon;; 4) ACTION=tor;;
    5) ACTION=selfsteal;; 6) ACTION=status;; 0) exit;; *) die "неверный выбор";; esac
}

need_root; command -v curl >/dev/null || die "curl не установлен"
ACTION=${1:-menu}; [[ $# == 0 ]] || shift; parse "$@"; [[ $ACTION != menu ]] || menu
case $ACTION in
  warp) install_warp;; tor) install_tor;; psiphon) install_psiphon;; selfsteal) install_selfsteal;;
  all) install_warp; install_tor; install_psiphon; install_selfsteal;; status) status;;
  uninstall) echo "Используйте команды удаления из README (удаление намеренно не автоматизировано).";;
  *) die "команда: menu|all|warp|tor|psiphon|selfsteal|status|uninstall";;
esac
