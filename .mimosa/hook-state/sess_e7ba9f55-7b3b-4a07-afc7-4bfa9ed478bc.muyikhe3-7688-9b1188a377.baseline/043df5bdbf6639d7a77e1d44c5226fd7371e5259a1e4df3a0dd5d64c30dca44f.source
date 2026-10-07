#!/usr/bin/env bash
#===============================================================================
#  GoldWaterTunnel — https://github.com/radkesvat/WaterWall based anti-DPI tunnel
#
#  Architecture (client = Iran, server = abroad):
#    Xray WG outbound -> UdpStatelessSocket -> WireGuardDevice -> PacketsToConnection
#      -> VlessClient (carries each flow's destination inside the tunnel)
#      -> ConnectionFisherClient (racing) -> RealityClient (REAL TLS camouflage)
#      -> TCP:443 -> [server] RealityServer -> ConnectionFisherServer -> VlessServer
#      -> TcpUdpConnector(dest_context) -> Internet
#
#  Roles:
#    install.sh server  --port 443 [--cover www.microsoft.com] [--password X --uuid Y]
#    install.sh client  --server IP --port 443 --password X --uuid Y [options]
#    install.sh print-xray-outbound    (client: print panel outbound JSON)
#    install.sh update                 (upgrade waterwall binary)
#    install.sh uninstall
#===============================================================================
set -euo pipefail

GWT_VERSION="1.0.0"
WATERWALL_VERSION="v1.46.9"
WATERWALL_URL_BASE="https://github.com/radkesvat/WaterWall/releases/download"
GWT_RAW_BASE="https://raw.githubusercontent.com/DashSaman/GoldWaterTunnel/main"
INSTALL_DIR="/etc/goldwater"
LOG_DIR="/var/log/goldwater"
STATE_DIR="/var/lib/goldwater"
BIN="/usr/local/bin/waterwall"
TEST_CMD="/usr/local/bin/WaterWall-Test"
ENV_FILE="$INSTALL_DIR/env"
WG_SUBNET="10.44.0"
FAKE_DNS_ADDR="198.18.0.2"
FAKE_DNS_NET="100.64.0.0"
FAKE_DNS_MASK="255.192.0.0"
FAKE_DNS_CACHE="65536"

C_Green='\033[0;32m'; C_Red='\033[0;31m'; C_Yellow='\033[1;33m'; C_Cyan='\033[0;36m'; C_Off='\033[0m'
say()  { echo -e "${C_Cyan}[*]${C_Off} $*"; }
ok()   { echo -e "${C_Green}[✓]${C_Off} $*"; }
warn() { echo -e "${C_Yellow}[!]${C_Off} $*"; }
die()  { echo -e "${C_Red}[✗]${C_Off} $*"; exit 1; }

require_root() {
  [ "$(id -u)" = "0" ] || die "Please run as root"
  [ "$(uname -m)" = "x86_64" ] || die "This installer targets x86_64 linux"
}

detect_workers() {
  local c; c="$(nproc 2>/dev/null || echo 2)"
  [ "$c" -ge 1 ] 2>/dev/null || c=2
  [ "$c" -gt 16 ] && c=16
  echo "$c"
}

rand_pass() { head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 28; }

# Generate a WireGuard keypair (clamped private, matching public).
# Tries python3+cryptography, then wg (wireguard-tools), then installs wireguard-tools.
WGW_PRIV=""; WGW_PUB=""
gen_wg_keys() {
  local tmp; tmp="$(mktemp)"
  if python3 -c "import cryptography" >/dev/null 2>&1; then
    python3 - > "$tmp" <<'PYEOF'
import os, base64
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives import serialization
k = bytearray(os.urandom(32)); k[0] &= 248; k[31] &= 127; k[31] |= 64
priv = X25519PrivateKey.from_private_bytes(bytes(k))
pub = priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
print(base64.b64encode(bytes(k)).decode()); print(base64.b64encode(pub).decode())
PYEOF
  elif ! command -v wg >/dev/null 2>&1; then
    say "installing wireguard-tools for key generation ..."
    (apt-get update -qq && apt-get install -y -qq wireguard-tools) >/dev/null 2>&1 \
      || die "cannot install key generation tools (no python3-cryptography, no apt wireguard-tools)"
  fi
  if [ ! -s "$tmp" ] && command -v wg >/dev/null 2>&1; then
    { wg genkey; } > "$tmp.priv" 2>/dev/null
    wg pubkey < "$tmp.priv" > "$tmp.pub" 2>/dev/null
    paste -d'\n' "$tmp.priv" "$tmp.pub" > "$tmp"
    shred -u "$tmp.priv" 2>/dev/null || rm -f "$tmp.priv"
  fi
  WGW_PRIV="$(sed -n 1p "$tmp")"
  WGW_PUB="$(sed -n 2p "$tmp")"
  rm -f "$tmp"
  [ -n "$WGW_PRIV" ] && [ -n "$WGW_PUB" ] || die "WireGuard key generation failed"
}

install_binary() {
  if [ -x "$BIN" ] && "$BIN" -v 2>/dev/null | grep -q "$WATERWALL_VERSION"; then
    ok "waterwall $WATERWALL_VERSION already installed"
    return 0
  fi
  local url="$WATERWALL_URL_BASE/$WATERWALL_VERSION/Waterwall-linux-gcc-x64.zip"
  local tmp; tmp="$(mktemp -d)"
  say "Downloading WaterWall $WATERWALL_VERSION ..."
  if command -v unzip >/dev/null 2>&1 && curl -fsSL --retry 3 --connect-timeout 15 -o "$tmp/ww.zip" "$url"; then
    unzip -o -q "$tmp/ww.zip" -d "$tmp/rel"
    install -m 755 "$tmp/rel/Waterwall" "$BIN"
  elif [ -f "${GWT_LOCAL_BIN:-/nonexistent}" ]; then
    install -m 755 "$GWT_LOCAL_BIN" "$BIN"
  else
    die "Download failed. If GitHub is unreachable, download $url on another machine,
copy it to this server, unzip it and re-run with: GWT_LOCAL_BIN=/path/to/Waterwall $0"
  fi
  rm -rf "$tmp"
  "$BIN" -v | head -1
  ok "waterwall installed at $BIN"
}

write_sysctl() {
  local bbr="$1"
  cat > /etc/sysctl.d/99-goldwater.conf <<EOF
# GoldWaterTunnel network tuning
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
EOF
  if [ "$bbr" = "1" ]; then
    cat >> /etc/sysctl.d/99-goldwater.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  fi
  sysctl --system > /dev/null 2>&1 || warn "sysctl apply reported errors (non-fatal)"
  ok "sysctl tuning applied (bbr=$bbr)"
}

write_service() {
  cat > /etc/systemd/system/waterwall.service <<EOF
[Unit]
Description=WaterWall tunnel (GoldWaterTunnel)
Documentation=https://github.com/radkesvat/WaterWall
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN -c:$INSTALL_DIR/core.json
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

write_logrotate() {
  mkdir -p "$LOG_DIR"
  cat > /etc/logrotate.d/goldwater <<EOF
$LOG_DIR/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
}

#===============================================================================
#  SERVER ROLE (abroad)
#===============================================================================
do_server() {
  local PORT="443" COVER="www.microsoft.com" PASSWORD="" WORKERS="" UUID=""
  while [ $# -gt 0 ]; do case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --cover) COVER="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --uuid) UUID="$2"; shift 2 ;;
    --workers) WORKERS="$2"; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac done
  [ -n "$PASSWORD" ] || PASSWORD="$(rand_pass)"
  [ -n "$UUID" ] || UUID="$(cat /proc/sys/kernel/random/uuid)"

  # stop a previous instance so the port check and re-install work cleanly
  systemctl stop waterwall 2>/dev/null || true
  sleep 1

  # port free?
  if ss -tln "sport = :$PORT" 2>/dev/null | grep -q LISTEN; then
    die "TCP port $PORT is already in use by another service. Choose another with --port"
  fi
  WORKERS="${WORKERS:-$(detect_workers)}"

  install_binary
  mkdir -p "$INSTALL_DIR" "$LOG_DIR" "$STATE_DIR"

  say "Writing server config (port=$PORT cover=$COVER workers=$WORKERS)"
  cat > "$INSTALL_DIR/core.json" <<EOF
{
  "log": {
    "path": "$LOG_DIR/",
    "core":    { "loglevel": "info", "file": "core.log",    "console": false },
    "network": { "loglevel": "warn", "file": "network.log", "console": false }
  },
  "dns": { "servers": ["1.1.1.1", "8.8.8.8"] },
  "misc": { "workers": $WORKERS },
  "configs": ["nodes.json"]
}
EOF
  cat > "$INSTALL_DIR/nodes.json" <<EOF
{
  "name": "goldwater-server",
  "nodes": [
    {
      "name": "entry", "type": "TcpListener",
      "settings": { "address": "0.0.0.0", "port": $PORT, "nodelay": true },
      "next": "reality"
    },
    {
      "name": "reality", "type": "RealityServer",
      "settings": {
        "password": "$PASSWORD",
        "algorithm": "aes-gcm",
        "destination": "visitor",
        "sniffing-attempts": 8
      },
      "next": "fisher"
    },
    {
      "name": "fisher", "type": "ConnectionFisherServer",
      "next": "vless"
    },
    {
      "name": "vless", "type": "VlessServer",
      "settings": { "uuid": "$UUID", "connect": true, "udp": true },
      "next": "exit"
    },
    {
      "name": "exit", "type": "TcpUdpConnector",
      "settings": {
        "address": "dest_context->address",
        "port": "dest_context->port",
        "nodelay": true,
        "domain-strategy": "prefer-ipv4"
      }
    },
    {
      "name": "visitor", "type": "TcpConnector",
      "settings": { "address": "$COVER", "port": 443, "nodelay": true }
    }
  ]
}
EOF
  chmod 600 "$INSTALL_DIR/core.json" "$INSTALL_DIR/nodes.json"

  cat > "$ENV_FILE" <<EOF
GWT_ROLE=server
GWT_PORT=$PORT
GWT_COVER=$COVER
GWT_UUID=$UUID
GWT_VERSION=$GWT_VERSION
EOF
  chmod 600 "$ENV_FILE"

  # restricted helper for the client watchdog (forced command via authorized_keys)
  cat > /usr/local/bin/goldwater-remote-restart <<'EOF'
#!/usr/bin/env bash
# Forced-command helper; only reachable through the watchdog's restricted SSH key.
case "${SSH_ORIGINAL_COMMAND:-}" in
  restart) systemctl restart waterwall; echo "remote waterwall restarted $(date '+%F %T')" ;;
  status)  systemctl is-active waterwall ;;
  *) echo "restricted shell"; exit 1 ;;
esac
EOF
  chmod 755 /usr/local/bin/goldwater-remote-restart

  write_service
  write_sysctl 1
  write_logrotate
  install_test_cmd

  systemctl enable waterwall >/dev/null 2>&1
  systemctl restart waterwall
  sleep 2
  systemctl is-active --quiet waterwall || { journalctl -u waterwall --no-pager -n 30; die "waterwall failed to start"; }
  ss -tln "sport = :$PORT" | grep -q LISTEN || die "port $PORT is not listening"
  ok "waterwall server active and listening on TCP:$PORT"

  # firewall hints
  if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "active"; then
    ufw allow "$PORT"/tcp comment 'goldwater' >/dev/null 2>&1 || true
    ok "ufw: allowed $PORT/tcp"
  fi

  cat <<SUMMARY

${C_Green}============================================================
 GoldWaterTunnel SERVER installed successfully
============================================================${C_Off}
  Listen port : TCP $PORT
 Reality pass: $PASSWORD   (needed by the client: --password)
     VLESS id: $UUID       (needed by the client: --uuid)
 Cover domain: $COVER
 Service     : systemctl status waterwall
 Test        : WaterWall-Test

IMPORTANT: keep the Reality password and VLESS uuid safe —
the client role needs the exact same values (--password / --uuid).
SUMMARY
}

#===============================================================================
#  CLIENT ROLE (Iran)
#===============================================================================
do_client() {
  local SERVER="" PORT="443" PASSWORD="" COVER="www.microsoft.com" WG_PORT="51820" \
        TEST_PORT="40000" FISHER="2" WORKERS="" SERVER_SSH="root@" UUID=""
  while [ $# -gt 0 ]; do case "$1" in
    --server) SERVER="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --uuid) UUID="$2"; shift 2 ;;
    --cover) COVER="$2"; shift 2 ;;
    --wg-port) WG_PORT="$2"; shift 2 ;;
    --test-port) TEST_PORT="$2"; shift 2 ;;
    --fisher) FISHER="$2"; shift 2 ;;
    --workers) WORKERS="$2"; shift 2 ;;
    --server-ssh) SERVER_SSH="$2"; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac done
  [ -n "$SERVER" ] || die "--server <foreign-server-ip> is required"
  [ -n "$PASSWORD" ] || die "--password <reality-password> is required (same as server)"
  [ -n "$UUID" ] || UUID="$(cat /proc/sys/kernel/random/uuid)"
  WORKERS="${WORKERS:-$(detect_workers)}"

  install_binary
  mkdir -p "$INSTALL_DIR" "$LOG_DIR" "$STATE_DIR"

  say "Generating WireGuard keys"
  local k_priv k_pub x_priv x_pub t_priv t_pub
  if [ -f "$INSTALL_DIR/keys.env" ]; then
    say "reusing existing keys from $INSTALL_DIR/keys.env"
    # shellcheck disable=SC1090
    . "$INSTALL_DIR/keys.env"
  fi
  [ -n "${WG_DEVICE_PRIV:-}" ] || { gen_wg_keys; k_priv="$WGW_PRIV"; k_pub="$WGW_PUB"; }
  [ -n "${XRAY_PRIV:-}" ]      || { gen_wg_keys; x_priv="$WGW_PRIV"; x_pub="$WGW_PUB"; }
  [ -n "${TEST_PRIV:-}" ]      || { gen_wg_keys; t_priv="$WGW_PRIV"; t_pub="$WGW_PUB"; }
  k_priv="${WG_DEVICE_PRIV:-$k_priv}"; k_pub="${WG_DEVICE_PUB:-$k_pub}"
  x_priv="${XRAY_PRIV:-$x_priv}";       x_pub="${XRAY_PUB:-$x_pub}"
  t_priv="${TEST_PRIV:-$t_priv}";       t_pub="${TEST_PUB:-$t_pub}"
  echo -e "  wg-device : $k_pub"
  echo -e "  xray-peer : $x_pub"
  echo -e "  test-peer : $t_pub"

  say "Writing client config (server=$SERVER:$PORT wg=127.0.0.1:$WG_PORT workers=$WORKERS fisher=$FISHER)"
  cat > "$INSTALL_DIR/core.json" <<EOF
{
  "log": {
    "path": "$LOG_DIR/",
    "core":    { "loglevel": "info", "file": "core.log",    "console": false },
    "network": { "loglevel": "warn", "file": "network.log", "console": false }
  },
  "misc": { "workers": $WORKERS },
  "configs": ["nodes.json"]
}
EOF
  cat > "$INSTALL_DIR/nodes.json" <<EOF
{
  "name": "goldwater-client",
  "nodes": [
    {
      "name": "wg-socket", "type": "UdpStatelessSocket",
      "settings": { "listen-address": "127.0.0.1", "listen-port": $WG_PORT },
      "next": "wg-device"
    },
    {
      "name": "wg-device", "type": "WireGuardDevice",
      "settings": {
        "privatekey": "$k_priv",
        "peers": [
          {
            "publickey": "$x_pub",
            "allowedips": "$WG_SUBNET.2/32",
            "endpoint": "127.0.0.1:12345"
          },
          {
            "publickey": "$t_pub",
            "allowedips": "$WG_SUBNET.3/32",
            "endpoint": "127.0.0.1:12346"
          }
        ]
      },
      "next": "ptc"
    },
    {
      "name": "ptc", "type": "PacketsToConnection",
      "settings": {
        "udp-idle-timeout-ms": 120000,
        "max-pending-bytes": 2097152,
        "fake-dns": {
          "address": "$FAKE_DNS_ADDR",
          "port": 53,
          "network": "$FAKE_DNS_NET",
          "netmask": "$FAKE_DNS_MASK",
          "cache-size": $FAKE_DNS_CACHE,
          "ttl": 5
        }
      },
      "next": "vless"
    },
    {
      "name": "vless", "type": "VlessClient",
      "settings": {
        "uuid": "$UUID",
        "address": "dest_context->address",
        "port": "dest_context->port",
        "protocol": "dest_context->protocol"
      },
      "next": "fisher"
    },
    {
      "name": "fisher", "type": "ConnectionFisherClient",
      "settings": { "simultaneous-tries-perline": $FISHER },
      "next": "reality"
    },
    {
      "name": "reality", "type": "RealityClient",
      "settings": {
        "sni": "$COVER",
        "verify": true,
        "x25519mlkem768": false,
        "password": "$PASSWORD",
        "algorithm": "aes-gcm"
      },
      "next": "uplink"
    },
    {
      "name": "uplink", "type": "TcpConnector",
      "settings": { "address": "$SERVER", "port": $PORT, "nodelay": true }
    },

    {
      "name": "test-listener", "type": "TcpListener",
      "settings": { "address": "127.0.0.1", "port": $TEST_PORT, "nodelay": true },
      "next": "test-socks"
    },
    {
      "name": "test-socks", "type": "Socks5Server",
      "settings": { "no-auth": true, "connect": true },
      "next": "test-vless"
    },
    {
      "name": "test-vless", "type": "VlessClient",
      "settings": {
        "uuid": "$UUID",
        "address": "dest_context->address",
        "port": "dest_context->port",
        "protocol": "dest_context->protocol"
      },
      "next": "test-fisher"
    },
    {
      "name": "test-fisher", "type": "ConnectionFisherClient",
      "settings": { "simultaneous-tries-perline": $FISHER },
      "next": "test-reality"
    },
    {
      "name": "test-reality", "type": "RealityClient",
      "settings": {
        "sni": "$COVER",
        "verify": true,
        "x25519mlkem768": false,
        "password": "$PASSWORD",
        "algorithm": "aes-gcm"
      },
      "next": "test-uplink"
    },
    {
      "name": "test-uplink", "type": "TcpConnector",
      "settings": { "address": "$SERVER", "port": $PORT, "nodelay": true }
    }
  ]
}
EOF
  chmod 600 "$INSTALL_DIR/core.json" "$INSTALL_DIR/nodes.json"

  # store keys for the panel outbound + wireproxy test conf
  cat > "$INSTALL_DIR/keys.env" <<EOF
WG_DEVICE_PRIV=$k_priv
WG_DEVICE_PUB=$k_pub
XRAY_PRIV=$x_priv
XRAY_PUB=$x_pub
TEST_PRIV=$t_priv
TEST_PUB=$t_pub
EOF
  chmod 600 "$INSTALL_DIR/keys.env"

  cat > "$INSTALL_DIR/xray-outbound.json" <<EOF
{
  "tag": "waterwall-wg",
  "protocol": "wireguard",
  "settings": {
    "secretKey": "$x_priv",
    "address": ["$WG_SUBNET.2/32"],
    "peers": [
      {
        "publicKey": "$k_pub",
        "endpoint": "127.0.0.1:$WG_PORT",
        "keepAlive": 25
      }
    ],
    "mtu": 1420,
    "kernelMode": false
  }
}
EOF
  chmod 600 "$INSTALL_DIR/xray-outbound.json"

  cat > "$INSTALL_DIR/wg-test.conf" <<EOF
[Interface]
Address = $WG_SUBNET.3/32
PrivateKey = $t_priv
DNS = $FAKE_DNS_ADDR
MTU = 1420

[Peer]
PublicKey = $k_pub
Endpoint = 127.0.0.1:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

[Socks5]
BindAddress = 127.0.0.1:40099
EOF
  chmod 600 "$INSTALL_DIR/wg-test.conf"

  cat > "$ENV_FILE" <<EOF
GWT_ROLE=client
GWT_SERVER_IP=$SERVER
GWT_SERVER_PORT=$PORT
GWT_COVER=$COVER
GWT_UUID=$UUID
GWT_WG_PORT=$WG_PORT
GWT_TEST_SOCKS=$TEST_PORT
GWT_EXPECTED_EXIT=$SERVER
GWT_SOCKS_TIMEOUT=8
GWT_FAIL_THRESHOLD=3
GWT_CHECK_INTERVAL=20
GWT_WATCHDOG_SSH=$SERVER_SSH$SERVER
GWT_WATCHDOG_KEY=/root/.ssh/id_ed25519_goldwater
GWT_VERSION=$GWT_VERSION
EOF
  chmod 600 "$ENV_FILE"

  write_service
  write_sysctl 0
  write_logrotate
  install_test_cmd
  install_watchdog

  systemctl enable waterwall goldwater-watchdog >/dev/null 2>&1
  systemctl restart waterwall
  sleep 2
  systemctl is-active --quiet waterwall || { journalctl -u waterwall --no-pager -n 40; die "waterwall failed to start"; }
  ss -uln "sport = :$WG_PORT" | grep -q UNCONN || die "UDP:$WG_PORT not listening"
  ss -tln "sport = :$TEST_PORT" | grep -q LISTEN || die "TCP:$TEST_PORT not listening"
  ok "waterwall client active (wg UDP:$WG_PORT, test socks TCP:$TEST_PORT)"

  # end-to-end self test through the tunnel
  say "Running end-to-end probe (socks -> reality -> server -> internet)"
  local probe
  probe="$(curl -s -m 15 --socks5-hostname 127.0.0.1:$TEST_PORT https://api.ipify.org 2>/dev/null || true)"
  if [ "$probe" = "$SERVER" ]; then
    ok "End-to-end OK — exit IP: $probe"
  else
    warn "End-to-end probe returned '${probe:-nothing}'. Check server side + password match."
  fi

  systemctl restart goldwater-watchdog

  cat <<SUMMARY

============================================================
 GoldWaterTunnel CLIENT installed successfully
============================================================
 Server      : $SERVER:$PORT
 WG endpoint : 127.0.0.1:$WG_PORT (for the Xray outbound)
 Test socks  : 127.0.0.1:$TEST_PORT
 Watchdog    : active (every ${GWT_CHECK_INTERVAL:-20}s, restart after 3 verified fails)
 Xray config : $INSTALL_DIR/xray-outbound.json
 Test suite  : WaterWall-Test

 Add the WireGuard outbound to your panel:
   x-ui panel -> Xray Configs -> Outbounds -> add contents of
   $INSTALL_DIR/xray-outbound.json
 Then route any inbound to outbound tag "waterwall-wg".

 Optional (remote restart by watchdog): run on the SERVER:
   grep goldwater /root/.ssh/authorized_keys 2>/dev/null || echo \
     'command="/usr/local/bin/goldwater-remote-restart",no-pty,no-X11-forwarding \\
      <public key printed below>' >> /root/.ssh/authorized_keys
SUMMARY
  echo; echo "Client watchdog public key (for the server's authorized_keys):"
  [ -f /root/.ssh/id_ed25519_goldwater.pub ] && cat /root/.ssh/id_ed25519_goldwater.pub || echo "(key will be generated by install-watchdog)"
}

#===============================================================================
#  Watchdog (client)
#===============================================================================
install_watchdog() {
  if [ ! -f /root/.ssh/id_ed25519_goldwater ]; then
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519_goldwater -C goldwater-watchdog >/dev/null 2>&1 || true
  fi
  fetch_repo_file "watchdog.sh" /usr/local/bin/goldwater-watchdog \
    || die "watchdog.sh not found next to install.sh and GitHub unreachable"

  cat > /etc/systemd/system/goldwater-watchdog.service <<EOF
[Unit]
Description=GoldWaterTunnel watchdog (verified-failure restart)
After=network-online.target waterwall.service
Wants=waterwall.service

[Service]
Type=simple
ExecStart=/usr/local/bin/goldwater-watchdog
Restart=always
RestartSec=5
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  ok "watchdog installed"
}

#===============================================================================
#  WaterWall-Test command
#===============================================================================
fetch_repo_file() { # $1 = repo file name, $2 = destination
  local src
  src="$(dirname "$0")/$1"
  if [ -f "$src" ]; then
    install -m 755 "$src" "$2"
    return 0
  fi
  say "downloading $1 from GitHub ..."
  curl -fsSL --retry 3 --connect-timeout 15 "$GWT_RAW_BASE/$1" -o "$2" 2>/dev/null && chmod 755 "$2" && return 0
  return 1
}

install_test_cmd() {
  fetch_repo_file "WaterWall-Test" "$TEST_CMD" \
    || die "WaterWall-Test not found next to install.sh and GitHub unreachable.
Download manually: curl -fL $GWT_RAW_BASE/WaterWall-Test -o $TEST_CMD && chmod +x $TEST_CMD"
  ok "installed $TEST_CMD"
}

#===============================================================================
#  Misc subcommands
#===============================================================================
do_print_xray() {
  [ -f "$INSTALL_DIR/xray-outbound.json" ] || die "run on the client first"
  cat "$INSTALL_DIR/xray-outbound.json"
}

do_update() {
  local old; old="$("$BIN" -v 2>/dev/null | head -1 || true)"
  install_binary
  systemctl restart waterwall
  ok "updated: $old -> $("$BIN" -v | head -1)"
}

do_uninstall() {
  systemctl disable --now waterwall goldwater-watchdog 2>/dev/null || true
  rm -f /etc/systemd/system/waterwall.service /etc/systemd/system/goldwater-watchdog.service
  systemctl daemon-reload
  rm -f "$BIN" "$TEST_CMD" /usr/local/bin/goldwater-watchdog /usr/local/bin/goldwater-remote-restart
  rm -f /etc/sysctl.d/99-goldwater.conf /etc/logrotate.d/goldwater
  sysctl --system >/dev/null 2>&1 || true
  warn "kept for inspection: $INSTALL_DIR $LOG_DIR $STATE_DIR (remove manually if desired)"
  ok "uninstalled"
}

#===============================================================================
main() {
  require_root
  local cmd="${1:-help}"; [ $# -gt 0 ] && shift || true
  case "$cmd" in
    server)          do_server "$@" ;;
    client)          do_client "$@" ;;
    print-xray-outbound) do_print_xray ;;
    update)          do_update ;;
    uninstall)       do_uninstall ;;
    help|-h|--help)  sed -n '2,16p' "$0" ;;
    *) die "unknown command: $cmd (see help)" ;;
  esac
}
main "$@"
