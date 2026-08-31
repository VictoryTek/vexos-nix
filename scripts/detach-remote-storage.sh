#!/usr/bin/env bash
# =============================================================================
# detach-remote-storage.sh — vexos-nix remote storage pool detacher
# Project: vexos-nix — Personal NixOS Flake
# Purpose: Remove a remote NFS/CIFS share attached earlier by
#          attach-remote-storage.sh. Interactive companion to that script.
#          Non-destructive to data — client unmount + declarative cleanup only.
# Usage:   sudo bash scripts/detach-remote-storage.sh  (via `just detach-remote-storage`)
#
# Steps:
#   [1/5] Preconditions (root, config present)
#   [2/5] Parse managed entries from /etc/nixos/storage-remote.nix
#   [3/5] Select an entry (or ALL) to detach
#   [4/5] Confirm, then unmount + rmdir mountpoint + drop orphaned CIFS creds
#   [5/5] Rewrite /etc/nixos/storage-remote.nix without the removed entries
#
# Applies nothing itself — prints a `just rebuild` reminder, like attach.
# =============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'
die()  { echo -e "${RED}error:${RESET} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}warning:${RESET} $*" >&2; }
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
hdr()  { echo ""; echo -e "${BOLD}── $* ──────────────────────────────────────────${RESET}"; }

REMOTE_NIX="/etc/nixos/storage-remote.nix"
BEGIN_MARK="# >>> vexos-remote-entries >>>"
END_MARK="# <<< vexos-remote-entries <<<"

# ---------- [1/5] Preconditions --------------------------------------------
hdr "[1/5] Preconditions"
[ "$(id -u)" -eq 0 ] || die "must be run as root (use 'just detach-remote-storage', which calls sudo)"
ok "running as root"

if [ ! -f "$REMOTE_NIX" ]; then
    ok "no remote shares configured ($REMOTE_NIX absent) — nothing to detach"
    exit 0
fi
ok "found $REMOTE_NIX"

# ---------- [2/5] Parse managed entries -----------------------------------
hdr "[2/5] Parsing entries"

mapfile -t ENTRIES < <(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    index($0, b) {f=1; next} index($0, e) {f=0} f' "$REMOTE_NIX")

# Drop blank lines.
_clean=(); for _l in "${ENTRIES[@]}"; do [ -n "${_l// /}" ] && _clean+=("$_l"); done
ENTRIES=("${_clean[@]}")

_field() { printf '%s\n' "$1" | grep -oP "$2"' = "\K[^"]+' | head -n1; }

if [ "${#ENTRIES[@]}" -eq 0 ]; then
    warn "$REMOTE_NIX has no managed entries."
    printf "Delete the now-empty %s? [y/N]: " "$REMOTE_NIX"
    read -r ANS
    case "${ANS,,}" in
        y|yes)
            rm -f "$REMOTE_NIX" "${REMOTE_NIX}.bak"
            ok "removed $REMOTE_NIX"
            echo ""
            echo "  Apply with:  ${BOLD}just rebuild${RESET}"
            ;;
        *) ok "left $REMOTE_NIX in place" ;;
    esac
    exit 0
fi

ok "found ${#ENTRIES[@]} entr$([ "${#ENTRIES[@]}" -eq 1 ] && echo y || echo ies)"

# ---------- [3/5] Selection ------------------------------------------------
hdr "[3/5] Select entry to detach"
for i in "${!ENTRIES[@]}"; do
    _t=$(_field "${ENTRIES[$i]}" "type")
    _s=$(_field "${ENTRIES[$i]}" "server")
    _x=$(_field "${ENTRIES[$i]}" "export")
    _m=$(_field "${ENTRIES[$i]}" "mountPoint")
    printf "  %d) %-4s  %s:%s  →  %s\n" "$((i + 1))" "$_t" "$_s" "$_x" "$_m"
done
echo "  a) detach ALL"
echo ""

SELECT=()
while [ "${#SELECT[@]}" -eq 0 ]; do
    printf "Choice [1-%d or a]: " "${#ENTRIES[@]}"
    read -r CH
    case "$CH" in
        a|A|all|ALL)
            for i in "${!ENTRIES[@]}"; do SELECT+=("$i"); done
            ;;
        ''|*[!0-9]*) echo "  invalid" ;;
        *)
            if [ "$CH" -ge 1 ] && [ "$CH" -le "${#ENTRIES[@]}" ]; then
                SELECT=("$((CH - 1))")
            else
                echo "  out of range"
            fi
            ;;
    esac
done

# ---------- [4/5] Confirm + live cleanup ---------------------------------
hdr "[4/5] Detach"

# Indices kept vs removed.
declare -A REMOVE=()
for i in "${SELECT[@]}"; do REMOVE[$i]=1; done

echo "  Will remove:"
for i in "${SELECT[@]}"; do echo "    - $(_field "${ENTRIES[$i]}" "mountPoint")  ($(_field "${ENTRIES[$i]}" "server"):$(_field "${ENTRIES[$i]}" "export"))"; done
echo ""
printf "Proceed? [y/N]: "
read -r GO
case "${GO,,}" in y|yes) ;; *) die "aborted (no changes made)" ;; esac

for i in "${SELECT[@]}"; do
    MNT=$(_field "${ENTRIES[$i]}" "mountPoint")
    CRED=$(_field "${ENTRIES[$i]}" "credentialsFile")
    [ -n "$MNT" ] || { warn "could not parse mountPoint from entry $((i + 1)); skipping its cleanup"; continue; }

    # Stop the transient automount unit, then unmount.
    _unit=$(systemd-escape -p --suffix=automount "$MNT" 2>/dev/null || true)
    [ -n "$_unit" ] && systemctl stop "$_unit" 2>/dev/null || true

    if mountpoint -q "$MNT"; then
        if umount "$MNT" 2>/dev/null; then
            ok "unmounted $MNT"
        elif umount -l "$MNT" 2>/dev/null; then
            warn "$MNT was busy — detached lazily (umount -l); it clears when the last user closes it"
        else
            warn "could not unmount $MNT — close anything using it and run 'umount $MNT' by hand (the rebuild drops the unit regardless)"
        fi
    else
        ok "$MNT not currently mounted"
    fi

    # Remove the mountpoint dir only if it is an empty directory.
    if [ -d "$MNT" ]; then
        if rmdir "$MNT" 2>/dev/null; then
            ok "removed empty mountpoint $MNT"
        else
            warn "$MNT is not empty or could not be removed — left in place"
        fi
    fi

    # Drop the CIFS credentials file only if no *remaining* entry references it.
    if [ -n "$CRED" ] && [ -f "$CRED" ]; then
        _still_used=0
        for j in "${!ENTRIES[@]}"; do
            [ -n "${REMOVE[$j]:-}" ] && continue
            [ "$(_field "${ENTRIES[$j]}" "credentialsFile")" = "$CRED" ] && _still_used=1
        done
        if [ "$_still_used" -eq 0 ]; then
            rm -f "$CRED"
            ok "removed orphaned credentials file $CRED"
        else
            ok "kept $CRED (still used by another entry)"
        fi
    fi
done

# ---------- [5/5] Rewrite storage-remote.nix ----------------------------
hdr "[5/5] Writing $REMOTE_NIX"

KEEP=()
for i in "${!ENTRIES[@]}"; do
    [ -n "${REMOVE[$i]:-}" ] && continue
    KEEP+=("${ENTRIES[$i]}")
done

cp -a "$REMOTE_NIX" "${REMOTE_NIX}.bak"
warn "previous $REMOTE_NIX backed up to ${REMOTE_NIX}.bak"

{
    echo "# /etc/nixos/storage-remote.nix"
    echo "# GENERATED/updated by scripts/detach-remote-storage.sh on $(date '+%Y-%m-%d %H:%M:%S')."
    echo "# Entries between the markers are managed by the storage scripts."
    echo "# Host-generated — do NOT commit to the vexos-nix repo (CIFS creds live in"
    echo "# /etc/nixos/secrets, referenced by path only)."
    echo "{ ... }:"
    echo "{"
    echo "  vexos.storage.remote = ["
    echo "    $BEGIN_MARK"
    for _e in "${KEEP[@]}"; do printf '%s\n' "$_e"; done
    echo "    $END_MARK"
    echo "  ];"
    echo "}"
} > "$REMOTE_NIX"

ok "wrote $REMOTE_NIX (${#KEEP[@]} entr$([ "${#KEEP[@]}" -eq 1 ] && echo y || echo ies) remaining)"

if [ "${#KEEP[@]}" -eq 0 ]; then
    echo ""
    printf "No shares remain. Remove %s entirely? [y/N]: " "$REMOTE_NIX"
    read -r ANS
    case "${ANS,,}" in
        y|yes)
            rm -f "$REMOTE_NIX"
            ok "removed $REMOTE_NIX (${REMOTE_NIX}.bak kept)"
            ;;
        *) ok "kept $REMOTE_NIX with an empty (inert) list" ;;
    esac
fi

echo ""
echo "  Apply with:"
echo -e "     ${BOLD}just rebuild${RESET}"
echo "  NixOS regenerates /etc/fstab and drops the mount unit on rebuild."
echo ""
ok "done"
