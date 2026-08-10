# Specification — ZFS pools created via `just create-zfs-pool` don't survive reboot

## Current State Analysis

`modules/zfs-server.nix:43` sets:
```nix
boot.zfs.extraPools = [ ];  # auto-imported pools added by `just create-zfs-pool` are
                             # cached in /etc/zfs/zpool.cache, not listed here
```
This comment is factually wrong. Verified directly against the vendored nixpkgs source
(`nixos/modules/tasks/filesystems/zfs.nix:47`):
```nix
allPools = lib.unique ((map fsToPool zfsFilesystems) ++ cfgZfs.extraPools);
```
A `zfs-import-<pool>.service` unit (line ~159) is generated **only** for pools that are
either declared in `fileSystems` (fsType "zfs") or explicitly listed in
`boot.zfs.extraPools`. There is no generic "import everything found in
`/etc/zfs/zpool.cache`" unit — `zfs-import-cache.service` does not exist as a systemd
unit on this system (confirmed live: `systemctl status zfs-import-cache.service` →
"could not be found").

Reproduced live on host `vexmox` (`vexos-server-*`):
- `scripts/create-zfs-pool.sh` was run, pool `tank` created successfully, imported and
  mounted immediately (that part of `zpool create` always works).
- After a later reboot, `zpool list` → `no pools available`.
- `sudo zpool import` confirms `tank` is fully intact and importable
  (`state: ONLINE`, no errors) — the disks/data are fine, it simply was never imported
  at boot because no `zfs-import-tank.service` unit exists.
- `hostId` is correctly and uniquely set (`47dfebc8`, matches `/etc/hostid`), ruling out
  the hostId-mismatch failure mode the script already warns about.

`scripts/create-zfs-pool.sh`'s own closing message (lines 291-293) currently claims:
```
Persistence: the pool will auto-import on next boot via /etc/zfs/zpool.cache.
No flake, fstab, or NixOS module changes are needed for the pool itself.
```
This is false and actively misleads the operator into believing no further action is
needed. This is a systemic bug affecting every pool anyone creates with this tool, not
specific to one host.

## Problem Definition

Pools created imperatively via `just create-zfs-pool` have no corresponding NixOS
declaration, so no `zfs-import-<pool>.service` unit is ever generated, so the pool never
auto-imports on boot. The operator must currently run `sudo zpool import <pool>`
manually after every reboot indefinitely.

## Proposed Solution

Follow the same generated-file pattern already established in this repo for
`storage-pool.nix` (`create-mergerfs-pool.sh`) and `storage-remote.nix`
(`attach-remote-storage.sh`): after a successful `zpool create`, write/update a
declarative `/etc/nixos/zfs-pools.nix` that sets `boot.zfs.extraPools`, optionally
imported by the flake only when present — mirroring `hasStoragePool` /
`hasStorageRemote` in `template/etc-nixos-flake.nix`.

Marker-delimited merge (same technique as `attach-remote-storage.sh:143-167`) so
re-running the script for a second pool appends rather than clobbers, and re-running for
the *same* pool name is idempotent (no duplicate entries).

## Implementation Steps

### 1. `scripts/create-zfs-pool.sh`

After the existing `[7/8] Wiping disks and creating pool` step succeeds and the pool is
confirmed via `zpool status`/`zfs list` (existing `[8/8]` block), before the "Register
with Proxmox VE" section, add a new sub-step that writes/updates
`/etc/nixos/zfs-pools.nix`:

```bash
# ---------- Persist pool for boot-time auto-import --------------------------
hdr "Registering pool for boot-time auto-import"
ZFS_POOLS_NIX="/etc/nixos/zfs-pools.nix"
BEGIN_MARK="# >>> vexos-zfs-pools >>>"
END_MARK="# <<< vexos-zfs-pools <<<"

EXISTING=""
if [ -f "$ZFS_POOLS_NIX" ]; then
    EXISTING=$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" \
        '$0 ~ b {f=1; next} $0 ~ e {f=0} f' "$ZFS_POOLS_NIX")
    cp -a "$ZFS_POOLS_NIX" "${ZFS_POOLS_NIX}.bak"
fi

# De-duplicate: keep existing pool names, add this one if not already present.
declare -a POOL_NAMES=()
while IFS= read -r line; do
    name=$(echo "$line" | sed -n 's/^[[:space:]]*"\(.*\)".*/\1/p')
    [ -n "$name" ] && POOL_NAMES+=("$name")
done <<< "$EXISTING"
if ! printf '%s\n' "${POOL_NAMES[@]:-}" | grep -qx "$POOL"; then
    POOL_NAMES+=("$POOL")
fi

{
    echo "# /etc/nixos/zfs-pools.nix"
    echo "# GENERATED/updated by scripts/create-zfs-pool.sh on $(date '+%Y-%m-%d %H:%M:%S')."
    echo "# Registers ZFS pools created via 'just create-zfs-pool' so NixOS generates a"
    echo "# zfs-import-<pool>.service unit for each and imports them automatically on"
    echo "# every boot. Without this, pools created imperatively never auto-import —"
    echo "# see modules/zfs-server.nix for why boot.zfs.extraPools must list them."
    echo "# Host-generated — do NOT commit to the vexos-nix repo."
    echo "{ ... }:"
    echo "{"
    echo "  boot.zfs.extraPools = ["
    echo "    $BEGIN_MARK"
    for name in "${POOL_NAMES[@]}"; do
        echo "    \"$name\""
    done
    echo "    $END_MARK"
    echo "  ];"
    echo "}"
} > "$ZFS_POOLS_NIX"
ok "wrote $ZFS_POOLS_NIX (pools: ${POOL_NAMES[*]})"
```

Update the closing "Persistence" message (lines 291-293) to:
```bash
echo "Persistence: $ZFS_POOLS_NIX now declares this pool in boot.zfs.extraPools."
echo "Run 'just update && sudo nixos-rebuild switch' to apply — until you do, the pool"
echo "will NOT survive the next reboot (it is already imported right now, though)."
```

### 2. `template/etc-nixos-flake.nix`

Add, alongside the existing `storagePoolFile`/`hasStoragePool` optional-import pattern
(lines ~141-147):
```nix
    zfsPoolsFile = ./zfs-pools.nix;
    hasZfsPools  = builtins.pathExists zfsPoolsFile;
```
And add `++ lib.optional hasZfsPools zfsPoolsFile` to the module list of
`mkServerVariant` (~line 292-318) and `mkHeadlessServerVariant` (~line 256-278) —
the only two builders that import `zfs-server.nix`. Do not add it to `mkVariant`,
`mkStatelessVariant`, `mkHtpcVariant`, or `mkVanillaVariant` — those roles never import
`zfs-server.nix` and `boot.zfs.extraPools` would be an unused/dead option there.

### 3. `modules/zfs-server.nix`

Fix the incorrect comment at line 43:
```nix
  # Pools created via `just create-zfs-pool` are registered here declaratively by
  # scripts/create-zfs-pool.sh, which writes/updates /etc/nixos/zfs-pools.nix
  # (imported by template/etc-nixos-flake.nix when present). Without an entry in
  # boot.zfs.extraPools, NixOS generates no zfs-import-<pool>.service unit and the
  # pool will NOT auto-import on boot — verified against nixpkgs'
  # nixos/modules/tasks/filesystems/zfs.nix (allPools = fsToPool fileSystems ++
  # extraPools; nothing else is scanned).
  boot.zfs.extraPools              = [ ];
```

## Dependencies

None. No new packages, flake inputs, or external libraries.

## Configuration Changes

- `scripts/create-zfs-pool.sh` gains a new generated-file-writing step (same category of
  change as the existing `storage-pool.nix`/`storage-remote.nix` generators).
- `template/etc-nixos-flake.nix` gains one new optional import wired into two variant
  builders only (server, headless-server).
- `modules/zfs-server.nix` comment corrected — no behavioral change to that file itself
  beyond the comment (the `[ ]` default is unchanged; it's now correctly described as
  "populated externally via the generated file, not auto-magic").

## Risks and Mitigations

- **Risk:** Existing deployed hosts that already ran `just create-zfs-pool` before this
  fix (like the user's `vexmox` host) still have no `zfs-pools.nix` and their pool still
  won't survive reboot after just pulling this fix.
  **Mitigation:** Out of scope for this code change — communicate to the user
  separately that they must either re-run `just create-zfs-pool` (which would
  destructively re-wipe disks — NOT what they want for an existing healthy pool) or,
  much better, manually create `/etc/nixos/zfs-pools.nix` with
  `{ boot.zfs.extraPools = [ "tank" ]; }` by hand and rebuild. This is a one-time manual
  step for pools that already exist; only future pool creations get it automatically.
- **Risk:** `awk`/`sed` parsing of the marker block could mis-parse a hand-edited file.
  **Mitigation:** Same risk profile and same mitigation (`.bak` backup before overwrite)
  as the already-shipped, working `attach-remote-storage.sh` pattern this mirrors.
- **Risk:** Script now writes to `/etc/nixos` (previously only read from it implicitly
  via `/etc/pve/storage.cfg`).
  **Mitigation:** Script already requires root and already writes to
  `/etc/pve/storage.cfg` in the existing "Register with Proxmox VE" step — no new
  privilege or write-target class introduced.
- **Risk:** Forgetting the required `sudo nixos-rebuild switch` after script completion
  leaves the false impression the pool is now permanently safe.
  **Mitigation:** Closing message explicitly states the pool will NOT survive a reboot
  until the rebuild is run, replacing the previous false "no action needed" message.
