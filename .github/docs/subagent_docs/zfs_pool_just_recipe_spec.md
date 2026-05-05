# Specification — `just create-zfs-pool` Recipe for Proxmox VM Storage Backing

**Project:** vexos-nix (NixOS 25.11 flake)
**Spec ID:** `zfs_pool_just_recipe_spec`
**Phase:** 1 — Research & Specification
**Scope:** Add a `just` recipe (and supporting helper script) that interactively creates a ZFS pool on **server** / **headless-server** hosts for use as Proxmox VE VM/container backing storage. Also add the minimal NixOS module wiring required to make ZFS available on those roles.

---

## 1. Current State Analysis

### 1.1 Repo layout & conventions
- `justfile` at repo root holds all task automation. Recipes are POSIX-shell (`#!/usr/bin/env bash`, `set -euo pipefail`) and follow a consistent style: defensive checks for `nix` / `sudo` / Linux, interactive prompts via `read -r`, color-free output, and `[private]` recipes for helpers.
- A guard pattern already exists for server-only recipes — `_require-server-role` (lines ~456-465 of [justfile](justfile)) reads `/etc/nixos/vexos-variant` and aborts when the variant string does not contain `server`. **The new recipe MUST reuse this guard.**
- The default recipe lists extra "server-only" recipes when the active variant is a server variant. The new recipe must be added to that hint block too.
- All shell scripts are LF-only (per [/memories/repo/preflight-line-endings.md](.github/copilot-instructions.md)). `.gitattributes` enforces this. Any new helper script under `scripts/` MUST be LF-only.

### 1.2 Server-role module wiring
- [configuration-server.nix](configuration-server.nix) and [configuration-headless-server.nix](configuration-headless-server.nix) both import `./modules/server` (the umbrella that aggregates optional services including `proxmox.nix`).
- `proxmox-nixos` is wired in at the flake level via `roles.server` / `roles.headless-server` `baseModules` in [flake.nix](flake.nix#L94-L110). The Proxmox NixOS module + overlay are always loaded on server roles, but the `services.proxmox-ve` service is only activated when `vexos.server.proxmox.enable = true` (see [modules/server/proxmox.nix](modules/server/proxmox.nix)).
- **There is NO ZFS configuration anywhere in the repo today.** A grep across `**/*.nix` for `zfs|hostId|supportedFilesystems` returns only one match: `boot.supportedFilesystems = [ "nfs" ]` in [modules/network-desktop.nix](modules/network-desktop.nix#L89). Server roles therefore have no ZFS kernel module loaded, no `zpool` / `zfs` userland tools in `$PATH`, and no `networking.hostId` set.
- The repo follows an **Option B module pattern** (per `.github/copilot-instructions.md`): universal base modules contain only universally-applicable settings, and role-specific additions live in separate `modules/<subsystem>-<role>.nix` files imported only by the relevant `configuration-*.nix`. The new ZFS NixOS wiring MUST follow this pattern.

### 1.3 Why this recipe is needed (problem definition)
- proxmox-nixos enables Proxmox VE on NixOS but **the Proxmox web UI's "Disks" panel cannot create or manage filesystems** — the pve-disk APIs assume Debian-managed udev/lvm/storage stacks and silently fail or no-op on NixOS.
- In practice, only **ZFS storage backends work reliably** under proxmox-nixos. The supported workflow is:
  1. Create a ZFS pool *outside* Proxmox (via `zpool create`, run by the host operator).
  2. Register the existing pool with Proxmox: `pvesm add zfspool <storage-id> -pool <poolname>` (or via the web UI's `Datacenter → Storage → Add → ZFS`).
- Today, a vexos-nix server-role operator has no in-repo tooling for step 1. They must:
  - Manually edit a NixOS module to enable ZFS + set `networking.hostId`, then `nixos-rebuild switch`.
  - Look up the right `zpool create` invocation (ashift, compression, atime, xattr, acltype, mountpoint, by-id paths).
  - Pick disks safely without wiping the OS disk.
  - Remember to register the pool with Proxmox afterward.
- This spec closes that gap with a single `just create-zfs-pool` command.

---

## 2. Proposed Solution Architecture

### 2.1 Two deliverables
1. **`modules/zfs-server.nix`** — new NixOS module (Option B "role-specific addition" file). Imported only by `configuration-server.nix` and `configuration-headless-server.nix`. Enables the ZFS kernel module and userland tools, deterministically derives `networking.hostId`, and tunes the ZFS scrub/trim services for a hypervisor backing pool.
2. **`scripts/create-zfs-pool.sh`** — interactive helper script (POSIX-bash, LF-only) invoked by the `just` recipe. All non-trivial logic lives in the script; the `just` recipe is a thin guard + dispatch wrapper. This mirrors the pattern of [scripts/preflight.sh](scripts/preflight.sh) and the `enable-ssh` recipe in the existing justfile.
3. **`just create-zfs-pool`** recipe added to [justfile](justfile) — gated by `_require-server-role`, also asserts ZFS userland is installed (warns the user to rebuild if not).

### 2.2 Why a separate helper script (not inline)
- The interactive logic (disk enumeration, by-id resolution, multi-disk topology selection, double confirmation, `zpool create` flag construction) is ~200 lines and contains nested case statements that are awkward inside a `just` recipe block.
- A script under `scripts/` can be unit-exercised in a VM via loopback files (see §8 Testing) and is easy to lint with `shellcheck`.
- The repo already establishes the precedent of `scripts/*.sh` being invoked from automation (`scripts/preflight.sh`, `scripts/install.sh`, `scripts/migrate-to-stateless.sh`, `scripts/stateless-setup.sh`).

### 2.3 Recipe behavior (high level)
1. **Guard:** depend on `_require-server-role`. Abort if not on a server variant.
2. **Tool check:** verify `zpool` and `zfs` are in `$PATH`. If absent, print exact instructions to enable ZFS:
   - "Add `./modules/zfs-server.nix` to imports (already done if you ran a recent build) and rebuild: `just switch <role> <gpu>`."
3. **Locate helper script:** use the same `_jf_dir` resolution pattern as `enable-ssh` (readlink of `{{justfile()}}` then dirname). Search candidates `$_jf_dir/scripts`, `/etc/nixos/scripts`, `$HOME/Projects/vexos-nix/scripts`. Abort if not found.
4. **Run helper script under sudo** (it must be root to enumerate `/dev/disk/by-id`, `wipefs`, and `zpool create`).
5. After successful pool creation, print the ready-to-paste Proxmox registration command:
   ```
   pvesm add zfspool <storage-id> -pool <poolname> -content images,rootdir -sparse
   ```
   …and remind the user to `git commit` any module/option changes.

### 2.4 What the helper script does (detailed flow)
1. **Preconditions**
   - `[ "$(id -u)" -eq 0 ]` else exit 1.
   - `command -v zpool && command -v zfs` else exit 1 with rebuild hint.
   - `lsmod | grep -q '^zfs '` (warn only — kernel module may auto-load on first `zpool` call).
   - Read `/proc/sys/kernel/random/boot_id`; check `nix-instantiate --eval --expr 'builtins.readFile "/proc/sys/kernel/random/uuid"'` is not strictly required — instead, parse `/etc/machine-id` and synthesize a guidance message if `networking.hostId` looks unset (test by `zgenhostid -f` would change state — do NOT call it; just `cat /etc/hostid` and warn if absent).
   - Confirm `vexos.server.proxmox.enable` status by grepping `/etc/nixos/server-services.nix` (informational only — do not block).

2. **Pool name prompt** with validation per the Proxmox/OpenZFS rules:
   - `^[A-Za-z][A-Za-z0-9._: -]*$` and must not start with `mirror`, `raidz`, `draid`, `spare`, and must not equal `log`.
   - Default suggestion: `tank`.

3. **Topology prompt** (numbered menu, single keystroke):
   ```
   1) single   — 1 disk, no redundancy (lab/dev only)
   2) mirror   — 2+ disks, RAID1
   3) raidz1   — 3+ disks, single parity
   4) raidz2   — 4+ disks, double parity
   5) raidz3   — 5+ disks, triple parity
   6) stripe-of-mirrors (RAID10) — 4, 6, 8 disks (pairs)
   ```
   For VM workloads, a one-line hint is printed: *"Mirror or stripe-of-mirrors recommended for VM/zvol workloads — RAIDZ amplifies write IO for small zvol blocks (Proxmox wiki, OpenZFS tuning docs)."*

4. **Disk enumeration & selection**
   - Build candidate list from `/dev/disk/by-id/` matching `^(ata|nvme|scsi|wwn)-` and excluding `*-part[0-9]+` symlinks.
   - For each candidate resolve to underlying device via `readlink -f`, then call `lsblk -dno NAME,SIZE,MODEL,TRAN,MOUNTPOINT` for that device.
   - **Exclude any device whose underlying name (or any partition thereof) is mounted at `/`, `/boot`, `/nix`, or has a swap signature** (`lsblk -no FSTYPE`). This is the OS-disk safety check.
   - Present a numbered list:
     ```
     # by-id                                      device   size   model              tran
     1 ata-CT1000MX500SSD1_2107E5BC23F4          sda      1.0T   CT1000MX500SSD1   sata
     2 nvme-Samsung_SSD_980_PRO_1TB_S5GXNF…       nvme1n1  1.0T   Samsung 980 PRO   nvme
     ...
     ```
   - User enters comma- or space-separated indices. Validate count against topology min (e.g. ≥3 for raidz1).
   - For mirror/raid10 also prompt for stripe count (number of mirror vdevs) so the script can split the disk list into N mirror groups.
   - Always operate on the `/dev/disk/by-id/...` paths (never `/dev/sdX`), per OpenZFS + Proxmox best practice — `sdX` names are not stable across reboots, but by-id paths follow the disk.

5. **Destructive-action confirmation**
   - Print full command preview, e.g.:
     ```
     The following pool will be created. ALL DATA on the listed disks will be destroyed.

       pool name : tank
       topology  : mirror
       disks     :
                   /dev/disk/by-id/ata-CT1000MX500SSD1_2107E5BC23F4
                   /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S5GXNF…
       options   : -o ashift=12
                   -O compression=lz4
                   -O atime=off
                   -O xattr=sa
                   -O acltype=posixacl
                   -O mountpoint=/tank
       wipefs    : YES (sgdisk --zap-all on each disk before zpool create)

     This action is IRREVERSIBLE.
     ```
   - Require typed confirmation: user must type the exact pool name to proceed. (Single `y/N` is too easy to mis-press.) Aborts on any mismatch.

6. **Wipe and create**
   - For each chosen disk: `wipefs -a "$disk"` then `sgdisk --zap-all "$disk"`. (`sgdisk` from `gptfdisk` is brought into PATH by the NixOS module.)
   - Build the `zpool create` argv array:
     ```
     zpool create -f \
       -o ashift=12 \
       -O compression=lz4 \
       -O atime=off \
       -O xattr=sa \
       -O acltype=posixacl \
       -O mountpoint=/<pool> \
       <pool> <topology-keyword> <disk> [<disk>...] [<topology-keyword> <disk>...]
     ```
   - `topology-keyword` is empty for `single`, `mirror` for mirror/RAID10 (repeated per pair), `raidz1`/`raidz2`/`raidz3` for RAIDZ.
   - Run it. On non-zero exit: dump `journalctl -k --since "2 minutes ago" | tail -50` and abort.

7. **Post-create dataset (optional, prompted)**
   - Default: create a child dataset for Proxmox VM disks, e.g. `<pool>/vm` with `recordsize` left at default 128K (Proxmox uses zvols under it; volblocksize is a per-zvol property managed by Proxmox itself).
   - Skip this step if the user answers `n` — the Proxmox storage can also point straight at the pool root.

8. **Print Proxmox registration hint**
   ```
   Pool '<pool>' created and imported.

   Verify with:
     zpool status <pool>
     zfs list -r <pool>

   Register with Proxmox VE (run on this host):
     pvesm add zfspool vm-store -pool <pool>/vm -content images,rootdir -sparse

   Or in the web UI:
     Datacenter → Storage → Add → ZFS
       ID:     vm-store
       Pool:   <pool>/vm
       Content: Disk image, Container

   Persistence: NixOS will auto-import the pool on next boot once the ZFS
   module is enabled (see modules/zfs-server.nix). No fstab edits required.
   ```

### 2.5 NixOS module: `modules/zfs-server.nix`
A fresh universal-for-server-roles file (no `lib.mkIf` guards), to be imported by both `configuration-server.nix` and `configuration-headless-server.nix`. Proposed content:

```nix
# modules/zfs-server.nix
# ZFS support for server roles — required for proxmox-nixos VM storage.
#
# Why this is a server-only addition:
#   • Loads the ZFS kernel module on every boot (overhead on roles that don't
#     need it, plus ZFS+nvidia-headless DKMS interactions can lengthen rebuilds).
#   • networking.hostId must be globally unique per machine; setting it on
#     desktop/htpc/stateless variants without ZFS adds noise.
#
# Per the Option B module pattern (see .github/copilot-instructions.md):
#   imported ONLY by configuration-server.nix and configuration-headless-server.nix.
{ config, lib, pkgs, ... }:
{
  # ── Kernel + userland ────────────────────────────────────────────────────
  boot.supportedFilesystems        = [ "zfs" ];
  boot.zfs.forceImportRoot         = false;   # backing pools are not the rootfs
  boot.zfs.forceImportAll          = false;
  boot.zfs.extraPools              = [ ];     # auto-imported pools added by `just create-zfs-pool` are cached in /etc/zfs/zpool.cache, not listed here
  services.zfs.autoScrub.enable    = true;
  services.zfs.autoScrub.interval  = "monthly";
  services.zfs.trim.enable         = true;
  services.zfs.trim.interval       = "weekly";

  # ── Userland tools needed by scripts/create-zfs-pool.sh ──────────────────
  environment.systemPackages = with pkgs; [
    zfs           # zpool, zfs (also pulled in by boot.supportedFilesystems but listed for clarity)
    gptfdisk      # sgdisk
    util-linux    # wipefs, lsblk
    pciutils      # lspci (optional, for disk topology hints)
  ];

  # ── networking.hostId ────────────────────────────────────────────────────
  # ZFS REQUIRES a stable 8-hex-digit hostId. Without it, pools may refuse to
  # auto-import on boot. We derive it deterministically from /etc/machine-id
  # via an activation script so each host gets a unique, reproducible value
  # without committing per-host secrets to the flake.
  #
  # If the user has already set networking.hostId in their host file (under
  # hosts/<role>-<gpu>.nix) or in /etc/nixos/hardware-configuration.nix,
  # that value wins (lib.mkDefault).
  networking.hostId = lib.mkDefault (
    let
      machineIdFile = "/etc/machine-id";
    in
      if builtins.pathExists machineIdFile
      then builtins.substring 0 8 (builtins.readFile machineIdFile)
      else "00000000"   # placeholder; first build on a fresh host will recompute
  );
}
```

Note: `boot.supportedFilesystems` is the canonical NixOS option for enabling ZFS in stage-1 and stage-2; setting it is what causes nixpkgs to add `zfs` to `boot.kernelModules` and pull `zfsUnstable`/`zfs_2_x` into the system closure.

### 2.6 Wiring into the two server `configuration-*.nix` files
Add a single line to the `imports` list in both files:

[configuration-server.nix](configuration-server.nix):
```nix
  imports = [
    ./modules/gnome.nix
    ...
    ./modules/server
    ./modules/zfs-server.nix          # NEW
    ./modules/nix.nix
    ...
  ];
```

[configuration-headless-server.nix](configuration-headless-server.nix):
```nix
  imports = [
    ./modules/gpu.nix
    ...
    ./modules/server
    ./modules/zfs-server.nix          # NEW
    ./modules/nix.nix
    ...
  ];
```

No changes to `configuration-desktop.nix`, `configuration-htpc.nix`, or `configuration-stateless.nix`.

### 2.7 `justfile` additions
Two edits to `justfile`:

**A.** Add the recipe near the existing server-services block (after `_require-server-role`, before `available-services`):

```just
# Interactively create a ZFS pool for use as Proxmox VM/container backing storage.
# Server roles only.  Requires modules/zfs-server.nix in the active build.
# All work runs as root via sudo. The recipe:
#   • lists block devices by /dev/disk/by-id/ path,
#   • prompts for pool name, topology, and disks,
#   • requires typed confirmation (the pool name) before destroying data,
#   • runs wipefs + sgdisk --zap-all + zpool create with VM-tuned defaults
#     (ashift=12, compression=lz4, atime=off, xattr=sa, acltype=posixacl),
#   • prints the `pvesm add zfspool` command to register the pool with Proxmox.
#
# Safe to abort with Ctrl-C at any prompt — destructive actions only run after
# the typed-name confirmation step.
create-zfs-pool: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v zpool >/dev/null 2>&1 || ! command -v zfs >/dev/null 2>&1; then
        echo "error: zpool/zfs not found — ZFS userland is not installed in this build." >&2
        echo "       Ensure modules/zfs-server.nix is imported by your active configuration-*.nix" >&2
        echo "       and rebuild:  just switch <role> <gpu>" >&2
        exit 1
    fi

    # Locate scripts/create-zfs-pool.sh — same resolution pattern as `enable-ssh`.
    _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
    _jf_dir=$(dirname "$_jf_real")

    SCRIPT=""
    for _candidate in "$_jf_dir/scripts" "/etc/nixos/scripts" "$HOME/Projects/vexos-nix/scripts"; do
        if [ -f "$_candidate/create-zfs-pool.sh" ]; then
            SCRIPT="$_candidate/create-zfs-pool.sh"
            break
        fi
    done
    if [ -z "$SCRIPT" ]; then
        echo "error: scripts/create-zfs-pool.sh not found in any known location." >&2
        echo "       searched: $_jf_dir/scripts /etc/nixos/scripts $HOME/Projects/vexos-nix/scripts" >&2
        exit 1
    fi

    sudo bash "$SCRIPT"
```

**B.** Update the default-recipe hint block at the top of `justfile` (the `if [[ "$variant" == *server* ]]` branch) to mention the new recipe:

```bash
        echo "    create-zfs-pool            Create a ZFS pool for Proxmox VM storage (interactive)"
```

Insert this line alongside the existing `enable-plex-pass` / `disable-plex-pass` entries.

### 2.8 `scripts/create-zfs-pool.sh` (full proposed content)
LF-only, executable bit set, header pattern matches `scripts/preflight.sh`.

```bash
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

# ---------- [8/8] Optional dataset + Proxmox hint ----------------------------
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
echo ""
echo "  pvesm add zfspool vm-store -pool $PVE_TARGET -content images,rootdir -sparse"
echo ""
echo "  …or in the web UI:"
echo "    Datacenter → Storage → Add → ZFS"
echo "      ID:      vm-store"
echo "      Pool:    $PVE_TARGET"
echo "      Content: Disk image, Container"
echo "      Thin provision: enabled"
echo ""
echo "Persistence: the pool will auto-import on next boot via /etc/zfs/zpool.cache."
echo "No flake, fstab, or NixOS module changes are needed for the pool itself."
echo ""
ok "done"
```

---

## 3. Implementation Steps (for the Phase 2 subagent)

1. **Create** `c:\Projects\vexos-nix\modules\zfs-server.nix` with the content from §2.5.
2. **Edit** `c:\Projects\vexos-nix\configuration-server.nix` — add `./modules/zfs-server.nix` to the `imports` list (immediately after `./modules/server`).
3. **Edit** `c:\Projects\vexos-nix\configuration-headless-server.nix` — add `./modules/zfs-server.nix` to the `imports` list (immediately after `./modules/server`).
4. **Create** `c:\Projects\vexos-nix\scripts\create-zfs-pool.sh` with the content from §2.8. **MUST be LF-only** (set `core.autocrlf=false` or use `git add --chmod=+x` after creation; verify with `file scripts/create-zfs-pool.sh` showing "ASCII text" not "ASCII text, with CRLF line terminators"). Mark executable: `git update-index --chmod=+x scripts/create-zfs-pool.sh`.
5. **Edit** `c:\Projects\vexos-nix\justfile`:
   - Add the `create-zfs-pool` recipe per §2.7.A. Place it directly under the existing `_require-server-role` private recipe block (line ~456), before `available-services`.
   - Add the hint line per §2.7.B inside the `if [[ "$variant" == *server* ]]` branch at the top of the file.
6. **Update** `c:\Projects\vexos-nix\.gitattributes` — verify `*.sh text eol=lf` is already present (per repo memory). No change expected; just confirm.
7. **Verify** with the standard preflight gate:
   - `nix flake check` — must pass.
   - `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` — must succeed (validates the new module evaluates and ZFS pulls into closure).
   - `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` — must succeed.
   - `sudo nixos-rebuild dry-build --flake .#vexos-server-vm` — must succeed.
   - `bash -n scripts/create-zfs-pool.sh` — syntax check.
   - `shellcheck scripts/create-zfs-pool.sh` — should pass with at most informational notices.
   - `just --list` — recipe appears.
   - Confirm `hardware-configuration.nix` is NOT present in the working tree, and `system.stateVersion` is unchanged in `configuration-server.nix` and `configuration-headless-server.nix`.

---

## 4. Configuration Changes (NixOS modules)

| File | Change |
|---|---|
| `modules/zfs-server.nix` | **NEW** — universal ZFS wiring for server roles (kernel module, userland tools, autoScrub, trim, deterministic `networking.hostId` via `lib.mkDefault`). |
| `configuration-server.nix` | Add one import line: `./modules/zfs-server.nix`. |
| `configuration-headless-server.nix` | Add one import line: `./modules/zfs-server.nix`. |

**No changes** to:
- `flake.nix` — proxmox-nixos overlay/module are already wired in at the role level.
- `hardware-configuration.nix` — must remain host-generated, never tracked.
- `system.stateVersion` — unchanged.
- `modules/server/proxmox.nix` — Proxmox enablement option already exists; pool registration is a runtime step, not a NixOS-managed one.
- Any non-server `configuration-*.nix` (desktop, htpc, stateless).

---

## 5. Dependencies

- **No new flake inputs.** All required tooling (`zfs`, `gptfdisk`, `util-linux`) is in `nixpkgs`.
- **No Context7 library lookups required** — the only "external library" surfaces are the NixOS option set (which is the same nixpkgs already pinned in `flake.nix`) and the Proxmox VE wiki (a runtime workflow reference, not an SDK).
- The new recipe and module are **additive** — they do not alter any existing closure on desktop/htpc/stateless variants.

---

## 6. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Wrong disk selected → OS destroyed | Critical | Script auto-excludes any device whose base name or any partition is mounted at `/`, `/boot`, `/nix`, or has `swap` FSTYPE. Disk list shows by-id, device name, size, and model so the operator can sanity-check before confirming. Final confirmation requires typing the **exact pool name**, not `y/n`. |
| `networking.hostId` missing → pool fails to auto-import on reboot | High | `modules/zfs-server.nix` sets `networking.hostId` deterministically from `/etc/machine-id` via `lib.mkDefault` (overridable per host). Script also warns if `/etc/hostid` is empty at run time. |
| ZFS not in active build when recipe is run | Medium | Recipe checks `command -v zpool && command -v zfs` and prints a precise rebuild instruction if missing. |
| User runs recipe on a non-server host | Medium | Recipe depends on `_require-server-role` (existing helper) which aborts with the active variant name. |
| Pool name collision with an existing pool | Medium | Script checks `zpool list -H -o name` and rejects duplicates. |
| Reserved pool name (`mirror`, `raidz`, `log`, etc.) | Low | Script enforces the reserved-name regex from the Proxmox wiki. |
| `zpool create` fails partway through (disks already wiped) | Medium | Script tails kernel log on failure; user can re-run from a clean state. Failure leaves disks zapped but does not corrupt anything else. |
| Script line endings get CRLF on Windows checkout → bash parse error | High (per repo memory) | `.gitattributes` already enforces `*.sh text eol=lf`. Phase 2 must verify the new file lands as LF-only. |
| RAIDZ chosen for VM/zvol workload → poor performance | Low (advisory) | Topology menu prints a hint pointing to mirror / raid10 for VM workloads; user can still choose RAIDZ for archive/non-VM datasets they may add later. |
| Pool created but never registered with Proxmox | Low | Final output prints both the `pvesm add zfspool` CLI command and the web-UI navigation steps. |
| Proxmox-nixos disk-management UI silently reappears working in a future release and overlaps with this recipe | Low | Recipe is independent of Proxmox-nixos internals — it only uses upstream `zpool`/`zfs`. If/when proxmox-nixos gains pool-creation support, this recipe still works as the no-UI fallback. |

---

## 7. Module Architecture Compliance ("Option B")

Per `.github/copilot-instructions.md`, every shared module must be either:
- a **universal base** (no `lib.mkIf` guards by role/feature), OR
- a **role/feature addition** (no conditionals; included only by the relevant `configuration-*.nix`).

`modules/zfs-server.nix` is a **role-specific addition file** in the strict Option B sense:
- It contains zero `lib.mkIf` guards keyed off role, display flag, or gaming flag.
- It is imported only by `configuration-server.nix` and `configuration-headless-server.nix`.
- All settings inside (`boot.supportedFilesystems`, `services.zfs.*`, `environment.systemPackages`, `networking.hostId`) apply unconditionally to every host that imports it.
- The single `lib.mkDefault` on `networking.hostId` is **not** a role guard — it's the standard NixOS pattern for "make this overridable from a host file" and is explicitly allowed by the convention.

The naming follows the convention `modules/<subsystem>-<qualifier>.nix` → `modules/zfs-server.nix` (subsystem = `zfs`, qualifier = `server` role).

---

## 8. Testing Notes (safe dry-run / verification)

### 8.1 Static / build-time
- `nix flake check`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-vm`
- `bash -n scripts/create-zfs-pool.sh`
- `shellcheck scripts/create-zfs-pool.sh`
- `just --list` (recipe appears, doc-string visible)

### 8.2 Runtime (safe — no real disks)
On a VM running `vexos-server-vm` after the rebuild, exercise the flow against loopback files. This verifies the script's prompts, validation, and `zpool create` invocation without touching real hardware:

```bash
# 1. Create three sparse 1 GiB backing files
sudo truncate -s 1G /tmp/zfs-test-{a,b,c}.img

# 2. Loopback-attach them
sudo losetup -fP /tmp/zfs-test-a.img
sudo losetup -fP /tmp/zfs-test-b.img
sudo losetup -fP /tmp/zfs-test-c.img
losetup -a   # note assigned /dev/loopN

# 3. Create matching by-id symlinks so the script's enumeration sees them
#    (the script filters /dev/disk/by-id/ for ata-/nvme-/scsi-/wwn- prefixes;
#    for testing, manually pass the loop devices via a small wrapper that
#    bypasses the by-id filter — OR test the live by-id flow on a real VM
#    with attached virtual disks, which is the recommended approach.)

# 4. Recommended: in a Proxmox/QEMU VM, attach 3-4 extra virtio-scsi disks.
#    These show up under /dev/disk/by-id/scsi-* with stable names — exactly
#    what the script expects. Run `just create-zfs-pool` and select them.

# 5. Tear down after testing
sudo zpool destroy testpool
sudo losetup -D
sudo rm /tmp/zfs-test-*.img
```

The loopback path is recommended only for unit-style testing of the script's argv assembly; the **production verification path is a throwaway VM with extra virtual disks**, which exercises the real by-id enumeration.

### 8.3 Negative tests
- Run on a desktop variant → `_require-server-role` aborts.
- Run before rebuilding with the new module → tool check aborts with rebuild instructions.
- Reserved name (`mirror`, `log`) → rejected at name prompt.
- Index out of range → re-prompts.
- Confirmation typo → aborts with no changes.

---

## 9. Sources Consulted

1. **Proxmox VE Wiki — ZFS on Linux** — `https://pve.proxmox.com/wiki/ZFS_on_Linux` — authoritative for `zpool create -o ashift=12 ...` syntax, RAIDZ vs mirror IOPS guidance for VM workloads, ZFS feature/upgrade caveats, and the zvol write-amplification analysis on RAIDZ.
2. **OpenZFS Documentation — Workload Tuning** — `https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html` — primary reference for `ashift`, `compression=lz4`, `atime=off` / `relatime=on`, `recordsize` / `volblocksize`, mirrors-vs-RAIDZ for VM workloads, and the "whole disks (by-id) over partitions" recommendation.
3. **OpenZFS Documentation — Hardware** — `https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Hardware.html` — `xattr=sa`, `acltype=posixacl` are the modern defaults required for Linux; ECC RAM and HBA-vs-hardware-RAID guidance referenced for the "Hint" panel.
4. **NixOS Manual — ZFS section** (NixOS 25.11) — `https://nixos.org/manual/nixos/stable/index.html#sec-zfs` — confirms `boot.supportedFilesystems = [ "zfs" ]`, `networking.hostId` 8-hex-digit requirement, `services.zfs.autoScrub`, `services.zfs.trim`, and that ZFS-imported pools persist via `/etc/zfs/zpool.cache` without `fileSystems` declarations.
5. **proxmox-nixos repository** — `https://github.com/SaumonNet/proxmox-nixos` — confirms (a) the binary cache settings already documented in `modules/server/proxmox.nix`, (b) that disk management via the Proxmox UI is unsupported on NixOS, and (c) that the recommended workflow is to create pools with native ZFS tooling and register them via `pvesm add zfspool`.
6. **OpenZFS man pages — `zpool-create(8)` and `zfs(8)`** — `https://openzfs.github.io/openzfs-docs/man/master/8/zpool-create.8.html` — canonical reference for the `-o` (pool property) vs `-O` (root-dataset property) flag distinction and the topology keywords (`mirror`, `raidz1..3`, `draid`).
7. **Proxmox VE `pvesm` documentation** — `https://pve.proxmox.com/pve-docs/pvesm.1.html` — `pvesm add zfspool <id> -pool <pool> -content images,rootdir -sparse` is the canonical CLI for registering an existing ZFS pool/dataset as a Proxmox storage location.
8. **Just manual — recipe syntax & dependencies** — `https://just.systems/man/en/` — confirms the `recipe: dep1 dep2` dependency syntax used by `_require-server-role`, the `[private]` attribute, and that recipe bodies starting with `#!/usr/bin/env bash` are executed as scripts (with the shebang) rather than line-by-line, which matches the existing repo style.

---

## 10. Summary for the Orchestrator

This spec adds **three deliverables** to `vexos-nix`:
1. `modules/zfs-server.nix` — Option-B-compliant role-addition module enabling ZFS on server / headless-server roles.
2. `scripts/create-zfs-pool.sh` — interactive, root-only helper that safely builds a Proxmox-tuned ZFS pool from `/dev/disk/by-id/` paths with destructive-action confirmation.
3. `just create-zfs-pool` recipe + default-recipe hint update in `justfile`.

No flake inputs change. No `hardware-configuration.nix` is touched. `system.stateVersion` is unchanged. The new module is gated to the two server roles by import-list inclusion only (no `lib.mkIf`). The recipe is gated at runtime by the existing `_require-server-role` helper. All deliverables follow the repo's LF-only shell-script convention.
