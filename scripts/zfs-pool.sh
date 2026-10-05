#!/usr/bin/env bash
# =============================================================================
# zfs-pool.sh — vexos-nix interactive ZFS pool manager
# Project: vexos-nix — Personal NixOS Flake
# Purpose: One menu for day-to-day ZFS pool work on a server-role host: show,
#          create, destroy, import, replace/add/attach/detach disks, scrub, clear.
#          Invoked by `just zfs-pool`.
# Usage:   sudo bash scripts/zfs-pool.sh [action]   (menu when no action is given)
#
# "Create" hands off to the sibling create-zfs-pool.sh. Everything else lives here.
# Pools are registered for boot-time import in /etc/nixos/zfs-pools.nix using the
# same marker block create-zfs-pool.sh writes, so the two scripts interoperate.
#
# Each menu action runs in a subshell: an error in one action returns to the menu.
# Destructive actions require typing the pool name. Safe to abort with Ctrl-C.
# =============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'
die()  { echo -e "${RED}error:${RESET} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}warning:${RESET} $*" >&2; }
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
hdr()  { echo ""; echo -e "${BOLD}── $* ──────────────────────────────────────────${RESET}"; }

# Resolve siblings via the UNRESOLVED path: when deployed through home-manager the
# scripts are separate symlinks in ~/scripts, not files in one store directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZFS_POOLS_NIX="${ZFS_POOLS_NIX:-/etc/nixos/zfs-pools.nix}"
PVE_STOR_CFG="${PVE_STOR_CFG:-/etc/pve/storage.cfg}"
BEGIN_MARK="# >>> vexos-zfs-pools >>>"
END_MARK="# <<< vexos-zfs-pools <<<"

POOL=""; LEAF=""
declare -a CANDIDATES=() CAND_DEV=() CAND_INFO=() SELECTED_BYID=()

# ---------- Generic helpers --------------------------------------------------

# Read one line into REPLY; abort the action (not loop forever) if stdin closes.
ask() { printf "%s" "$1"; read -r REPLY || die "input closed"; }

confirm_name() {
    echo "To proceed, type the pool name '$1' exactly:"
    ask "> "
    [ "$REPLY" = "$1" ] || die "confirmation mismatch — aborting (no changes made)"
}

pause() { printf "\nPress Enter to return to the menu... "; read -r _ || exit 0; }

run_action() { ( "$@" ); pause; }

wipe_disks() {
    local d
    for d in "$@"; do
        echo "  wipefs -a $d"
        wipefs -a "$d" >/dev/null || die "wipefs failed on $d"
        echo "  sgdisk --zap-all $d"
        sgdisk --zap-all "$d" >/dev/null || die "sgdisk failed on $d"
    done
}

# ---------- Pool / device pickers --------------------------------------------

# Sets POOL to the chosen imported pool.
pick_pool() {
    local -a names=()
    local i sel
    mapfile -t names < <(zpool list -H -o name 2>/dev/null)
    [ "${#names[@]}" -gt 0 ] || die "no ZFS pools are imported (use 'Import an existing pool' to bring one in)"
    echo ""
    for i in "${!names[@]}"; do
        zpool list -H -o name,size,alloc,free,health "${names[$i]}" \
            | awk -F'\t' -v n="$((i+1))" '{printf "  %d) %-16s size %-8s used %-8s free %-8s %s\n", n, $1, $2, $3, $4, $5}'
    done
    echo ""
    while true; do
        ask "Pool [1-${#names[@]}]: "
        sel="$REPLY"
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#names[@]}" ]; then
            POOL="${names[$((sel-1))]}"
            return 0
        fi
        echo "  invalid"
    done
}

# Print "<device> <state>" for every disk in pool $1 (full paths; a numeric GUID
# for a disk that has gone missing). Reads the config table of `zpool status -P`.
pool_leaves() {
    zpool status -P "$1" 2>/dev/null | awk -v pool="$1" '
        /^[[:space:]]*NAME[[:space:]]+STATE/ { cfg = 1; next }
        cfg && /^[[:space:]]*$/              { cfg = 0 }
        cfg && NF >= 2 && $1 != pool && $1 !~ /^(mirror|raidz[123]?|draid[^ ]*|spare|replacing|logs|cache|spares|special|dedup)(-[0-9]+)?$/ { print $1, $2 }'
}

# $1 = pool. Sets LEAF to the chosen disk of that pool.
pick_leaf() {
    local -a devs=() states=()
    local d s i sel
    while read -r d s; do
        devs+=("$d"); states+=("$s")
    done < <(pool_leaves "$1")
    [ "${#devs[@]}" -gt 0 ] || die "could not read the disks of pool '$1'"
    echo ""
    for i in "${!devs[@]}"; do
        printf "  %d) %-70s %s\n" "$((i+1))" "${devs[$i]}" "${states[$i]}"
    done
    echo ""
    while true; do
        ask "Disk [1-${#devs[@]}]: "
        sel="$REPLY"
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#devs[@]}" ]; then
            LEAF="${devs[$((sel-1))]}"
            return 0
        fi
        echo "  invalid"
    done
}

# Kernel names (sda, nvme0n1, ...) of whole disks that belong to an imported pool.
in_pool_disks() {
    local pool path dev parent
    while read -r pool; do
        while read -r path _; do
            [[ "$path" == /dev/* ]] || continue
            dev=$(readlink -f "$path") || continue
            parent=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)
            basename "${parent:-$dev}"
        done < <(pool_leaves "$pool")
    done < <(zpool list -H -o name 2>/dev/null) | sort -u
}

# Fill CANDIDATES/CAND_DEV/CAND_INFO with whole disks that are safe to offer and
# print them. Skips disks with anything mounted (/, /boot, /nix, swap, data) and
# disks that are part of an imported pool; de-duplicates ata-/wwn- aliases.
enumerate_disks() {
    CANDIDATES=(); CAND_DEV=(); CAND_INFO=()
    local used byid dev base info tag hidden=0 i
    used=$(in_pool_disks)
    while IFS= read -r byid; do
        [ -L "/dev/disk/by-id/$byid" ] || continue
        case "$byid" in
            *-part[0-9]*) continue ;;        # skip partition links
            ata-*|nvme-*|scsi-*|wwn-*) ;;
            *) continue ;;
        esac
        dev=$(readlink -f "/dev/disk/by-id/$byid")
        base=$(basename "$dev")
        printf '%s\n' "${CAND_DEV[@]}" | grep -qx "$base" && continue   # alias of a disk already listed
        if lsblk -nr -o MOUNTPOINT "$dev" 2>/dev/null | grep -q .; then
            continue
        fi
        if echo "$used" | grep -qx "$base"; then
            hidden=$((hidden+1)); continue
        fi
        info=$(lsblk -dno SIZE,MODEL,TRAN "$dev" 2>/dev/null | head -1)
        tag=""
        if lsblk -nr -o FSTYPE "$dev" 2>/dev/null | grep -qx "zfs_member"; then
            tag="  [has old ZFS labels]"
        fi
        CANDIDATES+=("$byid"); CAND_DEV+=("$base"); CAND_INFO+=("$info$tag")
    done < <(ls /dev/disk/by-id/ 2>/dev/null)

    [ "${#CANDIDATES[@]}" -gt 0 ] || die "no eligible disks found (every disk is mounted or already in a pool)"
    echo ""
    printf "  %-3s  %-50s  %-10s  %s\n" "#" "by-id" "device" "size / model / tran"
    printf "  %-3s  %-50s  %-10s  %s\n" "-" "-----" "------" "-------------------"
    for i in "${!CANDIDATES[@]}"; do
        printf "  %-3s  %-50s  %-10s  %s\n" "$((i+1))" "${CANDIDATES[$i]}" "${CAND_DEV[$i]}" "${CAND_INFO[$i]}"
    done
    [ "$hidden" -eq 0 ] || echo "  ($hidden disk(s) hidden because they already belong to an imported pool)"
    echo ""
}

# $1 = minimum disks, $2 = maximum disks (0 = no limit). Sets SELECTED_BYID.
select_disks() {
    local min="$1" max="$2" idx input seen valid
    while true; do
        ask "Select disks (comma- or space-separated numbers, e.g. '1 2'): "
        input="${REPLY//,/ }"
        SELECTED_BYID=(); seen=" "; valid=1
        for idx in $input; do
            if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#CANDIDATES[@]}" ]; then
                echo "  invalid number: $idx"; valid=0; break
            fi
            if [[ "$seen" == *" $idx "* ]]; then
                echo "  disk $idx listed twice"; valid=0; break
            fi
            seen="$seen$idx "
            SELECTED_BYID+=("/dev/disk/by-id/${CANDIDATES[$((idx-1))]}")
        done
        [ "$valid" -eq 1 ] || continue
        if [ "${#SELECTED_BYID[@]}" -lt "$min" ]; then
            echo "  select at least $min disk(s)"; continue
        fi
        if [ "$max" -gt 0 ] && [ "${#SELECTED_BYID[@]}" -gt "$max" ]; then
            echo "  select at most $max disk(s)"; continue
        fi
        return 0
    done
}

# ---------- Boot-import registry (/etc/nixos/zfs-pools.nix) -------------------

# Pool names listed inside the managed block, one per line.
registered_pools() {
    [ -f "$ZFS_POOLS_NIX" ] || return 0
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0 ~ b {f=1; next} $0 ~ e {f=0} f' "$ZFS_POOLS_NIX" \
        | sed -n 's/^[[:space:]]*"\(.*\)".*/\1/p'
}

# Rewrite the registry with exactly the pool names given as arguments.
write_registered_pools() {
    local name
    if [ -f "$ZFS_POOLS_NIX" ]; then
        cp -a "$ZFS_POOLS_NIX" "${ZFS_POOLS_NIX}.bak"
        warn "existing $ZFS_POOLS_NIX backed up to ${ZFS_POOLS_NIX}.bak"
    fi
    {
        echo "# /etc/nixos/zfs-pools.nix"
        echo "# GENERATED/updated by scripts/zfs-pool.sh on $(date '+%Y-%m-%d %H:%M:%S')."
        echo "# Registers ZFS pools managed via 'just zfs-pool' so NixOS generates a"
        echo "# zfs-import-<pool>.service unit for each and imports them automatically on"
        echo "# every boot. Without this, pools created imperatively never auto-import —"
        echo "# see modules/zfs-server.nix for why boot.zfs.extraPools must list them."
        echo "# Host-generated — do NOT commit to the vexos-nix repo."
        echo "{ ... }:"
        echo "{"
        echo "  boot.zfs.extraPools = ["
        echo "    $BEGIN_MARK"
        for name in "$@"; do
            echo "    \"$name\""
        done
        echo "    $END_MARK"
        echo "  ];"
        echo "}"
    } > "$ZFS_POOLS_NIX" || die "could not write $ZFS_POOLS_NIX"
}

register_pool() {
    local -a names=()
    mapfile -t names < <(registered_pools)
    if [[ " ${names[*]} " != *" $1 "* ]]; then
        names+=("$1")
    fi
    write_registered_pools "${names[@]}"
    ok "pool '$1' registered for boot-time import in $ZFS_POOLS_NIX"
}

unregister_pool() {
    local -a names=() keep=()
    local n
    mapfile -t names < <(registered_pools)
    for n in "${names[@]}"; do
        [ "$n" = "$1" ] || keep+=("$n")
    done
    if [ "${#keep[@]}" -eq "${#names[@]}" ]; then
        echo "  pool '$1' was not listed in $ZFS_POOLS_NIX — nothing to remove"
        return 0
    fi
    write_registered_pools "${keep[@]}"
    ok "pool '$1' removed from $ZFS_POOLS_NIX"
}

rebuild_reminder() {
    echo ""
    echo "Apply with your normal rebuild (e.g. 'just rebuild') so NixOS's boot-time"
    echo "import list matches. Until then the change above only affects this boot."
}

# IDs of Proxmox zfspool storages whose pool is $1 or a dataset under it.
pve_storage_ids_for() {
    [ -f "$PVE_STOR_CFG" ] || return 0
    awk -v pool="$1" '
        /^zfspool:/            { id = $2; next }
        /^[^[:space:]]/        { id = "" }
        id != "" && $1 == "pool" && ($2 == pool || index($2, pool "/") == 1) { print id; id = "" }
    ' "$PVE_STOR_CFG"
}

# ---------- Actions ----------------------------------------------------------

action_status() {
    hdr "Pools and health"
    if [ -z "$(zpool list -H -o name 2>/dev/null)" ]; then
        echo "  No ZFS pools are imported."
        return 0
    fi
    zpool list
    echo ""
    zpool status
    echo ""
    zfs list -r -o name,used,avail,mountpoint
}

action_create() {
    hdr "Create a new pool"
    [ -f "$SCRIPT_DIR/create-zfs-pool.sh" ] || die "create-zfs-pool.sh not found next to this script ($SCRIPT_DIR)"
    bash "$SCRIPT_DIR/create-zfs-pool.sh"
}

action_destroy() {
    hdr "Destroy a pool"
    pick_pool
    local -a sids=()
    local id
    echo ""
    zpool status "$POOL"
    echo ""
    zfs list -r -o name,used,mountpoint "$POOL"
    mapfile -t sids < <(pve_storage_ids_for "$POOL")
    echo ""
    echo -e "${RED}This permanently destroys pool '$POOL' and ALL data in it (every dataset,${RESET}"
    echo -e "${RED}VM disk and snapshot). It cannot be undone.${RESET}"
    [ "${#sids[@]}" -eq 0 ] || echo "  Proxmox storage entries on this pool, to be removed: ${sids[*]}"
    echo "  The pool will also be removed from $ZFS_POOLS_NIX (boot-time import)."
    echo ""
    confirm_name "$POOL"

    zpool destroy "$POOL" || die "zpool destroy failed — if the pool is busy, stop the VMs/services using it (try: lsof +D /$POOL) and retry"
    ok "pool '$POOL' destroyed"

    if [ "${#sids[@]}" -gt 0 ]; then
        if command -v pvesm >/dev/null 2>&1 && mountpoint -q /etc/pve; then
            for id in "${sids[@]}"; do
                if pvesm remove "$id"; then
                    ok "Proxmox storage '$id' removed"
                else
                    warn "could not remove Proxmox storage '$id' — remove it in Datacenter → Storage"
                fi
            done
        else
            warn "Proxmox is not running here — remove storage ID(s) '${sids[*]}' later in Datacenter → Storage"
        fi
    fi
    unregister_pool "$POOL"
    rebuild_reminder
}

action_import() {
    hdr "Import an existing pool"
    local out force
    local -a names=()
    local i sel
    out=$(zpool import -d /dev/disk/by-id 2>&1)
    mapfile -t names < <(printf '%s\n' "$out" | awk '/^[[:space:]]*pool:/ {print $2}')
    if [ "${#names[@]}" -eq 0 ]; then
        echo "  No importable pools found on the connected disks."
        return 0
    fi
    printf '%s\n' "$out"
    echo ""
    for i in "${!names[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "${names[$i]}"
    done
    echo ""
    while true; do
        ask "Pool to import [1-${#names[@]}]: "
        sel="$REPLY"
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#names[@]}" ]; then
            POOL="${names[$((sel-1))]}"
            break
        fi
        echo "  invalid"
    done

    if ! zpool import -d /dev/disk/by-id "$POOL"; then
        ask "Import failed. Force it with -f? Only if the disks are NOT in use by another machine [y/N]: "
        force="${REPLY,,}"
        case "$force" in
            y|yes) zpool import -f -d /dev/disk/by-id "$POOL" || die "forced import failed" ;;
            *)     die "import cancelled" ;;
        esac
    fi
    ok "pool '$POOL' imported"
    register_pool "$POOL"
    rebuild_reminder
}

action_replace() {
    hdr "Replace a disk"
    pick_pool
    echo ""
    echo "Which disk is being replaced?"
    pick_leaf "$POOL"
    local old="$LEAF"
    echo ""
    echo "Pick the NEW disk (at least as large as the one it replaces). It will be erased."
    enumerate_disks
    select_disks 1 1
    local new="${SELECTED_BYID[0]}"

    echo ""
    echo "  Pool     : $POOL"
    echo "  Replace  : $old"
    echo "  With     : $new   (will be wiped)"
    echo ""
    confirm_name "$POOL"
    wipe_disks "$new"
    zpool replace "$POOL" "$old" "$new" || die "zpool replace failed (see message above)"
    ok "replace started — ZFS is copying data to the new disk (resilvering)"
    zpool status "$POOL"
}

action_add() {
    hdr "Add disks to a pool"
    pick_pool
    echo ""
    zpool status "$POOL"
    echo ""
    echo "  How should the new disks be added? (permanent — ZFS cannot remove them again)"
    echo "  1) Mirror — 2 or more disks, adds the space of ONE disk, every disk a full copy"
    echo "  2) RAID-Z1 — 3 or more disks, adds N-1 disks of space, survives 1 failure"
    echo "  3) RAID-Z2 — 4 or more disks, adds N-2 disks of space, survives 2 failures"
    echo "  4) Single disk — adds its full space but NO protection: if it fails, the"
    echo "     WHOLE pool is lost"
    echo "  Match the style of the pool's existing disks; ZFS refuses mismatches."
    echo ""
    local kind min max
    while true; do
        ask "Choice [1-4]: "
        kind="$REPLY"
        case "$kind" in
            1|2|3|4) break ;;
            *) echo "  invalid" ;;
        esac
    done
    max=0
    case "$kind" in
        1) min=2 ;;
        2) min=3 ;;
        3) min=4 ;;
        4) min=1; max=1 ;;
    esac
    echo ""
    enumerate_disks
    select_disks "$min" "$max"

    local -a vdev=()
    case "$kind" in
        1) vdev=(mirror "${SELECTED_BYID[@]}") ;;
        2) vdev=(raidz1 "${SELECTED_BYID[@]}") ;;
        3) vdev=(raidz2 "${SELECTED_BYID[@]}") ;;
        4) vdev=("${SELECTED_BYID[@]}") ;;
    esac

    echo ""
    echo "Preview (nothing is changed yet):"
    zpool add -n -f "$POOL" "${vdev[@]}" || die "ZFS rejected this layout (see above) — nothing was changed"
    echo ""
    echo -e "${RED}The listed disks will be ERASED and added to '$POOL' permanently.${RESET}"
    confirm_name "$POOL"
    wipe_disks "${SELECTED_BYID[@]}"
    zpool add "$POOL" "${vdev[@]}" || die "zpool add failed — usually a redundancy mismatch with the pool's existing disks (see message above)"
    ok "disks added to '$POOL'"
    zpool list "$POOL"
}

action_attach() {
    hdr "Attach a disk to a mirror"
    pick_pool
    echo ""
    echo "Attaching adds one more full copy of an existing disk: a 2-disk mirror becomes"
    echo "3-way, and a single disk becomes a 2-disk mirror. Space does not grow."
    echo "Which existing disk should the new disk copy?"
    pick_leaf "$POOL"
    local existing="$LEAF"
    echo ""
    echo "Pick the NEW disk (at least as large as the existing one). It will be erased."
    enumerate_disks
    select_disks 1 1
    local new="${SELECTED_BYID[0]}"

    echo ""
    echo "  Pool     : $POOL"
    echo "  Copy of  : $existing"
    echo "  New disk : $new   (will be wiped)"
    echo ""
    confirm_name "$POOL"
    wipe_disks "$new"
    zpool attach "$POOL" "$existing" "$new" || die "zpool attach failed (see message above)"
    ok "attach started — ZFS is copying data to the new disk (resilvering)"
    zpool status "$POOL"
}

action_detach() {
    hdr "Detach a disk from a mirror"
    pick_pool
    echo ""
    echo "Which disk should be removed from its mirror? (the pool keeps its other copies)"
    pick_leaf "$POOL"
    echo ""
    echo "  Pool : $POOL"
    echo "  Disk : $LEAF"
    ask "Detach this disk? [y/N]: "
    case "${REPLY,,}" in
        y|yes) ;;
        *) die "cancelled — nothing changed" ;;
    esac
    zpool detach "$POOL" "$LEAF" || die "zpool detach failed — only mirror disks can be detached (see message above)"
    ok "disk detached from '$POOL'"
    zpool status "$POOL"
}

action_scrub() {
    hdr "Scrub a pool"
    pick_pool
    echo ""
    echo "A scrub reads every block and repairs bad data from the redundant copies."
    echo "(NixOS already scrubs all pools monthly; this runs one now.)"
    echo "  1) Start a scrub"
    echo "  2) Stop a running scrub"
    while true; do
        ask "Choice [1-2]: "
        case "$REPLY" in
            1) zpool scrub "$POOL" || die "could not start the scrub"; ok "scrub started on '$POOL'"; break ;;
            2) zpool scrub -s "$POOL" || die "could not stop the scrub (is one running?)"; ok "scrub stopped on '$POOL'"; break ;;
            *) echo "  invalid" ;;
        esac
    done
    zpool status "$POOL"
}

action_clear() {
    hdr "Clear error counters"
    pick_pool
    echo ""
    echo "Resets the read/write/checksum error counts. Only do this after fixing the cause"
    echo "(cable, controller, replaced disk) — it does not repair anything by itself."
    ask "Clear errors on '$POOL'? [y/N]: "
    case "${REPLY,,}" in
        y|yes) ;;
        *) die "cancelled — nothing changed" ;;
    esac
    zpool clear "$POOL" || die "zpool clear failed"
    ok "error counters cleared on '$POOL'"
    zpool status "$POOL"
}

# ---------- Preconditions ----------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "must be run as root (use 'just zfs-pool', which calls sudo)"
for t in zpool zfs sgdisk wipefs lsblk; do
    command -v "$t" >/dev/null 2>&1 || die "$t not found — modules/zfs-server.nix not active (or gptfdisk/util-linux missing)"
done

# ---------- Direct action: `just zfs-pool <action>` ---------------------------
if [ $# -gt 0 ]; then
    case "$1" in
        status|create|destroy|import|replace|add|attach|detach|scrub|clear)
            "action_$1"; exit $? ;;
        *)  die "unknown action '$1' (status, create, destroy, import, replace, add, attach, detach, scrub, clear)" ;;
    esac
fi

# ---------- Menu -------------------------------------------------------------
while true; do
    hdr "ZFS pool manager"
    echo "   1) Show pools and their health"
    echo "   2) Create a new pool"
    echo "   3) Destroy a pool                  (erases the pool and all its data)"
    echo "   4) Import an existing pool         (bring a pool back after a reinstall or moving disks)"
    echo "   5) Replace a disk                  (swap a failed or old disk for a new one)"
    echo "   6) Add disks to a pool             (more space; permanent)"
    echo "   7) Attach a disk to a mirror       (another full copy; also turns a single disk into a mirror)"
    echo "   8) Detach a disk from a mirror     (removes one copy)"
    echo "   9) Scrub a pool                    (check all data for errors)"
    echo "  10) Clear error counters on a pool  (after fixing a cable or replacing a disk)"
    echo "   0) Quit"
    echo ""
    ask "Choice [0-10]: "
    case "$REPLY" in
        1)  run_action action_status ;;
        2)  run_action action_create ;;
        3)  run_action action_destroy ;;
        4)  run_action action_import ;;
        5)  run_action action_replace ;;
        6)  run_action action_add ;;
        7)  run_action action_attach ;;
        8)  run_action action_detach ;;
        9)  run_action action_scrub ;;
        10) run_action action_clear ;;
        0|q|Q) exit 0 ;;
        *)  echo "  invalid" ;;
    esac
done
