# ZFS pool topology menu — plain-language wording (review)

Spec: `zfs_pool_topology_plain_language_spec.md`
Modified: `scripts/create-zfs-pool.sh` (step [3/8] menu + hint echo lines only)

## Findings
- Spec compliance: only echo text changed. Option numbers, `TOPO`/`MIN_DISKS` values,
  the `case` mapping and all later logic are untouched (diff is 29+/8- lines, all in the menu).
- Accuracy vs. code: option 1 is described as what the code does (disks added together,
  no protection); option 6 now says "even number only", matching the check at
  the disk-selection step. Capacity/failure figures match standard OpenZFS semantics.
- Menu rendered locally: reads cleanly, max line width 84 columns.
- Security / Option B module pattern: not applicable (shell script text only).
- Line endings: LF, no CR bytes.

## Validation
- `bash -n scripts/create-zfs-pool.sh` (WSL): OK
- `scripts/preflight.sh` (WSL, Nix 2.34.1): exit 0, "Preflight PASSED".
  Includes `nix flake show`, shellcheck -S warning on scripts/*.sh, gitleaks, stateVersion
  and hardware-configuration checks.
- Not exercised: dry-build stage was skipped by preflight (WSL has no
  `/etc/nixos/vexos-variant`); irrelevant to this change, which touches no Nix evaluation.
- Not exercised: an actual interactive run creating a pool (destructive; requires real disks).

## Notes (not changed, out of scope)
- Option 1 still permits selecting multiple disks (stripe). Enforcing exactly one disk
  would be a behaviour change; the label now describes the real behaviour instead.

## Scores
| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 95% | A |
| Build Success | 95% | A |

**Overall Grade: A (97%)** — PASS
