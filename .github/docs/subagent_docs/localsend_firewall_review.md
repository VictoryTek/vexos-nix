# LocalSend Firewall Fix — Review

## Summary

Implementation matches spec exactly: `modules/network-desktop.nix` gained a single
new section opening TCP+UDP port 53317, scoped to the same four display roles that
already import this file and already install `localsend`.

## Environment Note

`sudo` is unavailable in this sandboxed session ("no new privileges" flag set),
so `sudo nixos-rebuild dry-build` could not be run directly. Substituted with
`nix eval --impure ".#nixosConfigurations.<config>.config.system.build.toplevel.drvPath"`,
which CLAUDE.md documents as the CI-equivalent forced-evaluation check for a single
target. All required targets were evaluated.

## Build Validation

| Command | Result |
|---|---|
| `nix flake show --impure` | ✅ Structure valid, all outputs listed |
| eval vexos-desktop-amd | ✅ Evaluates to a valid drvPath |
| eval vexos-desktop-nvidia | ✅ Evaluates to a valid drvPath |
| eval vexos-desktop-vm | ✅ Evaluates to a valid drvPath |
| eval vexos-stateless-amd | ✅ Evaluates (pre-existing warning: locked user password, unrelated) |
| eval vexos-htpc-amd | ✅ Evaluates to a valid drvPath |
| eval vexos-server-amd | ⚠️ Fails on placeholder `networking.hostId` assertion |
| eval vexos-headless-server-amd | ⚠️ Fails on placeholder `networking.hostId` assertion |

The two `hostId` failures are **pre-existing and unrelated**: `hosts/server-amd.nix`
and `hosts/headless-server-amd.nix` ship shared placeholder hostIds (`a0000001`,
`b0000001`) from commit `b161981` ("fix(zfs): reject shared placeholder hostId"),
which intentionally asserts against exactly this condition until a real per-machine
value is set. This module's change (`network-desktop.nix`) has no relationship to
ZFS or hostId. Confirmed via `git log` and `grep` — no `git stash`/destructive
verification was used (forbidden by project rules).

## Other Checks

- `git ls-files hardware-configuration.nix` → empty (not committed). ✅
- `system.stateVersion` unchanged in all `configuration-*.nix` files (still `25.11`
  everywhere). ✅
- No new flake inputs added — `follows` check N/A. ✅
- No new external dependency — Context7 not required (internal firewall config only). ✅

## Category Scores

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 95% | A (port scoped to LAN/display-roles only, standard LocalSend port) |
| Performance | 100% | A |
| Consistency | 100% | A (matches Option B pattern; no new `lib.mkIf` role gate added) |
| Build Success | 100% | A (all applicable targets evaluate; hostId failures are pre-existing/unrelated) |

**Overall Grade: A (99%)**

## Result: PASS
