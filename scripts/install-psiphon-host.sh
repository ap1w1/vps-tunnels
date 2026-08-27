#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE=swarupsengupta2007/psiphon:latest
REGION=""; SOCKS_PORT=1080; HTTP_PORT=8080; HTTP=1
die(){ echo "Ошибка: $*" >&2; exit 1; }
valid_port(){ [[ $1 =~ ^[0-9]+$ ]] && ((1 <= $1 && $1 <= 65535)); }

ACTION=${1:-install}; shift || true
while (($#)); do case $1 in
  --region) REGION=${2^^}; shift 2;; --socks-port) SOCKS_PORT=$2; shift 2;;
  --http-port) HTTP_PORT=$2; shift 2;; --no-http) HTTP=0; shift;;
  --image) IMAGE=$2; shift 2;; *) die "неизвестный параметр $1";; esac; done
[[ $EUID == 0 ]] || die "запустите от root"

uninstall(){
  systemctl disable --now vps-psiphon.service vps-psiphon-firewall.service 2>/dev/null || true
  docker rm -f vps-psiphon 2>/dev/null || true
  nft delete table inet vps_psiphon 2>/dev/null || true
  rm -f /etc/systemd/system/vps-psiphon{,-firewall}.service /etc/nftables.d/vps-psiphon.nft /etc/vps-psiphon.env
  systemctl daemon-reload; echo "Psiphon удалён"
}
[[ $ACTION != uninstall ]] || { uninstall; exit; }
[[ $ACTION == install ]] || die "действие: install|uninstall"
for c in docker nft systemctl; do command -v "$c" >/dev/null || die "$c не установлен"; done
docker info >/dev/null 2>&1 || die "Docker daemon не запущен"
valid_port "$SOCKS_PORT" || die "неверный SOCKS port"
valid_port "$HTTP_PORT" || die "неверный HTTP port"
[[ $SOCKS_PORT != "$HTTP_PORT" ]] || die "порты должны отличаться"
[[ -z $REGION || $REGION =~ ^[A-Z]{2}$ ]] || die "region должен быть ISO-кодом из 2 букв"

install -d -m 0755 /etc/nftables.d
install -d -m 0700 /opt/vps-psiphon/config
cat >/etc/vps-psiphon.env <<EOF
IMAGE=$IMAGE
REGION=$REGION
SOCKS_PORT=$SOCKS_PORT
HTTP_PORT=$HTTP_PORT
HTTP_ENABLED=$HTTP
EOF
chmod 0600 /etc/vps-psiphon.env

cat >/etc/nftables.d/vps-psiphon.nft <<EOF
table inet vps_psiphon {
  chain input {
    type filter hook input priority -200; policy accept;
    iifname "lo" tcp dport $SOCKS_PORT accept
    tcp dport $SOCKS_PORT counter drop
$( ((HTTP)) && printf '    iifname "lo" tcp dport %s accept\n    tcp dport %s counter drop' "$HTTP_PORT" "$HTTP_PORT" )
$( ((!HTTP)) && printf '    tcp dport %s counter drop' "$HTTP_PORT" )
  }
}
EOF
nft -c -f /etc/nftables.d/vps-psiphon.nft

cat >/etc/systemd/system/vps-psiphon-firewall.service <<'EOF'
[Unit]
Description=Dedicated nftables firewall for Psiphon proxies
Before=vps-psiphon.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '/usr/sbin/nft delete table inet vps_psiphon 2>/dev/null || true; /usr/sbin/nft -f /etc/nftables.d/vps-psiphon.nft'
ExecStop=-/usr/sbin/nft delete table inet vps_psiphon
[Install]
WantedBy=multi-user.target
EOF
cat >/etc/systemd/system/vps-psiphon.service <<'EOF'
[Unit]
Description=Psiphon host-network egress for Remnawave
Requires=docker.service vps-psiphon-firewall.service
After=docker.service network-online.target vps-psiphon-firewall.service
[Service]
EnvironmentFile=/etc/vps-psiphon.env
ExecStartPre=-/usr/bin/docker rm -f vps-psiphon
ExecStart=/bin/sh -c 'args="--rm --name vps-psiphon --network host -e PUID=1000 -e PGID=1000 -e SOCKS_PORT=$SOCKS_PORT -e HTTP_PORT=$HTTP_PORT -v /opt/vps-psiphon/config:/config"; [ -z "$REGION" ] || args="$args -e EGRESS_REGION=$REGION"; exec /usr/bin/docker run $args "$IMAGE"'
ExecStop=/usr/bin/docker stop -t 20 vps-psiphon
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now vps-psiphon-firewall.service vps-psiphon.service
echo "Psiphon установлен: SOCKS5 127.0.0.1:$SOCKS_PORT (host network + nftables)"
