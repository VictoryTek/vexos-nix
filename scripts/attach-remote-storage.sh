#!/usr/bin/env bash
# =============================================================================
# attach-remote-storage.sh — vexos-nix remote storage pool attacher
# Project: vexos-nix — Personal NixOS Flake
# Purpose: Attach a storage pool exported by ANOTHER host (NFS or CIFS/SMB) so
#          local services can consume it. Non-destructive — client mount only.
#          Emits/updates a declarative /etc/nixos/storage-remote.nix.
# Usage:   sudo bash scripts/attach-remote-storage.sh  (via `just remote-storage attach`)
#
# Steps:
#   [1/6] Preconditions (root)
#   [2/6] Protocol (nfs / cifs)
#   [3/6] Server — discovered over mDNS (avahi) and offered as a menu, typed
#         address as fallback (+ CIFS username/password, needed to list shares)
#   [4/6] Share / mountpoint — shares are probed from the server and offered as a
#         menu (showmount / smbclient); typed entry is the fallback. The local
#         mountpoint is derived as /mnt/<server-name>/<share-name>. CIFS
#         credentials are written to /etc/nixos/secrets, never inlined.
#   [5/6] Optional test-mount
#   [6/6] Merge the entry into /etc/nixos/storage-remote.nix
#
# Multiple remotes are supported: existing entries are preserved on re-run.
# =============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'
die()  { echo -e "${RED}error:${RESET} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}warning:${RESET} $*" >&2; }
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
hdr()  { echo ""; echo -e "${BOLD}── $* ──────────────────────────────────────────${RESET}"; }

REMOTE_NIX="/etc/nixos/storage-remote.nix"
SECRET_DIR="/etc/nixos/secrets"
BEGIN_MARK="# >>> vexos-remote-entries >>>"
END_MARK="# <<< vexos-remote-entries <<<"

# ---------- [1/6] Preconditions ---------------------------------------------
hdr "[1/6] Preconditions"
[ "$(id -u)" -eq 0 ] || die "must be run as root (use 'just remote-storage attach', which calls sudo)"
ok "running as root"

# ---------- [2/6] Protocol ---------------------------------------------------
hdr "[2/6] Protocol"
echo "  1) nfs    — Linux/Unix NAS export (e.g. another vexos ZFS/mergerfs host)"
echo "  2) cifs   — SMB share (Windows, Samba, most consumer NAS units)"
PROTO=""
while [ -z "$PROTO" ]; do
    printf "Choice [1-2]: "
    read -r INPUT
    case "$INPUT" in
        1) PROTO="nfs" ;;
        2) PROTO="cifs" ;;
        *) echo "  invalid" ;;
    esac
done
ok "protocol: $PROTO"

# pick_from <label>... — numbered menu with a "type it manually" entry.
# Sets PICKED to the chosen 0-based index, or "" when manual entry was chosen.
pick_from() {
    local n=$# i c
    PICKED=""
    for ((i = 1; i <= n; i++)); do printf "    %d) %s\n" "$i" "${!i}"; done
    echo "    m) type it manually"
    while :; do
        printf "Choice [1-%d/m]: " "$n"
        read -r c || die "no input"
        case "$c" in
            m|M) return 0 ;;
            ''|*[!0-9]*) ;;
            *) if [ "$c" -ge 1 ] && [ "$c" -le "$n" ]; then PICKED=$((c - 1)); return 0; fi ;;
        esac
        echo "  invalid"
    done
}

# Print "<ipv4>\t<label>\t<hostname>" for each host on the LAN advertising the chosen
# protocol over mDNS (avahi is enabled on every role). This host's own
# addresses are skipped. Avahi escapes bytes in service names as \DDD (decimal).
discover_hosts() {
    command -v avahi-browse >/dev/null 2>&1 || return 0
    local svc="_smb._tcp" self
    [ "$PROTO" = "nfs" ] && svc="_nfs._tcp"
    self=$(ip -4 -o addr show 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4 }')
    timeout 10 avahi-browse -t -r -p "$svc" 2>/dev/null </dev/null | awk -F';' -v self="$self" '
        BEGIN { n = split(self, s, "\n"); for (i = 1; i <= n; i++) mine[s[i]] = 1 }
        $1 == "=" && $3 == "IPv4" && !($8 in mine) && !($8 in seen) {
            seen[$8] = 1
            name = $4
            while (match(name, /\\[0-9][0-9][0-9]/))
                name = substr(name, 1, RSTART - 1) sprintf("%c", substr(name, RSTART + 1, 3) + 0) substr(name, RSTART + RLENGTH)
            host = $7; sub(/\..*/, "", host)
            printf "%s\t%s (%s)\t%s\n", $8, name, $8, host
        }'
}

# slug <text> — reduce to [A-Za-z0-9._-] for use in a path / file name.
slug() {
    local s
    s=$(printf '%s' "$1" | tr -cs 'A-Za-z0-9._' '-')
    s="${s#-}"; s="${s%-}"
    printf '%s' "${s:-share}"
}

# ---------- [3/6] Server (+ CIFS credentials) --------------------------------
hdr "[3/6] Storage server"
echo "  Looking for servers on the network..."
HOST_ADDR=(); HOST_LABEL=(); HOST_NAME=()
while IFS=$'\t' read -r _addr _label _name; do
    [ -n "$_addr" ] && { HOST_ADDR+=("$_addr"); HOST_LABEL+=("$_label"); HOST_NAME+=("$_name"); }
done < <(discover_hosts)

SERVER=""
if [ "${#HOST_ADDR[@]}" -gt 0 ]; then
    echo "  Found:"
    pick_from "${HOST_LABEL[@]}"
    [ -n "$PICKED" ] && SERVER="${HOST_ADDR[$PICKED]}"
else
    warn "no servers advertised over mDNS — enter the address manually"
fi
if [ -z "$SERVER" ]; then
    printf "Storage server host or IP: "
    read -r SERVER
fi
[ -n "$SERVER" ] || die "server cannot be empty"
ok "server: $SERVER"

# Short name for the mountpoint: the discovered mDNS hostname when the address
# is a known host, else the typed hostname (domain dropped), else nas-<ip>.
SERVER_NAME=""
for i in "${!HOST_ADDR[@]}"; do
    [ "${HOST_ADDR[$i]}" = "$SERVER" ] && SERVER_NAME="${HOST_NAME[$i]}"
done
if [ -z "$SERVER_NAME" ]; then
    case "$SERVER" in
        *[!0-9.]*) SERVER_NAME="${SERVER%%.*}" ;;
        *)         SERVER_NAME="nas-${SERVER//./-}" ;;
    esac
fi

# Throw-away 0700 dir for the probe's credentials file and stderr capture.
PROBE_DIR=$(mktemp -d)
trap 'rm -rf "$PROBE_DIR"' EXIT

# CIFS credentials are collected before the share is chosen: most NAS units
# refuse to list shares to guests, and the mount needs them regardless. The
# real credentials file is named after the mountpoint, so it is written in [4/6].
SMB_USER=""; SMB_PASS=""
if [ "$PROTO" = "cifs" ]; then
    printf "SMB username: "
    read -r SMB_USER
    [ -n "$SMB_USER" ] || die "username cannot be empty"
    printf "SMB password: "
    IFS= read -rs SMB_PASS; echo ""
fi

# ---------- [4/6] Share / mountpoint -----------------------------------------
hdr "[4/6] Share and mountpoint"

if [ "$PROTO" = "nfs" ]; then
    PROBE_BIN="showmount"; PROBE_PKG="nfs-utils"; KIND="exports"
else
    PROBE_BIN="smbclient"; PROBE_PKG="samba";     KIND="shares"
fi

# Run the probe tool; nfs-utils/samba only land on rebuild, so fall back to a
# one-off `nix shell` when it is not installed yet.
probe() {
    if command -v "$PROBE_BIN" >/dev/null 2>&1; then
        timeout 30 "$PROBE_BIN" "$@" </dev/null
    else
        timeout 180 nix shell "nixpkgs#${PROBE_PKG}" -c "$PROBE_BIN" "$@" </dev/null
    fi
}

# Print one share/export name per line. Exit status of the tool is ignored:
# smbclient exits non-zero after listing when its SMB1 workgroup-listing
# reconnect fails. stderr goes to $PROBE_DIR/err for the caller to report.
list_shares() {
    local out
    if [ "$PROTO" = "nfs" ]; then
        out=$(probe -e --no-headers "$SERVER" 2>"$PROBE_DIR/err")
        # "<export>   <clients>" — keep the path; skip anything else.
        printf '%s\n' "$out" | awk '$1 ~ /^\// { print $1 }'
    else
        ( umask 077; printf 'username = %s\npassword = %s\n' "$SMB_USER" "$SMB_PASS" > "$PROBE_DIR/auth" )
        out=$(probe -L "//${SERVER}" -g -A "$PROBE_DIR/auth" 2>"$PROBE_DIR/err")
        # Grepable form is "Disk|<name>|<comment>"; hide admin shares (IPC$, ADMIN$, ...).
        printf '%s\n' "$out" | awk -F'|' '$1 == "Disk" && $2 !~ /\$$/ { print $2 }'
    fi
}

echo "  Querying $SERVER for available $KIND..."
command -v "$PROBE_BIN" >/dev/null 2>&1 \
    || echo "  ($PROBE_BIN not installed yet — fetching $PROBE_PKG via nix shell; needs network)"
FOUND=()
mapfile -t FOUND < <(list_shares)

EXPORT=""
if [ "${#FOUND[@]}" -gt 0 ]; then
    echo "  Found on $SERVER:"
    pick_from "${FOUND[@]}"
    [ -n "$PICKED" ] && EXPORT="${FOUND[$PICKED]}"
else
    PROBE_ERR=$(grep -v '^[[:space:]]*$' "$PROBE_DIR/err" 2>/dev/null | tail -n1)
    warn "could not list $KIND on $SERVER${PROBE_ERR:+ ($PROBE_ERR)} — enter it manually"
fi

if [ -z "$EXPORT" ]; then
    if [ "$PROTO" = "nfs" ]; then
        printf "NFS export path (e.g. /tank/media): "
    else
        printf "CIFS share name (e.g. media): "
    fi
    read -r EXPORT
    [ -n "$EXPORT" ] || die "export/share cannot be empty"
fi
EXPORT="${EXPORT#/}"; [ "$PROTO" = "nfs" ] && EXPORT="/$EXPORT"   # NFS needs leading /

# Mountpoint is derived, not asked: /mnt/<server-name>/<share-name>, so several
# shares from several servers never collide and group by server.
MNT="/mnt/$(slug "$SERVER_NAME")/$(slug "$(basename "$EXPORT")")"

# Each mountpoint keys a fileSystems.<mountPoint> attribute in
# modules/storage-remote.nix; a duplicate key is silently collapsed by
# builtins.listToAttrs (first entry wins), so a second share on the same
# mountpoint would never mount. Only when the derived path is already taken
# (e.g. the same share attached twice) do we ask for a different one.
claimed() { [ -f "$REMOTE_NIX" ] && grep -qF "mountPoint = \"$1\";" "$REMOTE_NIX"; }
while claimed "$MNT"; do
    warn "mountpoint $MNT is already claimed by an entry in $REMOTE_NIX"
    echo "  (drop the existing entry first with 'just remote-storage detach', or pick another path)"
    while :; do
        printf "Local mountpoint (absolute path): "
        read -r MNT || die "no input"
        case "$MNT" in /*) break ;; esac
        echo "  must be an absolute path"
    done
done
ok "will mount ${SERVER}:${EXPORT} → $MNT"

CRED_FILE=""
if [ "$PROTO" = "cifs" ]; then
    # Named after the full mountpoint (not its basename) so same-named shares
    # on different servers do not share a credentials file.
    CRED_FILE="$SECRET_DIR/remote-$(slug "$MNT")-credentials"
    mkdir -p "$SECRET_DIR"; chmod 700 "$SECRET_DIR"
    printf 'username=%s\npassword=%s\n' "$SMB_USER" "$SMB_PASS" > "$CRED_FILE"
    chmod 600 "$CRED_FILE"; chown root:root "$CRED_FILE"
    ok "credentials written to $CRED_FILE (0600 root:root — not in the Nix store)"
fi

# ---------- [5/6] Optional test-mount ----------------------------------------
hdr "[5/6] Test mount (optional)"
TESTDIR="/tmp/vexos-remote-test.$$"
run_test=1
if [ "$PROTO" = "nfs" ] && ! command -v mount.nfs >/dev/null 2>&1; then
    warn "mount.nfs not present yet (nfs-utils installs on rebuild) — skipping test"
    run_test=0
elif [ "$PROTO" = "cifs" ] && ! command -v mount.cifs >/dev/null 2>&1; then
    warn "mount.cifs not present yet (cifs-utils installs on rebuild) — skipping test"
    run_test=0
fi
if [ "$run_test" -eq 1 ]; then
    printf "Attempt a test mount now? [Y/n]: "
    read -r ANSWER
    case "${ANSWER,,}" in
        n|no) echo "  skipped" ;;
        *)
            mkdir -p "$TESTDIR"
            if [ "$PROTO" = "nfs" ]; then
                mount -t nfs -o nfsvers=4.2,soft,timeo=50 "${SERVER}:${EXPORT}" "$TESTDIR" 2>/tmp/vexos-mnt-err
            else
                mount -t cifs -o "credentials=${CRED_FILE}" "//${SERVER}/${EXPORT}" "$TESTDIR" 2>/tmp/vexos-mnt-err
            fi
            if mountpoint -q "$TESTDIR"; then
                ok "test mount succeeded"
                umount "$TESTDIR" 2>/dev/null || true
            else
                warn "test mount failed: $(cat /tmp/vexos-mnt-err 2>/dev/null)"
                printf "  Write the config anyway? [y/N]: "
                read -r GOON
                case "${GOON,,}" in y|yes) ;; *) rmdir "$TESTDIR" 2>/dev/null; die "aborted (no config written)" ;; esac
            fi
            rmdir "$TESTDIR" 2>/dev/null || true
            rm -f /tmp/vexos-mnt-err
            ;;
    esac
fi

# ---------- [6/6] Merge into storage-remote.nix ------------------------------
hdr "[6/6] Writing $REMOTE_NIX"

if [ "$PROTO" = "nfs" ]; then
    ENTRY="      { type = \"nfs\"; server = \"${SERVER}\"; export = \"${EXPORT}\"; mountPoint = \"${MNT}\"; }"
else
    ENTRY="      { type = \"cifs\"; server = \"${SERVER}\"; export = \"${EXPORT}\"; mountPoint = \"${MNT}\"; credentialsFile = \"${CRED_FILE}\"; }"
fi

# Preserve any existing entries between the markers.
EXISTING=""
if [ -f "$REMOTE_NIX" ]; then
    EXISTING=$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
        $0 ~ b {f=1; next} $0 ~ e {f=0} f' "$REMOTE_NIX")
    cp -a "$REMOTE_NIX" "${REMOTE_NIX}.bak"
    warn "existing $REMOTE_NIX backed up to ${REMOTE_NIX}.bak"
fi

{
    echo "# /etc/nixos/storage-remote.nix"
    echo "# GENERATED/updated by scripts/attach-remote-storage.sh on $(date '+%Y-%m-%d %H:%M:%S')."
    echo "# Entries between the markers are managed by the script; re-runs append here."
    echo "# Host-generated — do NOT commit to the vexos-nix repo (CIFS creds live in"
    echo "# /etc/nixos/secrets, referenced by path only)."
    echo "{ ... }:"
    echo "{"
    echo "  vexos.storage.remote = ["
    echo "    $BEGIN_MARK"
    [ -n "$EXISTING" ] && printf '%s\n' "$EXISTING"
    echo "$ENTRY"
    echo "    $END_MARK"
    echo "  ];"
    echo "}"
} > "$REMOTE_NIX"

ok "wrote $REMOTE_NIX"

echo ""
echo "  Apply with:"
echo -e "     ${BOLD}just rebuild${RESET}"
echo "  The share mounts lazily on first access (x-systemd.automount), so a slow"
echo "  or offline storage server never blocks boot."
echo ""
ok "done"
