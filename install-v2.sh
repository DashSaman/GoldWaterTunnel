#!/usr/bin/env bash
#===============================================================================
#  GoldWaterTunnel v2 — Direct WireGuard backup tunnels
#
#  Creates kernel-level WireGuard tunnels between your Iran server and foreign
#  exit servers. Works on ANY CPU (no AVX2 needed). Deployable in 2 minutes.
#
#  Two modes:
#    1) DEDICATED: Iran has a public IP directly on the server
#    2) NAT-ONLY: Iran server sits behind MikroTik/other NAT router
#       (script auto-detects and prints the router rules you need)
#
#  Usage:
#    Foreign:   install-v2.sh server [--port N]
#    Iran:      install-v2.sh client --server FOREIGN_IP [--port N]
#               [--server-pub KEY] [--nat]
#    Print:     install-v2.sh outbound FOREIGN_IP
#    Test:      install-v2.sh test FOREIGN_IP
#===============================================================================
set -euo pipefail

GWT_VERSION="2.0.0"
WG_DIR="/etc/wireguard"
GWT_DIR="/etc/goldwater-v2"

C_Green='\033[0;32m'; C_Red='\033[0;31m'; C_Yellow='\033[1;33m'; C_Cyan='\033[0;36m'; C_Off='\033[0m'
say()  { echo -e "${C_Cyan}[*]${C_Off} $*"; }
ok()   { echo -e "${C_Green}[✓]${C_Off} $*"; }
warn() { echo -e "${C_Yellow}[!]${C_Off} $*"; }
die()  { echo -e "${C_Red}[✗]${C_Off} $*" >&2; exit 1; }

require_root() { [ "$(id -u)" = "0" ] || die "Run as root"; }

ensure_wg() {
  command -v wg >/dev/null 2>&1 && return 0
  say "Installing wireguard-tools ..."
  export DEBIAN_FRONTEND=noninteractive
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq wireguard-tools >/dev/null
  else
    die "Only Ubuntu/Debian supported. Install wireguard-tools manually."
  fi
  command -v wg >/dev/null 2>&1 || die "wireguard-tools installation failed"
}

detect_public_ip() {
  local ip=""
  ip=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null) || true
  [ -z "$ip" ] && ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
  [ -z "$ip" ] && ip="unknown"
  printf '%s' "$ip"
}

detect_local_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || echo ""
}

is_private() {
  [[ "$1" =~ ^10\. ]] || [[ "$1" =~ ^192\.168\. ]] || [[ "$1" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]
}

#===============================================================================
# SERVER (foreign)
#===============================================================================
do_server() {
  local PORT=52000
  while [ $# -gt 0 ]; do case "$1" in
    --port) PORT="$2"; shift 2 ;;
    *) shift ;;
  esac done

  require_root
  ensure_wg

  local IFNAME="gwt0"
  local NET="10.70.0"
  local PUB_IP
  PUB_IP=$(detect_public_ip)

  # Clean old
  wg-quick down "$IFNAME" 2>/dev/null || true

  local PRIV PUB
  PRIV=$(wg genkey)
  PUB=$(echo "$PRIV" | wg pubkey)

  mkdir -p "$WG_DIR" "$GWT_DIR"
  cat > "$WG_DIR/$IFNAME.conf" <<EOF
[Interface]
PrivateKey = $PRIV
Address = ${NET}.1/24
ListenPort = $PORT
Table = off
PostUp = sysctl -qw net.ipv4.ip_forward=1; iptables -I FORWARD 1 -i %i -j ACCEPT; iptables -I FORWARD 1 -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -I POSTROUTING 1 -s ${NET}.0/24 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -s ${NET}.0/24 -j MASQUERADE
EOF
  chmod 600 "$WG_DIR/$IFNAME.conf"

  echo "GWT_IF=$IFNAME" > "$GWT_DIR/server.env"
  echo "GWT_PORT=$PORT" >> "$GWT_DIR/server.env"
  echo "GWT_PUB=$PUB" >> "$GWT_DIR/server.env"
  echo "GWT_IP=$PUB_IP" >> "$GWT_DIR/server.env"
  chmod 600 "$GWT_DIR/server.env"

  iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -p udp --dport "$PORT" -j ACCEPT

  systemctl enable "wg-quick@$IFNAME" >/dev/null 2>&1
  wg-quick up "$IFNAME" 2>/dev/null || systemctl restart "wg-quick@$IFNAME"

  ok "Server WireGuard active on $PUB_IP:$PORT"
  echo ""
  echo "════════════════════════════════════════════"
  echo "  Server public key: $PUB"
  echo "  Server IP:         $PUB_IP"
  echo "  Port:              $PORT"
  echo "════════════════════════════════════════════"
  echo ""
  echo "Now run on the IRAN server:"
  echo "  install-v2.sh client --server $PUB_IP --port $PORT --server-pub $PUB"
  echo "It prints an 'addpeer' command — run that HERE to finish."
}

#===============================================================================
# CLIENT (Iran)
#===============================================================================
do_client() {
  local SERVER="" PORT="52000" SERVER_PUB="" NAT_MODE=""
  while [ $# -gt 0 ]; do case "$1" in
    --server)      SERVER="$2"; shift 2 ;;
    --port)        PORT="$2"; shift 2 ;;
    --server-pub)  SERVER_PUB="$2"; shift 2 ;;
    --nat)         NAT_MODE="1"; shift ;;
    *) shift ;;
  esac done

  [ -n "$SERVER" ] || die "--server <foreign-ip> required"
  [ -n "$SERVER_PUB" ] || die "--server-pub <key> required (from server output)"
  [[ "$SERVER" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "--server must be an IPv4 address"

  require_root
  ensure_wg

  # Auto-detect NAT vs dedicated
  local LOCAL_IP PUBLIC_IP
  LOCAL_IP=$(detect_local_ip)
  PUBLIC_IP=$(detect_public_ip)
  local IS_NAT=0
  if is_private "$LOCAL_IP" || [ "$LOCAL_IP" != "$PUBLIC_IP" ]; then
    IS_NAT=1
    [ -z "$NAT_MODE" ] && NAT_MODE="1"
  fi

  # Interface name from IP last octet (max 12 chars, no dots)
  local LAST
  LAST=$(echo "$SERVER" | awk -F. '{print $4}')
  [[ "$LAST" =~ ^[0-9]+$ ]] || LAST=0
  local IFNAME="gwt${LAST}"
  # One flat tunnel subnet 10.70.0.0/24 (server holds 10.70.0.1).
  # Each foreign server gets a unique host address derived from its last octet.
  local NET="10.70.0"
  local ADDR="${NET}.$(( (LAST % 249) + 2 ))"

  local PRIV PUB
  PRIV=$(wg genkey)
  PUB=$(echo "$PRIV" | wg pubkey)

  mkdir -p "$WG_DIR" "$GWT_DIR/$SERVER"
  cat > "$WG_DIR/$IFNAME.conf" <<EOF
[Interface]
PrivateKey = $PRIV
Address = ${ADDR}/32
Table = off
MTU = 1380

[Peer]
PublicKey = $SERVER_PUB
Endpoint = ${SERVER}:${PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 15
EOF
  chmod 600 "$WG_DIR/$IFNAME.conf"

  # Save for outbound generation
  cat > "$GWT_DIR/$SERVER/client.env" <<EOF
GWT_CLIENT_PRIV=$PRIV
GWT_CLIENT_PUB=$PUB
GWT_SERVER_PUB=$SERVER_PUB
GWT_SERVER=$SERVER
GWT_PORT=$PORT
GWT_NET=$NET
GWT_ADDR=$ADDR
GWT_GW=${NET}.1
GWT_IF=$IFNAME
EOF
  chmod 600 "$GWT_DIR/$SERVER/client.env"

  wg-quick up "$IFNAME" 2>/dev/null || true

  if [ "$IS_NAT" = "1" ]; then
    warn "NAT mode detected (local=$LOCAL_IP public=$PUBLIC_IP)"
    warn "No router changes needed — WireGuard UDP punches through NAT."
    warn "If the tunnel doesn't connect, forward UDP port $PORT to $LOCAL_IP on your router."
  else
    ok "Dedicated IP mode (public IP on this server)"
  fi

  ok "Client WireGuard configured: $IFNAME ($ADDR) -> $SERVER:$PORT"
  echo ""
  echo "Run this ONE command on the SERVER:"
  echo ""
  echo "  install-v2.sh addpeer --pub $PUB --ip $ADDR"
  echo ""
  echo "Xray outbound JSON (paste into 3x-ui panel):"
  echo "  $0 outbound $SERVER"
}

#===============================================================================
# ADDPEER (foreign — attach an Iran client, zero downtime)
#===============================================================================
do_addpeer() {
  local PUB="" IP=""
  while [ $# -gt 0 ]; do case "$1" in
    --pub) PUB="$2"; shift 2 ;;
    --ip)  IP="$2"; shift 2 ;;
    *) shift ;;
  esac done

  [ -n "$PUB" ] || die "--pub <client-public-key> required"
  [ -n "$IP" ]  || die "--ip <client-tunnel-ip> required"
  [ -f "$GWT_DIR/server.env" ] || die "Server mode not set up here (run server first)"
  # shellcheck disable=SC1090
  source "$GWT_DIR/server.env"

  wg set "$GWT_IF" peer "$PUB" allowed-ips "$IP/32" 2>/dev/null || \
    die "wg set failed (is $GWT_IF up?)"
  grep -q "$PUB" "$WG_DIR/$GWT_IF.conf" || cat >> "$WG_DIR/$GWT_IF.conf" <<EOF

[Peer]
PublicKey = $PUB
AllowedIPs = $IP/32
EOF

  ok "Peer $IP live on $GWT_IF (persisted to config)"
}

#===============================================================================
# OUTBOUND (print Xray JSON)
#===============================================================================
do_outbound() {
  local SERVER="${1:?Usage: outbound FOREIGN_IP}"
  local env_file="$GWT_DIR/$SERVER/client.env"
  [ -f "$env_file" ] || die "No client config for $SERVER (run client first)"
  # shellcheck disable=SC1090
  source "$env_file"

  cat <<EOF
{
  "tag": "WaterWall-${GWT_SERVER}",
  "protocol": "wireguard",
  "settings": {
    "secretKey": "${GWT_CLIENT_PRIV}",
    "address": ["${GWT_ADDR:-${GWT_NET}.2}/32"],
    "peers": [{
      "publicKey": "${GWT_SERVER_PUB}",
      "endpoint": "${GWT_SERVER}:${GWT_PORT}",
      "keepAlive": 15
    }],
    "mtu": 1380,
    "kernelMode": false
  }
}
EOF
}

#===============================================================================
# TEST (verify tunnel works)
#===============================================================================
do_test() {
  local SERVER="${1:?Usage: test FOREIGN_IP}"
  local env_file="$GWT_DIR/$SERVER/client.env"
  [ -f "$env_file" ] || die "No client config for $SERVER"
  source "$env_file"

  say "Testing tunnel to $SERVER ..."
  if ip link show "$GWT_IF" >/dev/null 2>&1; then
    local HS AGE WAITED=0
    # a fresh peer may need a few seconds to complete its first handshake
    while [ "$WAITED" -lt 20 ]; do
      HS=$(wg show "$GWT_IF" latest-handshakes 2>/dev/null | awk '{print $2}')
      AGE=$(( $(date +%s) - ${HS:-0} ))
      [ -n "$HS" ] && [ "$HS" != "0" ] && [ "$AGE" -lt 180 ] && break
      sleep 2; WAITED=$((WAITED+2))
    done
    if [ "$AGE" -lt 180 ]; then
      ok "Handshake fresh (${AGE}s ago)"
    else
      warn "Handshake stale (${AGE}s ago) — tunnel may be down"
    fi
    # Ping the tunnel gateway (server holds 10.70.0.1)
    if ping -c 3 -W 2 -I "$GWT_IF" "${GWT_GW:-10.70.0.1}" >/dev/null 2>&1; then
      ok "Ping through tunnel: PASS"
    else
      warn "Ping through tunnel: FAIL"
    fi
    # Exit IP test (temporary host route — Table=off means no default route via WG)
    local CHECK_IP EXIT
    CHECK_IP=$(python3 -c 'import socket;print(socket.gethostbyname("api.ipify.org"))' 2>/dev/null || true)
    if [ -n "$CHECK_IP" ]; then
      ip route add "$CHECK_IP/32" dev "$GWT_IF" >/dev/null 2>&1 || true
      EXIT=$(curl -4fsS --resolve "api.ipify.org:443:$CHECK_IP" --max-time 8 https://api.ipify.org 2>/dev/null || true)
      ip route del "$CHECK_IP/32" >/dev/null 2>&1 || true
      if [ -n "$EXIT" ]; then
        if [ "$EXIT" = "$GWT_SERVER" ]; then
          ok "Exit IP correct: $EXIT"
        else
          warn "Exit IP: $EXIT (expected $GWT_SERVER)"
        fi
      else
        warn "Exit IP test failed (is addpeer done on the server?)"
      fi
    else
      warn "Exit IP test skipped (cannot resolve api.ipify.org)"
    fi
  else
    die "Interface $GWT_IF not found — run client first"
  fi
}

#===============================================================================
# STATUS
#===============================================================================
do_status() {
  local found=0
  if [ -f "$GWT_DIR/server.env" ]; then
    source "$GWT_DIR/server.env"
    local PEERS FRESH
    PEERS=$(wg show gwt0 peers 2>/dev/null | wc -l)
    FRESH=$(wg show gwt0 latest-handshakes 2>/dev/null | \
      awk -v now="$(date +%s)" '$2 > 0 && now - $2 < 180 {n++} END {print n+0}')
    echo "server gwt0 (port $GWT_PORT): $FRESH/$PEERS peers active"
    found=1
  fi
  for dir in "$GWT_DIR"/*/; do
    [ -f "$dir/client.env" ] || continue
    source "$dir/client.env"
    local HS AGE STATUS
    HS=$(wg show "$GWT_IF" latest-handshakes 2>/dev/null | awk '{print $2}')
    AGE=$(( $(date +%s) - ${HS:-0} ))
    if [ "$AGE" -lt 180 ]; then STATUS="UP"; else STATUS="DOWN"; fi
    echo "$GWT_SERVER ($GWT_IF): $STATUS (handshake ${AGE}s ago)"
    found=1
  done
  [ "$found" = "0" ] && echo "No tunnels configured."
  return 0
}

#===============================================================================
usage() {
  cat <<'USAGE'
GoldWaterTunnel v2 — direct WireGuard backup tunnels

Usage:
  install-v2.sh server   [--port N]                               # foreign server
  install-v2.sh client   --server IP --server-pub KEY [--port N]  # iran server
  install-v2.sh addpeer  --pub KEY --ip IP                        # foreign server
  install-v2.sh outbound FOREIGN_IP                               # xray outbound JSON
  install-v2.sh test      FOREIGN_IP                              # verify tunnel
  install-v2.sh status                                             # all tunnels
USAGE
}

main() {
  local cmd="${1:-help}"
  [ $# -gt 0 ] && shift || true
  case "$cmd" in
    server)   do_server "$@" ;;
    client)   do_client "$@" ;;
    addpeer)  do_addpeer "$@" ;;
    outbound) do_outbound "$@" ;;
    test)     do_test "$@" ;;
    status)   do_status ;;
    help|-h|--help|*) usage ;;
  esac
}
main "$@"
