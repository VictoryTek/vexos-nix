#!/usr/bin/env bash
# =============================================================================
# create-zfs-pool.sh — vexos-nix interactive ZFS pool creator
# Project: vexos-nix — Personal NixOS Flake (NixOS 25.11)
# Purpose: Create a ZFS pool on a server-role host for Proxmox VE VM/container
#          backing storage. Invoked by `just create-zfs-pool`.
# Usage:   sudo bash scripts/create-zfs-pool.sh
#
# Steps:
#   [1/8] Preconditions (root, ZFS userland, hostId)
#   [2/8] Pool name (validated)
#   [3/8] Topology selection
#   [4/8] Disk enumeration (by /dev/disk/by-id/, OS disks excluded)
#   [5/8] Disk selection
#   [6/8] Destructive-action confirmation (typed pool name)
#   [7/8] wipefs + sgdisk --zap-all + zpool create
#   [8/8] Optional child dataset + Proxmox registration hint
#
# This script is idempotent only up to step 5 (everything before destructive
# actions). After step 6 confirmation, partial failures may leave disks
# zapped — re-run the script to retry from a clean state.
# =============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'
die()  { echo -e "${RED}error:${RESET} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}warning:${RESET} $*" >&2; }
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
hdr()  { echo ""; echo -e "${BOLD}── $* ──────────────────────────────────────────${RESET}"; }

# ---------- [1/8] Preconditions ---------------------------------------------
hdr "[1/8] Preconditions"
[ "$(id -u)" -eq 0 ] || die "must be run as root (use 'just create-zfs-pool', which calls sudo)"
command -v zpool  >/dev/null 2>&1 || die "zpool not found — modules/zfs-server.nix not active"
command -v zfs    >/dev/null 2>&1 || die "zfs not found — modules/zfs-server.nix not active"
command -v sgdisk >/dev/null 2>&1 || die "sgdisk not found — gptfdisk missing from systemPackages"
command -v wipefs >/dev/null 2>&1 || die "wipefs not found — util-linux missing from systemPackages"
command -v lsblk  >/dev/null 2>&1 || die "lsblk not found"

# hostId sanity check
if [ ! -s /etc/hostid ] && [ -z "$(awk '/^networking\.hostId/{found=1} END{print found}' /etc/nixos/configuration.nix 2>/dev/null)" ]; then
    warn "/etc/hostid is empty and no networking.hostId override detected."
    warn "Pools created now may fail to auto-import on next boot."
    warn "modules/zfs-server.nix sets networking.hostId from /etc/machine-id by default;"
    warn "verify after the next nixos-rebuild switch that 'cat /etc/hostid' returns 8 bytes."
fi

ok "running as root with zfs userland present"

# ---------- [2/8] Pool name --------------------------------------------------
hdr "[2/8] Pool name"
RESERVED='^(mirror|raidz|raidz1|raidz2|raidz3|draid|spare|log)$'
NAME_RE='^[A-Za-z][A-Za-z0-9._:-]*$'
while true; do
    printf "Pool name [tank]: "
    read -r POOL
    POOL="${POOL:-tank}"
    if [[ ! "$POOL" =~ $NAME_RE ]]; then
        echo "  invalid — must start with a letter and use [A-Za-z0-9._:-] only"
        continue
    fi
    if [[ "$POOL" =~ $RESERVED ]]; then
        echo "  invalid — '$POOL' is a reserved zpool keyword"
        continue
    fi
    if zpool list -H -o name 2>/dev/null | grep -qx "$POOL"; then
        echo "  pool '$POOL' already exists on this system — choose a different name"
        continue
    fi
    break
done
ok "pool name: $POOL"

# ---------- [3/8] Topology ---------------------------------------------------
hdr "[3/8] Topology"
echo "  1) single   — 1 disk          (no redundancy, lab/dev only)"
echo "  2) mirror   — 2+ disks        (RAID1, recommended for VM workloads)"
echo "  3) raidz1   — 3+ disks        (single parity)"
echo "  4) raidz2   — 4+ disks        (double parity)"
echo "  5) raidz3   — 5+ disks        (triple parity)"
echo "  6) raid10   — 4/6/8 disks     (stripe of mirrors, recommended for VM workloads)"
echo ""
echo "  Hint: for Proxmox VM/zvol storage, prefer mirror or raid10. RAIDZ amplifies"
echo "  small-block writes for zvols (Proxmox wiki, OpenZFS tuning docs)."
echo ""
TOPO=""; MIN_DISKS=0
while [ -z "$TOPO" ]; do
    printf "Choice [1-6]: "
    read -r INPUT
    case "$INPUT" in
        1) TOPO="single";  MIN_DISKS=1 ;;
        2) TOPO="mirror";  MIN_DISKS=2 ;;
        3) TOPO="raidz1";  MIN_DISKS=3 ;;
        4) TOPO="raidz2";  MIN_DISKS=4 ;;
        5) TOPO="raidz3";  MIN_DISKS=5 ;;
        6) TOPO="raid10";  MIN_DISKS=4 ;;
        *) echo "  invalid" ;;
    esac
done
ok "topology: $TOPO (min $MIN_DISKS disks)"

# ---------- [4/8] Disk enumeration -------------------------------------------
hdr "[4/8] Disk enumeration"

# Find OS-protected device names (root, /boot, /nix, swap)
PROTECTED=$(lsblk -no PKNAME,MOUNTPOINT,FSTYPE 2>/dev/null \
            | awk '$2=="/" || $2=="/boot" || $2=="/nix" || $3=="swap" {print $1}' \
            | sort -u)

declare -a CANDIDATES=()
declare -a CAND_DEV=()
declare -a CAND_INFO=()

while IFS= read -r byid; do
    [ -L "/dev/disk/by-id/$byid" ] || continue
    case "$byid" in
        *-part[0-9]*) continue ;;        # skip partition links
    esac
    case "$byid" in
        ata-*|nvme-*|scsi-*|wwn-*) ;;
        *) continue ;;
    esac
    dev=$(readlink -f "/dev/disk/by-id/$byid")
    base=$(basename "$dev")

    # exclude OS disks (any base name in PROTECTED)
    if echo "$PROTECTED" | grep -qx "$base"; then
        continue
    fi
    # also exclude if any partition of this disk is in PROTECTED
    skip=0
    for part in $(lsblk -no NAME "$dev" 2>/dev/null | tail -n +2); do
        if echo "$PROTECTED" | grep -qx "$part"; then skip=1; break; fi
    done
    [ "$skip" -eq 0 ] || continue

    info=$(lsblk -dno SIZE,MODEL,TRAN "$dev" 2>/dev/null | head -1)
    CANDIDATES+=("$byid")
    CAND_DEV+=("$base")
    CAND_INFO+=("$info")
done < <(ls /dev/disk/by-id/ 2>/dev/null)

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
    die "no eligible disks found (all detected disks contain /, /boot, /nix, or swap)"
fi

echo ""
printf "  %-3s  %-50s  %-10s  %s\n" "#" "by-id" "device" "size / model / tran"
printf "  %-3s  %-50s  %-10s  %s\n" "-" "-----" "------" "-------------------"
for i in "${!CANDIDATES[@]}"; do
    n=$((i+1))
    printf "  %-3s  %-50s  %-10s  %s\n" "$n" "${CANDIDATES[$i]}" "${CAND_DEV[$i]}" "${CAND_INFO[$i]}"
done
echo ""

# ---------- [5/8] Disk selection ---------------------------------------------
hdr "[5/8] Disk selection"
declare -a SELECTED_BYID=()
while true; do
    printf "Select disks (comma- or space-separated indices, e.g. '1 2'): "
    read -r INPUT
    SELECTED_BYID=()
    INPUT="${INPUT//,/ }"
    valid=1
    for idx in $INPUT; do
        if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#CANDIDATES[@]}" ]; then
            echo "  invalid index: $idx"; valid=0; break
        fi
        SELECTED_BYID+=("/dev/disk/by-id/${CANDIDATES[$((idx-1))]}")
    done
    [ "$valid" -eq 1 ] || continue
    if [ "${#SELECTED_BYID[@]}" -lt "$MIN_DISKS" ]; then
        echo "  topology '$TOPO' requires at least $MIN_DISKS disks"
        continue
    fi
    if [ "$TOPO" = "raid10" ] && [ $((${#SELECTED_BYID[@]} % 2)) -ne 0 ]; then
        echo "  raid10 requires an even number of disks (mirror pairs)"
        continue
    fi
    break
done

# Build the zpool create vdev argv based on topology
declare -a VDEV_ARGS=()
case "$TOPO" in
    single)
        VDEV_ARGS=("${SELECTED_BYID[@]}") ;;
    mirror)
        VDEV_ARGS=("mirror" "${SELECTED_BYID[@]}") ;;
    raidz1) VDEV_ARGS=("raidz1" "${SELECTED_BYID[@]}") ;;
    raidz2) VDEV_ARGS=("raidz2" "${SELECTED_BYID[@]}") ;;
    raidz3) VDEV_ARGS=("raidz3" "${SELECTED_BYID[@]}") ;;
    raid10)
        # Pair disks into successive mirror vdevs.
        for ((i=0; i<${#SELECTED_BYID[@]}; i+=2)); do
            VDEV_ARGS+=("mirror" "${SELECTED_BYID[$i]}" "${SELECTED_BYID[$((i+1))]}")
        done ;;
esac

# ---------- [6/8] Destructive-action confirmation ----------------------------
hdr "[6/8] Confirmation — IRREVERSIBLE"
echo ""
echo "  Pool name : $POOL"
echo "  Topology  : $TOPO"
echo "  Disks     :"
for d in "${SELECTED_BYID[@]}"; do echo "                $d"; done
echo "  Options   : -o ashift=12"
echo "              -O compression=lz4"
echo "              -O atime=off"
echo "              -O xattr=sa"
echo "              -O acltype=posixacl"
echo "              -O mountpoint=/$POOL"
echo "  Pre-step  : wipefs -a + sgdisk --zap-all on each disk"
echo ""
echo -e "${RED}ALL EXISTING DATA on the listed disks will be destroyed.${RESET}"
echo "To proceed, type the pool name '$POOL' exactly:"
printf "> "
read -r CONFIRM
[ "$CONFIRM" = "$POOL" ] || die "confirmation mismatch — aborting (no changes made)"

# ---------- [7/8] Wipe and create --------------------------------------------
hdr "[7/8] Wiping disks and creating pool"
for d in "${SELECTED_BYID[@]}"; do
    echo "  wipefs -a $d"
    wipefs -a "$d" >/dev/null
    echo "  sgdisk --zap-all $d"
    sgdisk --zap-all "$d" >/dev/null
done

echo ""
echo "  zpool create -f -o ashift=12 \\"
echo "    -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \\"
echo "    -O mountpoint=/$POOL \\"
echo "    $POOL ${VDEV_ARGS[*]}"
echo ""

if ! zpool create -f -o ashift=12 \
        -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
        -O mountpoint=/"$POOL" \
        "$POOL" "${VDEV_ARGS[@]}"; then
    echo ""
    echo "── recent kernel log ─────────────────────────────────────────"
    journalctl -k --since "2 minutes ago" 2>/dev/null | tail -50 || true
    die "zpool create failed (see kernel log above)"
fi
ok "pool '$POOL' created"

# ---------- [8/8] Optional dataset + Proxmox registration -------------------
hdr "[8/8] Optional Proxmox child dataset"
printf "Create a child dataset '%s/vm' for Proxmox VM disks? [Y/n]: " "$POOL"
read -r MAKE_DS
case "${MAKE_DS,,}" in
    n|no) PVE_TARGET="$POOL" ;;
    *)    zfs create "$POOL/vm"; PVE_TARGET="$POOL/vm"; ok "dataset '$POOL/vm' created" ;;
esac

echo ""
echo "── Verify ────────────────────────────────────────────────────"
zpool status "$POOL"
zfs list -r "$POOL"

echo ""
echo "── Register with Proxmox VE ──────────────────────────────────"
if command -v pvesm >/dev/null 2>&1; then
    printf "Proxmox storage ID [vm-store]: "
    read -r STOR_ID
    STOR_ID="${STOR_ID:-vm-store}"
    if pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "$STOR_ID"; then
        warn "storage ID '$STOR_ID' already exists in Proxmox — skipping registration"
        warn "To register manually: pvesm add zfspool $STOR_ID --pool $PVE_TARGET --content images,rootdir --sparse 1"
    else
        echo "  pvesm add zfspool $STOR_ID --pool $PVE_TARGET --content images,rootdir --sparse 1"
        if pvesm add zfspool "$STOR_ID" --pool "$PVE_TARGET" --content images,rootdir --sparse 1; then
            ok "storage '$STOR_ID' registered in Proxmox (pool: $PVE_TARGET)"
        else
            warn "pvesm registration failed — register manually:"
            warn "  pvesm add zfspool $STOR_ID --pool $PVE_TARGET --content images,rootdir --sparse 1"
        fi
    fi
else
    warn "pvesm not found — not running on a Proxmox VE host, or pvesm is not in PATH"
    echo "  Register manually:"
    echo "    pvesm add zfspool vm-store --pool $PVE_TARGET --content images,rootdir --sparse 1"
    echo "  …or in the web UI:"
    echo "    Datacenter → Storage → Add → ZFS"
    echo "      ID:      vm-store"
    echo "      Pool:    $PVE_TARGET"
    echo "      Content: Disk image, Container"
    echo "      Thin provision: enabled"
fi

echo ""
echo "Persistence: the pool will auto-import on next boot via /etc/zfs/zpool.cache."
echo "No flake, fstab, or NixOS module changes are needed for the pool itself."
echo ""
ok "done"
