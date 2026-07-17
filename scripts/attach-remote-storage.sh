#!/usr/bin/env bash
# =============================================================================
# attach-remote-storage.sh — vexos-nix remote storage pool attacher
# Project: vexos-nix — Personal NixOS Flake
# Purpose: Attach a storage pool exported by ANOTHER host (NFS or CIFS/SMB) so
#          local services can consume it. Non-destructive — client mount only.
#          Emits/updates a declarative /etc/nixos/storage-remote.nix.
# Usage:   sudo bash scripts/attach-remote-storage.sh  (via `just attach-remote-storage`)
#
# Steps:
#   [1/6] Preconditions (root)
#   [2/6] Protocol (nfs / cifs)
#   [3/6] Server / export / mountpoint
#   [4/6] Credentials (cifs only — written to /etc/nixos/secrets, never inlined)
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
[ "$(id -u)" -eq 0 ] || die "must be run as root (use 'just attach-remote-storage', which calls sudo)"
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

# ---------- [3/6] Server / export / mountpoint -------------------------------
hdr "[3/6] Remote location"
printf "Storage server host or IP: "
read -r SERVER
[ -n "$SERVER" ] || die "server cannot be empty"

if [ "$PROTO" = "nfs" ]; then
    printf "NFS export path (e.g. /tank/media): "
else
    printf "CIFS share name (e.g. media): "
fi
read -r EXPORT
[ -n "$EXPORT" ] || die "export/share cannot be empty"
EXPORT="${EXPORT#/}"; [ "$PROTO" = "nfs" ] && EXPORT="/$EXPORT"   # NFS needs leading /

DEFAULT_MNT="/mnt/nas-$(basename "$EXPORT")"
printf "Local mountpoint [%s]: " "$DEFAULT_MNT"
read -r MNT
MNT="${MNT:-$DEFAULT_MNT}"
case "$MNT" in /*) ;; *) die "mountpoint must be an absolute path" ;; esac
ok "will mount ${SERVER}:${EXPORT} → $MNT"

# ---------- [4/6] Credentials (cifs only) ------------------------------------
CRED_FILE=""
if [ "$PROTO" = "cifs" ]; then
    hdr "[4/6] CIFS credentials"
    CRED_FILE="$SECRET_DIR/remote-$(basename "$MNT")-credentials"
    printf "SMB username: "
    read -r SMB_USER
    printf "SMB password: "
    IFS= read -rs SMB_PASS; echo ""
    [ -n "$SMB_USER" ] || die "username cannot be empty"
    mkdir -p "$SECRET_DIR"; chmod 700 "$SECRET_DIR"
    printf 'username=%s\npassword=%s\n' "$SMB_USER" "$SMB_PASS" > "$CRED_FILE"
    chmod 600 "$CRED_FILE"; chown root:root "$CRED_FILE"
    ok "credentials written to $CRED_FILE (0600 root:root — not in the Nix store)"
else
    hdr "[4/6] Credentials"
    echo "  (none — NFS uses host-based export permissions)"
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
    echo "  vexos.server.storage.remote = ["
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
