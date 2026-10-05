# `just zfs-pool` — ZFS pool manager menu (spec)

## Current state
- `just create-zfs-pool` (`[private]` recipe, justfile) runs `scripts/create-zfs-pool.sh`
  (create only). Destroying/editing a pool is done by hand with `zpool` and requires
  remembering to undo two things the create script wires up: the `boot.zfs.extraPools`
  entry in `/etc/nixos/zfs-pools.nix` and the Proxmox `zfspool:` entry in
  `/etc/pve/storage.cfg`.
- `just create-zfs-pool` is also called by the `enable <service>` storage wizard in the
  justfile and referenced in docs/templates.
- `scripts/*.sh` are exposed to deployed hosts via `home.file."scripts/..."` in
  `home-server.nix` / `home-headless-server.nix` (one line per script).
- `_run-storage-script <name>` already locates a script under `scripts/` (walk-up, known
  checkouts, flake-input store path) and runs it with sudo.

## Problem
No single entry point for day-to-day ZFS management, and no safe destroy path that cleans
up the boot-import and Proxmox registrations.

## Proposed solution
1. **`scripts/zfs-pool.sh`** (new) — root-only interactive menu. Each action runs in a
   subshell so an `die` returns to the menu instead of killing the session.
   Menu (plain-language wording, destructive items say so):
   1. Show pools and health — `zpool list/status`, `zfs list -r`
   2. Create a new pool — delegates to sibling `create-zfs-pool.sh` (unchanged)
   3. Destroy a pool — shows layout/datasets, typed pool-name confirmation,
      `zpool destroy` (no `-f`), then `pvesm remove` for Proxmox `zfspool:` storages on
      that pool (or manual hint if Proxmox isn't running), then removes the pool from
      `/etc/nixos/zfs-pools.nix`
   4. Import an existing pool — `zpool import -d /dev/disk/by-id`, optional `-f` after an
      explicit prompt, registers the pool in `/etc/nixos/zfs-pools.nix`
   5. Replace a disk — `zpool replace`
   6. Add disks to a pool — `zpool add` (mirror / raidz1 / raidz2 / single), dry-run
      preview, typed confirmation; real add is NOT forced so ZFS refuses redundancy mismatches
   7. Attach a disk to a mirror — `zpool attach` (also turns a single disk into a mirror)
   8. Detach a disk from a mirror — `zpool detach`
   9. Scrub — start / stop (`zpool scrub [-s]`)
   10. Clear error counters — `zpool clear`
2. **`justfile`**: new `[private] zfs-pool: _require-server-role` recipe →
   `@just _run-storage-script zfs-pool.sh` (same pattern as `create-mergerfs-pool`), plus a
   help line in the server block of `default`. `create-zfs-pool` is kept (wizard + docs use it).
3. **`home-server.nix`, `home-headless-server.nix`**: expose `scripts/zfs-pool.sh` next to
   `create-zfs-pool.sh` (the menu resolves its sibling via the *unresolved* script
   directory, so both must sit in the same directory on every lookup path).

## Design decisions
- Disk picker for replace/add/attach: whole disks by `/dev/disk/by-id`, de-duplicated by
  kernel name (ata-/wwn- aliases); excludes any disk whose device tree has a mountpoint or
  swap (covers `/`, `/boot`, `/nix`) **and** any disk that is a leaf of an imported pool
  (resolved via `zpool status -P`). Disks carrying ZFS labels from a destroyed/exported
  pool stay selectable (tagged) so a just-destroyed pool's disks can be reused.
  (The create script's PROTECTED awk mis-parses rows with an empty MOUNTPOINT, e.g. swap
  partitions — pre-existing, not touched here.)
- Leaf devices for replace/attach/detach come from the config table of `zpool status -P`
  (works for missing disks that appear only as numeric GUIDs).
- Registry file format and markers match what `create-zfs-pool.sh` writes, so both
  scripts interoperate. The writer is duplicated (create script left untouched — surgical
  change). Paths overridable via `ZFS_POOLS_NIX` / `PVE_STOR_CFG` env for testing.
- Option B module rule: shell script + justfile + home-file exposure only; no `lib.mkIf`
  in shared modules; no Nix module changes.

## Dependencies
None new. OpenZFS CLI flags used (`replace`, `attach`, `detach`, `add -n`, `scrub -s`,
`clear`, `import -d`, `status -P`) exist in every OpenZFS the server roles ship. No
Context7 lookup needed (no libraries).

## Out of scope (noted)
Datasets/snapshots, hot spares, log/cache devices, raidz expansion, recovering destroyed pools
(`zpool import -D`), export.

## Risks and mitigations
- Destructive actions: typed pool-name confirmation (destroy/replace/add/attach), no `-f`
  on destroy/add, in-pool and mounted disks never offered.
- Cannot run real ZFS in the dev environment: validate with shellcheck (preflight),
  `bash -n`, and a stub-`zpool`/`lsblk` harness driving the menu and registry/`storage.cfg`
  logic. Real-disk behaviour is NOT exercised and must be tried by the user on spare disks.
- Sibling lookup: script dir vs symlinked home files — mitigated by exposing both scripts.
