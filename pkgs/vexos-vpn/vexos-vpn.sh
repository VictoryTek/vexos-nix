# vexos-vpn — see pkgs/vexos-vpn/default.nix and modules/vpn.nix.
# PIA_CA is prepended by default.nix.
#
# Secrets hygiene: the PIA password and the API token are never placed on a
# command line (visible in /proc/*/cmdline) or written to the journal. curl
# reads them from a config on stdin; OpenVPN reads the token from a 0600 file
# in /run. `status` output contains no secrets.

STATE_DIR=/var/lib/vexos-vpn
RUN_DIR=/run/vexos-vpn
CONFIG_FILE=/etc/vexos-vpn/config

FWMARK=0x5650          # marks the tunnel's own encrypted packets (kill switch + routing)
TABLE=22096            # routing table id (= 0x5650)
WG_IF=pia0
OVPN_IF=pia0-ovpn
PIA_DNS=10.0.0.242     # PIA in-tunnel resolver (both protocols)
KS_TABLE=vexos_killswitch
DNS_TABLE=vexos_vpn_dns
SERVERLIST_URL_HOST=serverlist.piaservers.net
SERVERLIST_PATH=/vpninfo/servers/v6
LATENCY_TIMEOUT=1

# Defaults; /etc/vexos-vpn/config (written by modules/vpn.nix) overrides.
DEFAULT_REGION=auto
DEFAULT_PROTOCOL=wireguard
CREDENTIALS_FILE=$STATE_DIR/credentials
KILLSWITCH_MODE=manual
# shellcheck source=/dev/null
[ -r "$CONFIG_FILE" ] && . "$CONFIG_FILE"

DAEMON=""
log()  { echo "vexos-vpn: $*" >&2; }
die()  {
  log "error: $*"
  [ -n "$DAEMON" ] && status_write state=error last_error="$*"
  exit 1
}
need_root() { [ "$(id -u)" -eq 0 ] || die "must be run as root (try: sudo vexos-vpn $*)"; }

# ── Persistent state (region/protocol chosen at runtime) ─────────────────────
state_get() {  # $1 = key, $2 = default
  local v=""
  [ -r "$STATE_DIR/state.json" ] && v=$(jq -r --arg k "$1" '.[$k] // empty' "$STATE_DIR/state.json" 2>/dev/null || true)
  echo "${v:-$2}"
}
state_set() {  # $1 = key, $2 = value
  local cur='{}'
  [ -r "$STATE_DIR/state.json" ] && cur=$(cat "$STATE_DIR/state.json")
  mkdir -p "$STATE_DIR"
  jq --arg k "$1" --arg v "$2" '.[$k] = $v' <<<"$cur" > "$STATE_DIR/state.json.tmp"
  mv "$STATE_DIR/state.json.tmp" "$STATE_DIR/state.json"
}

# ── Status file (world-readable, no secrets) ─────────────────────────────────
STATUS_JSON='{}'
status_write() {  # key=value pairs (string values)
  local args=() kv
  for kv in "$@"; do args+=(--arg "${kv%%=*}" "${kv#*=}"); done
  STATUS_JSON=$(jq -c "${args[@]}" '. + $ARGS.named' <<<"$STATUS_JSON")
  mkdir -p "$RUN_DIR"
  printf '%s\n' "$STATUS_JSON" > "$RUN_DIR/status.json.tmp"
  chmod 0644 "$RUN_DIR/status.json.tmp"
  mv "$RUN_DIR/status.json.tmp" "$RUN_DIR/status.json"
}

# ── Kill switch helpers ──────────────────────────────────────────────────────
ks_active() { nft list table inet "$KS_TABLE" >/dev/null 2>&1; }

# Load every PIA server IP from the cached server list into @pia_servers.
# Atomic (single nft transaction). No-op when the kill switch is not loaded.
ks_sync() {
  ks_active || return 0
  [ -s "$STATE_DIR/serverlist.json" ] || { log "kill switch: no cached server list yet"; return 0; }
  local ips
  ips=$(jq -r '[.regions[].servers | (.meta, .wg, .ovpnudp, .ovpntcp) // [] | .[].ip] | unique | join(", ")' \
        "$STATE_DIR/serverlist.json")
  [ -n "$ips" ] || return 0
  nft -f - <<EOF
flush set inet $KS_TABLE pia_servers
add element inet $KS_TABLE pia_servers { $ips }
EOF
}

# Temporarily allow root-only DNS/HTTPS to the given IPs. Elements carry a
# timeout, so the hole closes by itself even if this process dies.
ks_bootstrap_allow() {
  ks_active || return 0
  local ip
  for ip in "$@"; do
    nft add element inet "$KS_TABLE" bootstrap "{ $ip timeout 60s }"
  done
}
ks_bootstrap_close() {
  ks_active || return 0
  nft flush set inet "$KS_TABLE" bootstrap 2>/dev/null || true
}

# ── Server list ──────────────────────────────────────────────────────────────
serverlist_fetch() {
  local tmp="$STATE_DIR/serverlist.json.tmp" url="https://$SERVERLIST_URL_HOST$SERVERLIST_PATH"
  mkdir -p "$STATE_DIR"
  if ks_active && ! tunnel_iface >/dev/null; then
    # Kill switch on, no tunnel: resolve via a fixed resolver through a
    # root-only, self-expiring hole, then fetch by IP.
    log "bootstrapping server list through the kill switch"
    ks_bootstrap_allow 1.1.1.1
    local ips
    ips=$(dig +short +time=3 +tries=2 @1.1.1.1 "$SERVERLIST_URL_HOST" A | grep -E '^[0-9.]+$' || true)
    [ -n "$ips" ] || { ks_bootstrap_close; return 1; }
    # shellcheck disable=SC2086
    ks_bootstrap_allow $ips
    local first; first=$(head -n1 <<<"$ips")
    curl -fsS --max-time 20 --resolve "$SERVERLIST_URL_HOST:443:$first" -o "$tmp.raw" "$url" || { ks_bootstrap_close; return 1; }
    ks_bootstrap_close
  else
    curl -fsS --max-time 20 -o "$tmp.raw" "$url" || return 1
  fi
  # Line 1 is the JSON; the rest is PIA's signature block.
  head -n1 "$tmp.raw" > "$tmp"; rm -f "$tmp.raw"
  jq -e '.regions | length > 0' "$tmp" >/dev/null || return 1
  mv "$tmp" "$STATE_DIR/serverlist.json"
  ks_sync
}

serverlist_ensure() {
  [ -s "$STATE_DIR/serverlist.json" ] && return 0
  serverlist_fetch || die "could not fetch the PIA server list"
}

region_json() { jq -c --arg id "$1" '.regions[] | select(.id == $id)' "$STATE_DIR/serverlist.json"; }

# Print usable region ids ordered by TCP connect time to their meta server.
# Also writes $RUN_DIR/latency.json for `regions --json`.
regions_by_latency() {
  local proto_key="$1" id ip
  mkdir -p "$RUN_DIR"
  # TCP connect time to each region's meta server (same method as PIA's
  # get_region.sh), all probes in parallel. curl fails after connecting
  # (TLS port, plain HTTP request) — only time_connect matters.
  while read -r id ip; do
    (
      t=$(curl -s -o /dev/null --connect-timeout "$LATENCY_TIMEOUT" -w '%{time_connect}' "http://$ip:443" 2>/dev/null || true)
      if [ -n "$t" ] && [ "$t" != "0.000000" ]; then echo "$t $id"; fi
    ) &
  done < <(jq -r --arg p "$proto_key" '.regions[]
        | select((.offline // false) | not)
        | select((.servers[$p] // []) | length > 0)
        | select((.servers.meta // []) | length > 0)
        | "\(.id) \(.servers.meta[0].ip)"' "$STATE_DIR/serverlist.json") > "$RUN_DIR/latency.unsorted"
  wait
  sort -n "$RUN_DIR/latency.unsorted" > "$RUN_DIR/latency.txt"
  rm -f "$RUN_DIR/latency.unsorted"
  jq -R -s -c 'split("\n") | map(select(length > 0) | split(" ") | {(.[1]): (.[0] | tonumber)}) | add // {}' \
     "$RUN_DIR/latency.txt" > "$RUN_DIR/latency.json"
  awk '{print $2}' "$RUN_DIR/latency.txt"
}

# ── PIA API ──────────────────────────────────────────────────────────────────
# Escape a value for a double-quoted curl config string.
curlq() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }

TOKEN=""
token_get() {  # $1 = meta cn, $2 = meta ip
  local tf="$STATE_DIR/token" now age user pass resp
  now=$(date +%s)
  if [ -s "$tf" ]; then
    age=$(( now - $(stat -c %Y "$tf") ))
    if [ "$age" -lt 72000 ]; then TOKEN=$(cat "$tf"); return 0; fi   # < 20 h (valid 24 h)
  fi
  [ -r "$CREDENTIALS_FILE" ] || die "no PIA credentials — run: sudo vexos-vpn login"
  { IFS= read -r user; IFS= read -r pass; } < "$CREDENTIALS_FILE" || true
  [ -n "${user:-}" ] && [ -n "${pass:-}" ] || die "credentials file is malformed — run: sudo vexos-vpn login"
  resp=$(printf 'user = %s\n' "$(curlq "$user:$pass")" \
    | curl -sS --max-time 15 --config - \
        --connect-to "$1::$2:" --cacert "$PIA_CA" \
        "https://$1/authv3/generateToken") || return 1
  TOKEN=$(jq -r '.token // empty' <<<"$resp" 2>/dev/null || true)
  if [ -z "$TOKEN" ]; then
    log "token request refused: $(jq -r '.message // "unknown error"' <<<"$resp" 2>/dev/null || echo unparseable)"
    return 1
  fi
  ( umask 077; printf '%s' "$TOKEN" > "$tf" )
}

# ── Routing / DNS (identical for both protocols) ─────────────────────────────
routing_up() {  # $1 = interface
  ip -4 route replace default dev "$1" table "$TABLE"
  ip -4 rule del pref 5280 2>/dev/null || true
  ip -4 rule del pref 5290 2>/dev/null || true
  # LAN / directly-connected routes in main win (NAS, router, DHCP).
  ip -4 rule add pref 5280 table main suppress_prefixlength 0
  # Everything else that is not the tunnel's own encrypted traffic → tunnel.
  # Prefs sit after Tailscale's 5210–5270 so tailnet routes (table 52) still win.
  ip -4 rule add pref 5290 not fwmark "$FWMARK" table "$TABLE"
  resolvectl dns "$1" "$PIA_DNS"
  resolvectl domain "$1" '~.'
  resolvectl default-route "$1" yes
  # While the tunnel is up, no DNS may leave by any other interface — even
  # with the kill switch off (otherwise resolved would also query the
  # router's resolver in parallel).
  nft -f - <<EOF
table inet $DNS_TABLE
delete table inet $DNS_TABLE
table inet $DNS_TABLE {
  chain output {
    type filter hook output priority filter; policy accept;
    oifname { "$1", "tailscale0" } accept
    oif lo accept
    udp dport { 53, 853 } drop
    tcp dport { 53, 853 } drop
  }
}
EOF
}

routing_down() {
  ip -4 rule del pref 5290 2>/dev/null || true
  ip -4 rule del pref 5280 2>/dev/null || true
  ip -4 route flush table "$TABLE" 2>/dev/null || true
  nft delete table inet "$DNS_TABLE" 2>/dev/null || true
}

tunnel_iface() {
  local i
  for i in "$WG_IF" "$OVPN_IF"; do
    if ip link show "$i" >/dev/null 2>&1; then echo "$i"; return 0; fi
  done
  return 1
}

# ── WireGuard ────────────────────────────────────────────────────────────────
wg_connect() {  # $1 = region json
  local cn ip mcn mip priv pub resp peer_ip server_key server_port
  cn=$(jq -r '.servers.wg[0].cn' <<<"$1");   ip=$(jq -r '.servers.wg[0].ip' <<<"$1")
  mcn=$(jq -r '.servers.meta[0].cn' <<<"$1"); mip=$(jq -r '.servers.meta[0].ip' <<<"$1")
  token_get "$mcn" "$mip" || return 1
  priv=$(wg genkey); pub=$(wg pubkey <<<"$priv")
  resp=$(printf 'data-urlencode = %s\ndata-urlencode = %s\n' "$(curlq "pt=$TOKEN")" "$(curlq "pubkey=$pub")" \
    | curl -sS -G --max-time 15 --config - \
        --connect-to "$cn::$ip:" --cacert "$PIA_CA" \
        "https://$cn:1337/addKey") || return 1
  if [ "$(jq -r '.status // empty' <<<"$resp")" != "OK" ]; then
    log "addKey refused by $cn: $(jq -r '.message // "unknown"' <<<"$resp" 2>/dev/null || echo unparseable)"
    # A refused token is most likely expired/revoked — drop it so the next try re-authenticates.
    rm -f "$STATE_DIR/token"
    return 1
  fi
  peer_ip=$(jq -r '.peer_ip' <<<"$resp"); peer_ip=${peer_ip%%/*}
  server_key=$(jq -r '.server_key' <<<"$resp"); server_port=$(jq -r '.server_port' <<<"$resp")

  ip link del "$WG_IF" 2>/dev/null || true
  ip link add "$WG_IF" type wireguard
  wg set "$WG_IF" private-key <(printf '%s' "$priv") fwmark "$FWMARK" \
     peer "$server_key" endpoint "$ip:$server_port" allowed-ips 0.0.0.0/0 persistent-keepalive 25
  ip -4 address add "$peer_ip/32" dev "$WG_IF"
  ip link set mtu 1420 up dev "$WG_IF"
  routing_up "$WG_IF"
  # Send one packet into the tunnel so WireGuard initiates the handshake now.
  dig +time=2 +tries=1 @"$PIA_DNS" privateinternetaccess.com >/dev/null 2>&1 || true

  # Wait for the first handshake.
  local i hs
  for i in $(seq 1 15); do
    hs=$(wg show "$WG_IF" latest-handshakes | awk '{print $2}')
    [ "${hs:-0}" -gt 0 ] && break
    sleep 1
  done
  [ "${hs:-0}" -gt 0 ] || { log "no handshake from $cn"; return 1; }
  status_write server_cn="$cn" endpoint_ip="$ip" interface="$WG_IF"
}

wg_healthy() {
  local hs now
  hs=$(wg show "$WG_IF" latest-handshakes 2>/dev/null | awk '{print $2}') || return 1
  now=$(date +%s)
  [ "${hs:-0}" -gt 0 ] && [ $(( now - hs )) -lt 180 ]
}

# ── OpenVPN (backup) ─────────────────────────────────────────────────────────
OVPN_PID=""
ovpn_connect() {  # $1 = region json
  local cn ip mcn mip
  cn=$(jq -r '.servers.ovpnudp[0].cn' <<<"$1");  ip=$(jq -r '.servers.ovpnudp[0].ip' <<<"$1")
  mcn=$(jq -r '.servers.meta[0].cn' <<<"$1");    mip=$(jq -r '.servers.meta[0].ip' <<<"$1")
  token_get "$mcn" "$mip" || return 1
  mkdir -p "$RUN_DIR"
  # PIA authenticates OpenVPN with the token split across the two lines.
  ( umask 077; printf '%s\n%s\n' "${TOKEN:0:62}" "${TOKEN:62}" > "$RUN_DIR/ovpn-auth" )
  # Deliberately NOT included (see stateless_vpn_redesign_spec.md §2):
  #   compress    — removed by PIA server-side (manual-connections PR #225)
  #   crl-verify  — PIA's CRL is malformed and rejected by OpenSSL >= 3.3
  # route-noexec + pull-filter: routing is ours (routing_up), same as WireGuard.
  cat > "$RUN_DIR/pia.ovpn" <<EOF
client
dev $OVPN_IF
dev-type tun
proto udp
remote $ip 8080
nobind
persist-key
persist-tun
cipher AES-256-CBC
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
auth sha256
tls-client
remote-cert-tls server
ca $PIA_CA
auth-user-pass $RUN_DIR/ovpn-auth
mark $(( FWMARK ))
route-noexec
pull-filter ignore "redirect-gateway"
pull-filter ignore "dhcp-option"
ping 10
ping-restart 60
reneg-sec 0
disable-occ
verb 3
EOF
  openvpn --config "$RUN_DIR/pia.ovpn" &
  OVPN_PID=$!
  local i
  for i in $(seq 1 30); do
    if ip -4 address show dev "$OVPN_IF" 2>/dev/null | grep -q 'inet '; then break; fi
    kill -0 "$OVPN_PID" 2>/dev/null || { log "openvpn exited during connect to $cn"; OVPN_PID=""; return 1; }
    sleep 1
  done
  ip -4 address show dev "$OVPN_IF" 2>/dev/null | grep -q 'inet ' || { log "openvpn: no tunnel address from $cn"; return 1; }
  # OpenVPN keeps the token in memory for ping-restart reconnects, so the file
  # is no longer needed. (OpenVPN deliberately stays root — no `user nobody` —
  # because a reconnect re-creates its socket and must set SO_MARK again, which
  # needs CAP_NET_ADMIN; unmarked packets would be dropped by the kill switch.)
  rm -f "$RUN_DIR/ovpn-auth"
  routing_up "$OVPN_IF"
  status_write server_cn="$cn" endpoint_ip="$ip" interface="$OVPN_IF"
}

ovpn_healthy() { [ -n "$OVPN_PID" ] && kill -0 "$OVPN_PID" 2>/dev/null; }

# ── Teardown ─────────────────────────────────────────────────────────────────
teardown() {
  routing_down
  local i
  for i in "$WG_IF" "$OVPN_IF"; do
    resolvectl revert "$i" 2>/dev/null || true
  done
  if [ -n "$OVPN_PID" ]; then kill "$OVPN_PID" 2>/dev/null || true; wait "$OVPN_PID" 2>/dev/null || true; OVPN_PID=""; fi
  ip link del "$WG_IF" 2>/dev/null || true
  ip link del "$OVPN_IF" 2>/dev/null || true
  rm -f "$RUN_DIR/ovpn-auth"
}

# ── Daemon (vexos-vpn.service) ───────────────────────────────────────────────
cmd_daemon() {
  need_root daemon
  local region protocol proto_key candidates id rj connected=""
  region=$(state_get region "$DEFAULT_REGION")
  protocol=$(state_get protocol "$DEFAULT_PROTOCOL")
  case "$protocol" in
    wireguard) proto_key=wg ;;
    openvpn)   proto_key=ovpnudp ;;
    *) die "unknown protocol '$protocol'" ;;
  esac
  DAEMON=1
  trap 'exit 0' TERM INT
  trap 'teardown; [ "$(jq -r ".state" <<<"$STATUS_JSON")" = error ] || status_write state=disconnected' EXIT
  STATUS_JSON='{}'
  status_write state=connecting protocol="$protocol" region_setting="$region" last_error=""
  teardown

  serverlist_ensure
  if [ "$region" = auto ]; then
    candidates=$(regions_by_latency "$proto_key" | head -n 5)
    [ -n "$candidates" ] || die "no PIA region reachable"
  else
    [ -n "$(region_json "$region")" ] || die "unknown region '$region' (see: vexos-vpn regions)"
    candidates=$region   # an explicit choice is never silently swapped for another region
  fi

  for id in $candidates; do
    rj=$(region_json "$id")
    status_write region="$id" region_name="$(jq -r '.name' <<<"$rj")"
    log "connecting: $protocol → $id"
    if [ "$protocol" = wireguard ]; then wg_connect "$rj" && connected=1; else ovpn_connect "$rj" && connected=1; fi
    [ -n "$connected" ] && break
    teardown
  done
  [ -n "$connected" ] || die "could not connect to any candidate region (see: journalctl -u vexos-vpn)"
  status_write state=connected since="$(date -Iseconds)" last_error=""
  log "connected"

  # Refresh the server list (now through the tunnel) and the kill-switch set.
  serverlist_fetch || log "server list refresh failed (keeping cached copy)"

  local ticks=0
  while sleep 30; do
    if [ "$protocol" = wireguard ]; then wg_healthy || die "tunnel lost (no handshake for 180 s)"
    else ovpn_healthy || die "openvpn exited"; fi
    ticks=$(( ticks + 1 ))
    # Daily: refresh the server list through the tunnel.
    if [ $(( ticks % 2880 )) -eq 0 ]; then serverlist_fetch || true; fi
  done
}

# ── User-facing commands ─────────────────────────────────────────────────────
cmd_status() {
  local json ks_state vpn_state iface rx=0 tx=0
  json=$(cat "$RUN_DIR/status.json" 2>/dev/null || echo '{}')
  vpn_state=$(systemctl is-active vexos-vpn.service 2>/dev/null || true)
  ks_state=$(systemctl is-active vexos-killswitch.service 2>/dev/null || true)
  # Service not running: whatever the file says is stale — unless it is an
  # error, which stays visible while systemd waits to retry.
  [ "$vpn_state" = active ] || json=$(jq -c 'if .state == "error" then . else .state = "disconnected" end' <<<"$json")
  iface=$(jq -r '.interface // empty' <<<"$json")
  if [ -n "$iface" ] && [ -r "/sys/class/net/$iface/statistics/rx_bytes" ]; then
    rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes"); tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes")
  fi
  json=$(jq -c --arg ks "$ks_state" --arg mode "$KILLSWITCH_MODE" --argjson rx "$rx" --argjson tx "$tx" \
           --arg pr "$(state_get protocol "$DEFAULT_PROTOCOL")" --arg rs "$(state_get region "$DEFAULT_REGION")" \
           '. + {killswitch: ($ks == "active"), killswitch_mode: $mode, rx_bytes: $rx, tx_bytes: $tx,
                 protocol_setting: $pr, region_setting: $rs}' <<<"$json")
  if [ "${1:-}" = --json ]; then printf '%s\n' "$json"; return; fi
  jq -r '"VPN:          \(.state // "disconnected")\(if .state == "connected" then " — \(.region_name) (\(.server_cn)) via \(.protocol)" else "" end)",
         "Region:       \(.region_setting)",
         "Protocol:     \(.protocol_setting)",
         "Kill switch:  \(if .killswitch then "ON" else "off" end) (mode: \(.killswitch_mode))",
         (if .state == "connected" then "Traffic:      rx \(.rx_bytes) B / tx \(.tx_bytes) B" else empty end),
         (if (.last_error // "") != "" then "Last error:   \(.last_error)" else empty end)' <<<"$json"
}

cmd_regions() {
  [ -s "$STATE_DIR/serverlist.json" ] || die "no cached server list yet (connect once, or: sudo vexos-vpn refresh)"
  local lat='{}'
  [ -s "$RUN_DIR/latency.json" ] && lat=$(cat "$RUN_DIR/latency.json")
  local out
  out=$(jq -c --argjson lat "$lat" '[.regions[] | select((.offline // false) | not)
          | {id, name, country, port_forward, latency_s: ($lat[.id] // null)}] | sort_by(.name)' \
          "$STATE_DIR/serverlist.json")
  if [ "${1:-}" = --json ]; then printf '%s\n' "$out"; return; fi
  jq -r '.[] | "\(.id)\t\(.name)\(if .latency_s then "\t\(.latency_s * 1000 | floor) ms" else "" end)"' <<<"$out" | column -t -s $'\t'
}

cmd_region() {
  local id=${1:-}
  [ -n "$id" ] || die "usage: vexos-vpn region <id|auto>"
  [[ "$id" =~ ^[a-z0-9_-]+$ ]] || die "invalid region id '$id'"
  # Unprivileged callers (users group) go through the polkit-allowed template
  # unit, which re-runs this command as root.
  if [ "$(id -u)" -ne 0 ]; then exec systemctl start "vexos-vpn-region@$id.service"; fi
  if [ "$id" != auto ]; then
    serverlist_ensure
    [ -n "$(region_json "$id")" ] || die "unknown region '$id' (see: vexos-vpn regions)"
  fi
  state_set region "$id"
  systemctl try-restart vexos-vpn.service
  log "region set to $id"
}

cmd_protocol() {
  case "${1:-}" in wireguard|openvpn) ;; *) die "usage: vexos-vpn protocol <wireguard|openvpn>" ;; esac
  if [ "$(id -u)" -ne 0 ]; then exec systemctl start "vexos-vpn-protocol@$1.service"; fi
  state_set protocol "$1"
  systemctl try-restart vexos-vpn.service
  log "protocol set to $1"
}

cmd_login() {
  need_root login
  local user pass
  read -r -p "PIA username: " user
  read -r -s -p "PIA password: " pass; echo
  [ -n "$user" ] && [ -n "$pass" ] || die "username and password are required"
  mkdir -p "$(dirname "$CREDENTIALS_FILE")"
  ( umask 077; printf '%s\n%s\n' "$user" "$pass" > "$CREDENTIALS_FILE.tmp" )
  mv "$CREDENTIALS_FILE.tmp" "$CREDENTIALS_FILE"
  chmod 0400 "$CREDENTIALS_FILE"
  rm -f "$STATE_DIR/token"
  log "credentials saved to $CREDENTIALS_FILE (root-only)"
  systemctl try-restart vexos-vpn.service
}

# Verifies credentials against PIA without printing them or the token.
cmd_selftest() {
  need_root selftest
  serverlist_ensure
  local rj mcn mip
  rj=$(jq -c '[.regions[] | select((.offline // false) | not) | select((.servers.meta // []) | length > 0)][0]' "$STATE_DIR/serverlist.json")
  mcn=$(jq -r '.servers.meta[0].cn' <<<"$rj"); mip=$(jq -r '.servers.meta[0].ip' <<<"$rj")
  echo "server list:     OK ($(jq '.regions | length' "$STATE_DIR/serverlist.json") regions)"
  rm -f "$STATE_DIR/token"
  if token_get "$mcn" "$mip"; then echo "PIA login:       OK (token obtained from $mcn; token not shown)"
  else echo "PIA login:       FAILED (see message above)"; return 1; fi
}

cmd_killswitch() {
  case "${1:-status}" in
    on)     systemctl start vexos-killswitch.service ;;
    off)    systemctl stop  vexos-killswitch.service ;;
    status) systemctl is-active vexos-killswitch.service || true ;;
    sync)   need_root killswitch sync; ks_sync ;;
    *) die "usage: vexos-vpn killswitch <on|off|status>" ;;
  esac
}

usage() {
  cat <<EOF
vexos-vpn — PIA VPN (WireGuard / OpenVPN) with kill switch

  vexos-vpn status [--json]          connection + kill switch state
  vexos-vpn up | down                connect / disconnect
  vexos-vpn regions [--json]         list PIA regions (latency after an auto connect)
  vexos-vpn region <id|auto>         choose a region (auto = fastest)
  vexos-vpn protocol <wireguard|openvpn>
  (status/up/down/region/protocol/killswitch work without sudo for the
   users group; turning the kill switch off asks for a password when it is
   in "always" mode)
  vexos-vpn login                    store PIA credentials (root-only file) [root]
  vexos-vpn selftest                 verify login without showing secrets   [root]
  vexos-vpn refresh                  re-download the PIA server list        [root]
  vexos-vpn killswitch <on|off|status>
EOF
}

case "${1:-}" in
  daemon)   cmd_daemon ;;
  teardown) need_root teardown; teardown ;;   # ExecStopPost safety net
  status)   shift; cmd_status "$@" ;;
  up)       systemctl start vexos-vpn.service ;;
  down)     systemctl stop vexos-vpn.service ;;
  regions)  shift; cmd_regions "$@" ;;
  region)   shift; cmd_region "$@" ;;
  protocol) shift; cmd_protocol "$@" ;;
  login)    cmd_login ;;
  selftest) cmd_selftest ;;
  refresh)  need_root refresh; serverlist_fetch && log "server list refreshed" ;;
  killswitch) shift; cmd_killswitch "$@" ;;
  ""|-h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
