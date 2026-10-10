#!/usr/bin/env bash
# =============================================================================
# list-remote-storage.sh — vexos-nix remote storage lister
# Project: vexos-nix — Personal NixOS Flake
# Purpose: Show the NFS/CIFS shares attached by attach-remote-storage.sh and
#          whether each one is mounted right now. Read-only: never mounts,
#          never writes — safe to run any time (root not required).
# Usage:   bash scripts/list-remote-storage.sh  (via `just remote-storage list`)
# =============================================================================

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'

REMOTE_NIX="/etc/nixos/storage-remote.nix"
BEGIN_MARK="# >>> vexos-remote-entries >>>"
END_MARK="# <<< vexos-remote-entries <<<"

none_attached() {
    echo ""
    echo "  No remote shares attached."
    echo -e "  Attach one with: ${BOLD}just remote-storage attach${RESET}"
    exit 0
}

[ -f "$REMOTE_NIX" ] || none_attached

mapfile -t ENTRIES < <(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    index($0, b) {f=1; next} index($0, e) {f=0} f' "$REMOTE_NIX")

# Drop blank lines.
_clean=(); for _l in "${ENTRIES[@]}"; do [ -n "${_l// /}" ] && _clean+=("$_l"); done
ENTRIES=("${_clean[@]}")
[ "${#ENTRIES[@]}" -gt 0 ] || none_attached

_field() { printf '%s\n' "$1" | grep -oP "$2"' = "\K[^"]+' | head -n1; }
_gid()   { printf '%s\n' "$1" | grep -oP '\bgid = \K[0-9]+' | head -n1; }

# status <mountpoint> — one line, without touching the mountpoint: a stat or
# readdir on an automount path would mount it (and block on an offline NAS).
status() {
    local mp=$1 unit size used avail
    if findmnt -rn -t nfs,nfs4,cifs --mountpoint "$mp" >/dev/null 2>&1; then
        read -r size used avail < <(timeout 5 df -h --output=size,used,avail "$mp" 2>/dev/null | tail -n1)
        if [ -n "${size:-}" ]; then
            echo -e "${GREEN}mounted${RESET} — $size total, $used used, $avail free"
        else
            echo -e "${GREEN}mounted${RESET}"
        fi
        return
    fi
    unit=$(systemd-escape -p --suffix=automount "$mp" 2>/dev/null)
    if [ -n "$unit" ] && systemctl is-active --quiet "$unit" 2>/dev/null; then
        echo -e "${GREEN}ready${RESET} ${DIM}— mounts on first access${RESET}"
    else
        echo -e "${YELLOW}not applied yet${RESET} ${DIM}— run: just rebuild${RESET}"
    fi
}

echo ""
echo -e "${BOLD}── Remote storage — ${#ENTRIES[@]} attached ──────────────────────────────${RESET}"
for i in "${!ENTRIES[@]}"; do
    e="${ENTRIES[$i]}"
    type=$(_field "$e" "type")
    server=$(_field "$e" "server")
    export_=$(_field "$e" "export")
    mp=$(_field "$e" "mountPoint")
    cred=$(_field "$e" "credentialsFile")
    gid=$(_gid "$e")

    echo ""
    printf "  %d) %s  %s\n" "$((i + 1))" "${type^^}" "$server:$export_"
    printf "     %-9s %s\n" "mount" "$mp"
    printf "     %-9s %b\n" "status" "$(status "$mp")"
    if [ -n "$gid" ]; then
        printf "     %-9s %s\n" "writers" "media services via the 'media' group (group number $gid)"
    else
        printf "     %-9s %s\n" "writers" "no media group set up"
    fi
    [ -n "$cred" ] && printf "     %-9s %s\n" "login" "$cred"
done

echo ""
echo "  Add another: just remote-storage attach   ·   Remove one: just remote-storage detach"
