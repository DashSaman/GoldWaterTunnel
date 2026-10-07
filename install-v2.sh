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

GWT_VERSION="2.2.2"
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
PostUp = sysctl -qw net.ipv4.ip_forward=1; iptables -I FORWARD 1 -i %i -j ACCEPT; iptables -I FORWARD 1 -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -I POSTROUTING 1 -s ${NET}.0/24 -j MASQUERADE; iptables -t mangle -I FORWARD -i %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; iptables -t mangle -I FORWARD -o %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -s ${NET}.0/24 -j MASQUERADE; iptables -t mangle -D FORWARD -i %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; iptables -t mangle -D FORWARD -o %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
EOF
  chmod 600 "$WG_DIR/$IFNAME.conf"

  # kernel/network tuning for high-throughput, many-flow tunnels
  cat > /etc/sysctl.d/99-goldwater-v2.conf <<EOF
# GoldWaterTunnel v2 tuning
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
net.ipv4.udp_mem = 65536 131072 262144
net.netfilter.nf_conntrack_max = 262144
EOF
  sysctl --system >/dev/null 2>&1 || true

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
    --server)      [ $# -ge 2 ] || die "--server requires a value"; SERVER="$2"; shift 2 ;;
    --port)        [ $# -ge 2 ] || die "--port requires a value"; PORT="$2"; shift 2 ;;
    --server-pub)  [ $# -ge 2 ] || die "--server-pub requires a value"; SERVER_PUB="$2"; shift 2 ;;
    --nat)         NAT_MODE="1"; shift ;;
    *) shift ;;
  esac done

  [ -n "$SERVER" ] || die "--server <foreign-ip> required"
  [ -n "$SERVER_PUB" ] || die "--server-pub <key> required (from server output)"
  [[ "$SERVER" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "--server must be an IPv4 address"
  local OCTET
  local -a OCTETS
  IFS=. read -r -a OCTETS <<< "$SERVER"
  for OCTET in "${OCTETS[@]}"; do
    [ "$((10#$OCTET))" -le 255 ] || die "--server must be an IPv4 address"
  done
  [[ "$PORT" =~ ^[0-9]{1,5}$ ]] || die "--port must be between 1 and 65535"
  PORT=$((10#$PORT))
  [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "--port must be between 1 and 65535"
  [[ "$SERVER_PUB" =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "--server-pub must be a WireGuard public key"

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
  LAST=$((10#$LAST))
  # One flat tunnel subnet 10.70.0.0/24 (server holds 10.70.0.1).
  # Each foreign server gets a unique host address derived from its last octet.
  local NET="10.70.0"
  local ADDR="${NET}.$(( (LAST % 249) + 2 ))"

  local CONF="$WG_DIR/$IFNAME.conf"
  local ENV="$GWT_DIR/$SERVER/client.env"
  local WORK HAD_CONF=0 HAD_ENV=0 WAS_UP=0
  mkdir -p "$WG_DIR" "$GWT_DIR/$SERVER" || die "could not create client directories"
  WORK=$(mktemp -d "$WG_DIR/.gwt-client.XXXXXX") || die "could not create client staging directory"

  # Snapshot both files before changing either or stopping the existing tunnel.
  if [ -e "$CONF" ] || [ -L "$CONF" ]; then
    [ -f "$CONF" ] && cp -p -- "$CONF" "$WORK/previous.conf" \
      || die "could not snapshot $CONF; tunnel untouched (staging: $WORK)"
    HAD_CONF=1
  fi
  if [ -e "$ENV" ] || [ -L "$ENV" ]; then
    [ -f "$ENV" ] && cp -p -- "$ENV" "$WORK/previous.env" \
      || die "could not snapshot $ENV; tunnel untouched (staging: $WORK)"
    HAD_ENV=1
  fi
  if ip link show "$IFNAME" >/dev/null 2>&1; then
    WAS_UP=1
    [ "$HAD_CONF" = "1" ] \
      || die "$IFNAME exists without a saved configuration; refusing teardown (staging: $WORK)"
  fi

  # reuse existing keys on re-install so reruns never orphan the server-side peer
  local PRIV PUB
  if [ "$HAD_CONF" = "1" ] && grep -q '^PrivateKey' "$WORK/previous.conf"; then
    PRIV=$(awk '/^PrivateKey/{print $3; exit}' "$WORK/previous.conf") \
      || die "could not read existing key; tunnel untouched (staging: $WORK)"
    PUB=$(printf '%s\n' "$PRIV" | wg pubkey) \
      || die "existing private key is invalid; tunnel untouched (staging: $WORK)"
    say "reusing existing keys for $IFNAME (idempotent re-install)"
  else
    PRIV=$(wg genkey) || die "could not generate client key (staging: $WORK)"
    PUB=$(printf '%s\n' "$PRIV" | wg pubkey) \
      || die "could not derive client public key (staging: $WORK)"
  fi

  if ! cat > "$WORK/$IFNAME.conf" <<EOF
[Interface]
PrivateKey = $PRIV
Address = ${ADDR}/32
Table = off
MTU = 1380

[Peer]
PublicKey = $SERVER_PUB
Endpoint = ${SERVER}:${PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 10
EOF
  then
    die "could not stage client configuration; tunnel untouched (staging: $WORK)"
  fi

  # Save for outbound generation
  # preserve the dedicated Xray peer identity (see do_outbound) across re-installs
  local XPEER=""
  if [ "$HAD_ENV" = "1" ]; then
    XPEER=$(awk '/^GWT_X(PRIV|PUB|ADDR)=/' "$WORK/previous.env") \
      || die "could not read Xray peer identity; tunnel untouched (staging: $WORK)"
  fi

  if ! cat > "$WORK/client.env" <<EOF
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
  then
    die "could not stage client environment; tunnel untouched (staging: $WORK)"
  fi
  if [ -n "$XPEER" ]; then
    printf '%s\n' "$XPEER" >> "$WORK/client.env" \
      || die "could not preserve Xray peer identity; tunnel untouched (staging: $WORK)"
  fi
  chmod 600 "$WORK/$IFNAME.conf" "$WORK/client.env" \
    || die "could not secure staged files; tunnel untouched (staging: $WORK)"

  # Validate WireGuard settings on a temporary, down interface before teardown.
  local CHECK_IF="gwtv${BASHPID}" VALID=1
  if ! wg-quick strip "$WORK/$IFNAME.conf" > "$WORK/check.conf"; then
    rm -rf -- "$WORK" || warn "could not remove staging directory $WORK"
    die "new configuration rejected; existing files and tunnel untouched"
  fi
  if ! ip link add dev "$CHECK_IF" type wireguard; then
    rm -rf -- "$WORK" || warn "could not remove staging directory $WORK"
    die "could not create validation interface; existing files and tunnel untouched"
  fi
  if ! wg setconf "$CHECK_IF" "$WORK/check.conf"; then
    VALID=0
  fi
  ip link delete dev "$CHECK_IF" \
    || die "could not remove validation interface $CHECK_IF; existing tunnel untouched (staging: $WORK)"
  if [ "$VALID" != "1" ]; then
    rm -rf -- "$WORK" || warn "could not remove staging directory $WORK"
    die "new configuration rejected; existing files and tunnel untouched"
  fi

  # Apply the staged files only after the old tunnel has stopped successfully.
  local FAILED="" CLEANED=1 RESTORED=1
  if [ "$WAS_UP" = "1" ]; then
    if ! wg-quick down "$IFNAME"; then
      FAILED="could not stop $IFNAME"
    fi
  fi
  if [ -z "$FAILED" ]; then
    if ! mv -f -- "$WORK/$IFNAME.conf" "$CONF"; then
      FAILED="could not install client configuration"
    elif ! mv -f -- "$WORK/client.env" "$ENV"; then
      FAILED="could not install client environment"
    elif ! wg-quick up "$IFNAME"; then
      FAILED="wg-quick up failed for $IFNAME"
    elif ! wg show "$IFNAME" >/dev/null 2>&1; then
      FAILED="WireGuard interface $IFNAME is missing after startup"
    fi
  fi

  if [ -n "$FAILED" ]; then
    warn "$FAILED — restoring previous client state"
    if ip link show "$IFNAME" >/dev/null 2>&1; then
      if ! wg-quick down "$IFNAME"; then
        CLEANED=0
      fi
      if ip link show "$IFNAME" >/dev/null 2>&1; then
        CLEANED=0
      fi
    fi
    if [ "$HAD_CONF" = "1" ]; then
      if ! cp -p -- "$WORK/previous.conf" "$CONF"; then
        RESTORED=0
      fi
    elif ! rm -f -- "$CONF"; then
      RESTORED=0
    fi
    if [ "$HAD_ENV" = "1" ]; then
      if ! cp -p -- "$WORK/previous.env" "$ENV"; then
        RESTORED=0
      fi
    elif ! rm -f -- "$ENV"; then
      RESTORED=0
    fi
    [ "$RESTORED" = "1" ] \
      || die "$FAILED; file restoration failed — backups retained at $WORK; manual recovery required"
    [ "$CLEANED" = "1" ] \
      || die "$FAILED; previous files restored but interface cleanup failed — backups retained at $WORK; manual recovery required"
    if [ "$HAD_CONF" != "1" ]; then
      rm -rf -- "$WORK" || warn "could not remove staging directory $WORK"
      die "fresh client installation failed: $FAILED"
    fi
    if wg-quick up "$IFNAME" && wg show "$IFNAME" >/dev/null 2>&1; then
      rm -rf -- "$WORK" || warn "could not remove staging directory $WORK"
      die "rerun failed: $FAILED; previous configuration and client.env restored, tunnel is UP and serving"
    fi
    die "$FAILED; previous configuration and client.env restored but tunnel restart failed — backups retained at $WORK; manual recovery required"
  fi
  rm -rf -- "$WORK" || warn "could not remove staging directory $WORK"

  # UDP socket buffers help both the kernel interface and userspace (Xray) WG
  cat > /etc/sysctl.d/99-goldwater-v2.conf <<EOF
# GoldWaterTunnel v2 tuning
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF
  sysctl --system >/dev/null 2>&1 || true

  # survive reboots: the tunnel must come back on its own (report honestly)
  if systemctl enable "wg-quick@$IFNAME" >/dev/null 2>&1 \
     && systemctl is-enabled "wg-quick@$IFNAME" >/dev/null 2>&1; then
    ok "tunnel enabled at boot (wg-quick@$IFNAME)"
  else
    warn "FAILED to enable wg-quick@$IFNAME at boot — tunnel will NOT survive reboot"
  fi

  # low-RAM servers without swap can hard-freeze under heavy load; add a safety net
  # only when disk space allows a real reserve besides the swap itself
  local RAM_MB SWAP_MB AVAIL_MB SWAP_MB_TO_MAKE
  RAM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
  SWAP_MB=$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo)
  AVAIL_MB=$(df -PBM / | awk 'NR==2{gsub("M","",$4); print int($4)}')
  if [ "$RAM_MB" -le 4096 ] && [ "$SWAP_MB" -lt 512 ] && [ ! -e /swapfile.gwt ] && [ ! -L /swapfile.gwt ]; then
    SWAP_MB_TO_MAKE=0
    if [ "$AVAIL_MB" -ge 4096 ]; then
      SWAP_MB_TO_MAKE=2048
    elif [ "$AVAIL_MB" -ge 3072 ]; then
      SWAP_MB_TO_MAKE=1024
    else
      warn "low RAM (${RAM_MB}MB) and no swap, but only ${AVAIL_MB}MB free — skipping swapfile"
    fi
    if [ "${GWT_NO_SWAP:-0}" != "1" ] && [ "$SWAP_MB_TO_MAKE" -gt 0 ]; then
      local SWAP_WORK OLD_SWAPPINESS SWAP_RESTORED=1
      SWAP_WORK=$(mktemp -d /etc/.gwt-swap.XXXXXX) \
        || die "could not create swap recovery directory; client tunnel is UP"
      if cp -p -- /etc/fstab "$SWAP_WORK/fstab" \
         && cp -p -- /etc/sysctl.d/99-goldwater-v2.conf "$SWAP_WORK/sysctl.conf" \
         && OLD_SWAPPINESS=$(sysctl -n vm.swappiness); then
        say "low RAM (${RAM_MB}MB) with no swap — creating ${SWAP_MB_TO_MAKE}MB safety swapfile (GWT_NO_SWAP=1 to skip)"
        if dd if=/dev/zero of=/swapfile.gwt bs=1M count="$SWAP_MB_TO_MAKE" status=none 2>/dev/null \
           && chmod 600 /swapfile.gwt \
           && mkswap /swapfile.gwt >/dev/null 2>&1 \
           && swapon /swapfile.gwt \
           && { grep -q '/swapfile.gwt' /etc/fstab || echo '/swapfile.gwt none swap sw 0 0' >> /etc/fstab; } \
           && sysctl -qw vm.swappiness=10 \
           && { grep -q 'vm.swappiness' /etc/sysctl.d/99-goldwater-v2.conf || echo 'vm.swappiness = 10' >> /etc/sysctl.d/99-goldwater-v2.conf; }; then
          ok "safety swap active (${SWAP_MB_TO_MAKE}MB, swappiness=10)"
        else
          warn "swap creation failed — cleaning up and continuing without it"
          if awk '$1 == "/swapfile.gwt" {found=1} END {exit !found}' /proc/swaps; then
            swapoff /swapfile.gwt \
              || die "could not deactivate failed swap setup; active file retained, backups at $SWAP_WORK"
          fi
          if ! rm -f -- /swapfile.gwt; then
            SWAP_RESTORED=0
          fi
          if ! cp -p -- "$SWAP_WORK/fstab" /etc/fstab; then
            SWAP_RESTORED=0
          fi
          if ! cp -p -- "$SWAP_WORK/sysctl.conf" /etc/sysctl.d/99-goldwater-v2.conf; then
            SWAP_RESTORED=0
          fi
          if ! sysctl -qw "vm.swappiness=$OLD_SWAPPINESS"; then
            SWAP_RESTORED=0
          fi
          [ "$SWAP_RESTORED" = "1" ] \
            || die "swap cleanup failed; backups retained at $SWAP_WORK; client tunnel is UP"
        fi
      else
        warn "could not snapshot swap settings — skipping swapfile"
      fi
      rm -rf -- "$SWAP_WORK" || warn "could not remove swap recovery directory $SWAP_WORK"
    fi
  fi

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
#  OUTBOUND (print Xray JSON — with a DEDICATED Xray peer)
#
#  The kernel interface (used by `test`) and the panel's userspace Xray outbound
#  must NEVER share one key: the server would bounce the endpoint between the two
#  sessions (roaming ping-pong) and drop packets intermittently. We therefore
#  generate a second peer identity just for Xray.
#===============================================================================
do_outbound() {
  local SERVER="${1:?Usage: outbound FOREIGN_IP}"
  local env_file="$GWT_DIR/$SERVER/client.env"
  [ -f "$env_file" ] || die "No client config for $SERVER (run client first)"
  # shellcheck disable=SC1090
  source "$env_file"

  # dedicated Xray peer (own key + own tunnel IP, never equal to the kernel one)
  if [ -z "${GWT_XPRIV:-}" ]; then
    local LAST XPRIV XPUB
    LAST=$(echo "$SERVER" | awk -F. '{print $4}')
    [[ "$LAST" =~ ^[0-9]+$ ]] || LAST=0
    XPRIV=$(wg genkey)
    XPUB=$(echo "$XPRIV" | wg pubkey)
    local XADDR="${GWT_NET}.$(( ((LAST + 100) % 249) + 2 ))"
    [ "$XADDR" = "$GWT_ADDR" ] && XADDR="${GWT_NET}.$(( ((LAST + 101) % 249) + 2 ))"
    cat >> "$env_file" <<EOF
GWT_XPRIV=$XPRIV
GWT_XPUB=$XPUB
GWT_XADDR=$XADDR
EOF
    chmod 600 "$env_file"
    # re-source to pick up the new values
    source "$env_file"
    warn "New Xray peer generated ($GWT_XADDR). Run on the SERVER first:"
    echo ""
    echo "  install-v2.sh addpeer --pub $GWT_XPUB --ip $GWT_XADDR"
    echo ""
  fi

  cat <<EOF
{
  "tag": "WaterWall-${GWT_SERVER}",
  "protocol": "wireguard",
  "settings": {
    "secretKey": "${GWT_XPRIV}",
    "address": ["${GWT_XADDR}/32"],
    "peers": [{
      "publicKey": "${GWT_SERVER_PUB}",
      "endpoint": "${GWT_SERVER}:${GWT_PORT}",
      "keepAlive": 10
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
