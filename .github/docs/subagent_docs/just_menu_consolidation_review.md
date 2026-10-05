# Just menu consolidation — review

Spec: `just_menu_consolidation_spec.md`
Modified: justfile, scripts/zfs-pool.sh (new), scripts/mergerfs-pool.sh (new), scripts/create-zfs-pool.sh
(message text), scripts/{attach,detach}-remote-storage.sh, scripts/create-mergerfs-pool.sh,
scripts/install.sh (comments/messages), home-server.nix, home-headless-server.nix, 20 modules/pkgs/template/
config files (comment/message text only), files/ai/skills/vexos/SKILL.md.

## Findings
- Spec compliance: all requested groups consolidated; attach/detach listed once; create-zfs-pool recipe
  removed; mergerfs menu includes destroy, add/remove disk and SnapRAID actions.
- Public `just --list` dropped from ~60 entries to the grouped set (service/plex-pass/zfs-pool/mergerfs-pool
  are server-only and listed in the server help block, as before).
- No dangling `just <old-name>` references remain in justfile; all 31 `_menu` targets exist.
- mergerfs: `add` formats + mounts a new disk, so it IS destructive to that disk (typed `storage`).
  `remove` is config-only (data stays). Removing a data disk shifts SnapRAID d1..dN names — warned, not solved.
- Pre-existing issues noted, not changed: stale `just enable-ssh` comment in authorized_keys;
  create-zfs-pool.sh's PROTECTED awk and lack of in-pool-disk exclusion; create-mergerfs-pool.sh
  overwrites storage-pool.nix when re-run (the menu now warns first).
- Known external impact: VexPortal recipe catalog (see spec).

## Validation
- `just --list`, `--show` on every target, `--dry-run` for zfs/mergerfs dispatch: OK.
- Real `just` dispatch with a stub `vexos-vpn`: menu (tty), direct action, missing-arg prompt,
  no-tty usage/error, unknown action, chained calls: OK.
- zfs-pool.sh and mergerfs-pool.sh: bash -n, shellcheck -S style clean; stub harnesses cover every action
  (see prior zfs review; mergerfs: status, add content/parity incl. size refusal and member-disk exclusion,
  remove content/parity, last-disk refusal, destroy with/without wipe, sync/scrub guards, create replace
  warning, direct actions).
- `nix-instantiate --parse` on all 27 changed .nix files: OK. `scripts/preflight.sh`: exit 0.
- NOT exercised: real disks/ZFS/mergerfs/SnapRAID; dry-build (needs /etc/nixos/vexos-variant).

## Scores
| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 97% | A |
| Best Practices | 92% | A- |
| Functionality | 90% | A- |
| Code Quality | 92% | A- |
| Security | 94% | A |
| Performance | 98% | A |
| Consistency | 95% | A |
| Build Success | 92% | A- |

**Overall Grade: A- (94%)** — PASS
