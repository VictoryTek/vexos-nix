#!/usr/bin/env bash
# =============================================================================
# create-mergerfs-pool.sh — vexos-nix interactive mergerfs+SnapRAID pool creator
# Project: vexos-nix — Personal NixOS Flake
# Purpose: Build the "bulk NAS" storage tier — a mergerfs union pool from
#          mixed-capacity drives, with optional SnapRAID parity. Emits a
#          declarative /etc/nixos/storage-pool.nix consumed by the flake.
# Usage:   sudo bash scripts/create-mergerfs-pool.sh   (via `just create-mergerfs-pool`)
#
# Steps:
#   [1/9] Preconditions (root, mergerfs, mkfs, blkid)
#   [2/9] Filesystem choice (ext4 / xfs)
#   [3/9] Disk enumeration (by-id; OS + ZFS-member disks excluded)
#   [4/9] Content-disk selection (the mergerfs branches)
#   [5/9] Parity-disk selection (optional SnapRAID; >= largest content disk)
#   [6/9] Destructive-action confirmation (typed keyword)
#   [7/9] wipefs + format + mount each disk
#   [8/9] Generate /etc/nixos/storage-pool.nix (by-uuid, idempotent overwrite)
#   [9/9] Next steps (just rebuild → snapraid sync)
#
# Contrast with create-zfs-pool.sh: ZFS self-persists via zpool.cache, so it
# needs no NixOS changes. mergerfs/ext4 mounts are NOT self-persisting — NixOS
# generates /etc/fstab — so this script writes a NixOS module instead.
#
# Idempotent only up to step 6 (before any destructive action).
# =============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'
die()  { echo -e "${RED}error:${RESET} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}warning:${RESET} $*" >&2; }
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
hdr()  { echo ""; echo -e "${BOLD}── $* ──────────────────────────────────────────${RESET}"; }

STORAGE_POOL_NIX="/etc/nixos/storage-pool.nix"

# ---------- [1/9] Preconditions ---------------------------------------------
hdr "[1/9] Preconditions"
[ "$(id -u)" -eq 0 ] || die "must be run as root (use 'just create-mergerfs-pool', which calls sudo)"
command -v mergerfs   >/dev/null 2>&1 || die "mergerfs not found — set vexos.server.nas.backend = \"mergerfs\" (or vexos.server.storage.mergerfs.enable) and rebuild first"
command -v mkfs.ext4  >/dev/null 2>&1 || die "mkfs.ext4 not found — e2fsprogs missing"
command -v wipefs     >/dev/null 2>&1 || die "wipefs not found — util-linux missing"
command -v blkid      >/dev/null 2>&1 || die "blkid not found — util-linux missing"
command -v lsblk      >/dev/null 2>&1 || die "lsblk not found"
ok "running as root with mergerfs userland present"

# ---------- [2/9] Filesystem choice -----------------------------------------
hdr "[2/9] Branch filesystem"
echo "  1) ext4   (default, universally supported)"
echo "  2) xfs    (better for very large files; needs xfsprogs)"
FSTYPE=""
while [ -z "$FSTYPE" ]; do
    printf "Choice [1-2, default 1]: "
    read -r INPUT
    INPUT="${INPUT:-1}"
    case "$INPUT" in
        1) FSTYPE="ext4" ;;
        2) FSTYPE="xfs"; command -v mkfs.xfs >/dev/null 2>&1 || die "mkfs.xfs not found — add xfsprogs" ;;
        *) echo "  invalid" ;;
    esac
done
ok "filesystem: $FSTYPE"

# ---------- [3/9] Disk enumeration -------------------------------------------
hdr "[3/9] Disk enumeration"

# OS-protected device names (root, /boot, /nix, swap).
PROTECTED=$(lsblk -no PKNAME,MOUNTPOINT,FSTYPE 2>/dev/null \
            | awk '$2=="/" || $2=="/boot" || $2=="/nix" || $3=="swap" {print $1}' \
            | sort -u)

declare -a CANDIDATES=() CAND_DEV=() CAND_INFO=()

while IFS= read -r byid; do
    [ -L "/dev/disk/by-id/$byid" ] || continue
    case "$byid" in
        *-part[0-9]*) continue ;;                 # skip partition links
        ata-*|nvme-*|scsi-*|wwn-*) ;;
        *) continue ;;
    esac
    dev=$(readlink -f "/dev/disk/by-id/$byid")
    base=$(basename "$dev")

    # exclude OS disks (disk itself or any of its partitions is protected)
    echo "$PROTECTED" | grep -qx "$base" && continue
    skip=0
    for part in $(lsblk -no NAME "$dev" 2>/dev/null | tail -n +2); do
        echo "$PROTECTED" | grep -qx "$part" && { skip=1; break; }
    done
    [ "$skip" -eq 0 ] || continue

    # exclude disks that are part of an existing ZFS pool (VM/live tier) so the
    # bulk tier can never cannibalise ZFS disks.
    if lsblk -no FSTYPE "$dev" 2>/dev/null | grep -qx "zfs_member"; then
        continue
    fi

    info=$(lsblk -dno SIZE,MODEL,TRAN "$dev" 2>/dev/null | head -1)
    CANDIDATES+=("$byid"); CAND_DEV+=("$base"); CAND_INFO+=("$info")
done < <(ls /dev/disk/by-id/ 2>/dev/null)

[ "${#CANDIDATES[@]}" -gt 0 ] || die "no eligible disks found (all detected disks are OS disks or ZFS members)"

echo ""
printf "  %-3s  %-50s  %-10s  %s\n" "#" "by-id" "device" "size / model / tran"
printf "  %-3s  %-50s  %-10s  %s\n" "-" "-----" "------" "-------------------"
for i in "${!CANDIDATES[@]}"; do
    printf "  %-3s  %-50s  %-10s  %s\n" "$((i+1))" "${CANDIDATES[$i]}" "${CAND_DEV[$i]}" "${CAND_INFO[$i]}"
done
echo ""

# Helper: prompt for a set of indices, returns selected by-id paths in REPLY_BYID.
declare -a REPLY_BYID=()
select_disks() {
    local prompt="$1" min="$2" allow_empty="$3" exclude_csv="${4:-}"
    local input idx
    while true; do
        REPLY_BYID=()
        printf "%s" "$prompt"
        read -r input
        input="${input//,/ }"
        if [ -z "$input" ] && [ "$allow_empty" = "yes" ]; then
            return 0
        fi
        local valid=1
        for idx in $input; do
            if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#CANDIDATES[@]}" ]; then
                echo "  invalid index: $idx"; valid=0; break
            fi
            if [ -n "$exclude_csv" ] && echo ",$exclude_csv," | grep -q ",$idx,"; then
                echo "  index $idx already used as a content disk"; valid=0; break
            fi
            REPLY_BYID+=("$idx")
        done
        [ "$valid" -eq 1 ] || continue
        if [ "${#REPLY_BYID[@]}" -lt "$min" ]; then
            echo "  need at least $min disk(s)"; continue
        fi
        return 0
    done
}

# ---------- [4/9] Content-disk selection -------------------------------------
hdr "[4/9] Content disks (mergerfs branches)"
select_disks "Select CONTENT disk indices (space/comma separated, e.g. '1 2 3'): " 1 no ""
declare -a CONTENT_IDX=("${REPLY_BYID[@]}")
CONTENT_CSV=$(IFS=,; echo "${CONTENT_IDX[*]}")
ok "content disks: ${CONTENT_IDX[*]}"

# ---------- [5/9] Parity-disk selection --------------------------------------
hdr "[5/9] Parity disks (SnapRAID — optional but recommended)"
echo "  SnapRAID adds scheduled parity protection. Each parity disk must be"
echo "  >= your largest content disk. Leave blank to skip (no redundancy)."
select_disks "Select PARITY disk indices, or blank to skip: " 1 yes "$CONTENT_CSV"
declare -a PARITY_IDX=("${REPLY_BYID[@]}")
USE_SNAPRAID="no"
[ "${#PARITY_IDX[@]}" -gt 0 ] && USE_SNAPRAID="yes"
if [ "$USE_SNAPRAID" = "yes" ]; then
    ok "parity disks: ${PARITY_IDX[*]} (SnapRAID enabled)"
else
    warn "no parity disks selected — the pool will have NO redundancy"
fi

# ---------- [6/9] Confirmation -----------------------------------------------
hdr "[6/9] Confirmation — IRREVERSIBLE"
echo ""
echo "  Filesystem : $FSTYPE"
echo "  Mountpoint : /storage (mergerfs union)"
echo "  Content disks → mergerfs branches:"
for n in "${CONTENT_IDX[@]}"; do echo "      /dev/disk/by-id/${CANDIDATES[$((n-1))]}"; done
if [ "$USE_SNAPRAID" = "yes" ]; then
    echo "  Parity disks (SnapRAID):"
    for n in "${PARITY_IDX[@]}"; do echo "      /dev/disk/by-id/${CANDIDATES[$((n-1))]}"; done
fi
echo ""
echo -e "${RED}ALL EXISTING DATA on the listed disks will be destroyed.${RESET}"
echo "To proceed, type 'storage' exactly:"
printf "> "
read -r CONFIRM
[ "$CONFIRM" = "storage" ] || die "confirmation mismatch — aborting (no changes made)"

# ---------- [7/9] Format and mount -------------------------------------------
hdr "[7/9] Wiping, formatting, mounting"

# format_disk <by-id> <mountpoint-label>  → echoes the resulting UUID
format_and_mount() {
    local byid="$1" mnt="$2" dev
    dev=$(readlink -f "/dev/disk/by-id/$byid")
    echo "  wipefs -a $dev"                     >&2
    wipefs -a "$dev" >/dev/null 2>&1 || warn "wipefs reported an issue on $dev"
    if [ "$FSTYPE" = "ext4" ]; then
        mkfs.ext4 -F "$dev" >/dev/null 2>&1 || die "mkfs.ext4 failed on $dev"
    else
        mkfs.xfs -f "$dev" >/dev/null 2>&1 || die "mkfs.xfs failed on $dev"
    fi
    mkdir -p "$mnt"
    mount "$dev" "$mnt" || die "mount $dev → $mnt failed"
    blkid -s UUID -o value "$dev"
}

declare -a CONTENT_UUID=() CONTENT_MNT=()
i=0
for n in "${CONTENT_IDX[@]}"; do
    i=$((i+1))
    mnt="/mnt/disk$i"
    uuid=$(format_and_mount "${CANDIDATES[$((n-1))]}" "$mnt")
    CONTENT_UUID+=("$uuid"); CONTENT_MNT+=("$mnt")
    ok "content disk $i → $mnt (UUID=$uuid)"
done

declare -a PARITY_UUID=() PARITY_MNT=()
if [ "$USE_SNAPRAID" = "yes" ]; then
    i=0
    for n in "${PARITY_IDX[@]}"; do
        i=$((i+1))
        mnt="/mnt/parity$i"
        uuid=$(format_and_mount "${CANDIDATES[$((n-1))]}" "$mnt")
        PARITY_UUID+=("$uuid"); PARITY_MNT+=("$mnt")
        ok "parity disk $i → $mnt (UUID=$uuid)"
    done
fi

# ---------- [8/9] Generate storage-pool.nix ----------------------------------
hdr "[8/9] Writing $STORAGE_POOL_NIX"

[ -f "$STORAGE_POOL_NIX" ] && cp -a "$STORAGE_POOL_NIX" "${STORAGE_POOL_NIX}.bak" && \
    warn "existing $STORAGE_POOL_NIX backed up to ${STORAGE_POOL_NIX}.bak"

{
    echo "# /etc/nixos/storage-pool.nix"
    echo "# GENERATED by scripts/create-mergerfs-pool.sh on $(date '+%Y-%m-%d %H:%M:%S')."
    echo "# Re-running the script overwrites this file (prior version saved as .bak)."
    echo "# Host-generated (per-machine disk UUIDs) — do NOT commit to the vexos-nix repo."
    echo "{ ... }:"
    echo "{"
    echo "  vexos.server.nas.backend = \"mergerfs\";"
    echo ""
    echo "  vexos.server.storage.mergerfs = {"
    echo "    enable = true;"
    echo "    branches = ["
    for j in "${!CONTENT_MNT[@]}"; do
        echo "      { mountPoint = \"${CONTENT_MNT[$j]}\"; device = \"/dev/disk/by-uuid/${CONTENT_UUID[$j]}\"; fsType = \"$FSTYPE\"; }"
    done
    echo "    ];"
    echo "  };"
    if [ "$USE_SNAPRAID" = "yes" ]; then
        echo ""
        echo "  vexos.server.storage.snapraid = {"
        echo "    enable = true;"
        echo "    parityDisks = ["
        for j in "${!PARITY_MNT[@]}"; do
            echo "      { mountPoint = \"${PARITY_MNT[$j]}\"; device = \"/dev/disk/by-uuid/${PARITY_UUID[$j]}\"; fsType = \"$FSTYPE\"; }"
        done
        echo "    ];"
        echo "  };"
    fi
    echo "}"
} > "$STORAGE_POOL_NIX"

ok "wrote $STORAGE_POOL_NIX"

# ---------- [9/9] Next steps -------------------------------------------------
hdr "[9/9] Next steps"
echo ""
echo "  1. Apply the configuration:"
echo -e "       ${BOLD}just rebuild${RESET}"
echo "     This declares the branch mounts and the /storage union pool."
echo ""
if [ "$USE_SNAPRAID" = "yes" ]; then
    echo "  2. After the rebuild, run the initial SnapRAID sync (builds parity):"
    echo -e "       ${BOLD}sudo snapraid sync${RESET}"
    echo "     Parity then refreshes automatically on the configured schedule."
    echo ""
    echo "  3. Point your Samba/NFS shares (Cockpit → File Sharing) at /storage."
else
    echo "  2. Point your Samba/NFS shares (Cockpit → File Sharing) at /storage."
fi
echo ""
echo "  Add more disks later by re-running this script (it regenerates the file)."
echo ""
ok "done"
