# `just zfs-pool` menu — review

Spec: `zfs_pool_menu_spec.md`
Modified/new: `scripts/zfs-pool.sh` (new), `justfile`, `home-server.nix`, `home-headless-server.nix`

## Findings
- Spec compliance: all 10 menu actions implemented; `create-zfs-pool.sh` untouched and
  launched as the "Create" action; recipe + help line + home-file exposure added.
- Safety: destroy/replace/add/attach require typing the pool name; destroy and add never
  pass `-f` to the real command; disks that are mounted (incl. `/`, `/boot`, `/nix`, swap)
  or already in an imported pool are never offered; ata-/wwn- aliases de-duplicated.
- Interop: registry file uses the same marker block as `create-zfs-pool.sh`.
- Option B / Nix: no module changes; only shell, justfile and home-file lines.
- Not changed (pre-existing, noted): create-zfs-pool.sh's PROTECTED awk mis-parses rows
  with an empty MOUNTPOINT (e.g. swap partitions) and its create path does not exclude
  disks that are in an imported pool.
- Known limits: no datasets/snapshots/spares/log/cache/export/`import -D`; `zpool add -n -f`
  preview forces past label checks (the real add does not force).

## Validation
- `bash -n`, shellcheck `-S style`: clean. LF endings.
- `just --show zfs-pool` and dry-run of `_run-storage-script zfs-pool.sh`: parse OK.
- Stub harness (fake zpool/zfs/lsblk/sgdisk/wipefs/pvesm + fake /dev/disk/by-id, run as root
  in WSL): status, scrub, clear, detach, replace, add (mirror; single), attach, import
  (normal, forced y/n), destroy (wrong name aborts; correct name destroys, removes only the
  matching Proxmox storage, unregisters only that pool, writes .bak). Recorded commands
  matched expectations.
- `scripts/preflight.sh`: exit 0, "Preflight PASSED".
- NOT exercised: real ZFS on real disks (no ZFS/spare disks in the dev environment).
  Try it first on spare disks.

## Scores
| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 94% | A |
| Functionality | 90% | A- |
| Code Quality | 93% | A |
| Security | 95% | A |
| Performance | 100% | A |
| Consistency | 95% | A |
| Build Success | 95% | A |

**Overall Grade: A (95%)** — PASS
