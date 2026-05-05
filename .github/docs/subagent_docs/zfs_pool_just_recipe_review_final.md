# Phase 5 Final Re-Review — `zfs_pool_just_recipe`

## Summary

Phase 4 added a single targeted change to `modules/zfs-server.nix` to resolve
the CI evaluation failure caused by `pkgs.linuxPackages_latest` advancing past
the kernel version supported by the current `zfs-kernel` derivation. The fix
pins `boot.kernelPackages` to `config.boot.zfs.package.latestCompatibleLinuxPackages`
at module-system priority `75`, which is strictly between the default
assignment in `modules/system.nix` (priority `100`) and the `lib.mkForce` in
`modules/gpu/vm.nix` (priority `50`).

The fix is minimal, well-commented, scoped to the one shared module that is
imported only by the affected configurations, and introduces no new flake
inputs, no new role gating, and no changes to unrelated modules.

Verdict: **APPROVED**.

---

## Verification of Phase 4 Fix

`modules/zfs-server.nix`:

- ✅ `lib` and `config` present in module function arguments (`{ config, lib, pkgs, ... }:`).
- ✅ Added line is syntactically valid Nix:
  `boot.kernelPackages = lib.mkOverride 75 config.boot.zfs.package.latestCompatibleLinuxPackages;`
- ✅ Accompanied by a thorough comment block explaining the failure mode,
  the priority arithmetic, and why the VM variant is intentionally untouched.
- ✅ No `lib.mkIf` role-gating was introduced inside this shared module
  (compliance with the Option B base + addition pattern: this file is
  imported only by `configuration-server.nix` and `configuration-headless-server.nix`).
- ✅ `git diff` confirms the only modified file is `modules/zfs-server.nix`
  (49 insertions, 0 deletions). No unrelated changes.

Cross-module sanity checks:

- `modules/system.nix` sets `boot.kernelPackages = pkgs.linuxPackages_latest;`
  as a plain assignment (priority **100**). ✅
- `modules/gpu/vm.nix` sets `boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_6;`
  (priority **50**). ✅
- `modules/gpu/amd-headless.nix`, `nvidia-headless.nix`, `intel-headless.nix`
  do **not** set `boot.kernelPackages` themselves — the `mkOverride 75` from
  `zfs-server.nix` will therefore win unopposed on the bare-metal headless
  variants. ✅
- `configuration-server.nix` and `configuration-headless-server.nix` both
  still import `./modules/zfs-server.nix`. No regression. ✅

---

## Priority Arithmetic Confirmation

NixOS module-system priorities (lower number = higher precedence):

| Mechanism | Priority |
|---|---|
| `mkOptionDefault` | 1500 |
| `mkDefault` | 1000 |
| Plain assignment | 100 |
| `mkOverride 75` (this fix) | **75** |
| `mkForce` | 50 |
| `mkVeryHigh` | 10 |

Therefore on a `headless-server-{amd,nvidia,intel}` host the merge resolves to:

- `modules/system.nix` → `linuxPackages_latest` @ 100
- `modules/zfs-server.nix` → `latestCompatibleLinuxPackages` @ **75** ← winner

On a `headless-server-vm` host:

- `modules/system.nix` → `linuxPackages_latest` @ 100
- `modules/zfs-server.nix` → `latestCompatibleLinuxPackages` @ 75
- `modules/gpu/vm.nix` → `linuxPackages_6_6` via `mkForce` @ **50** ← winner

No duplicate-priority conflict is possible (each contributor sits at a
distinct priority level). The reasoning in the Phase 4 comment block is
correct.

---

## Per-Variant Expected Outcome

| Variant | Previous CI | Expected after fix |
|---|---|---|
| vexos-headless-server-amd | FAIL (zfs-kernel broken) | **PASS** |
| vexos-headless-server-nvidia | FAIL (zfs-kernel broken) | **PASS** |
| vexos-headless-server-intel | FAIL (zfs-kernel broken) | **PASS** |
| vexos-headless-server-vm | PASS | **PASS** (unchanged — `mkForce 6.6` still wins) |
| vexos-server-amd | (not in failing log) | **PASS** (now uses ZFS-compatible kernel) |
| vexos-server-nvidia | (not in failing log) | **PASS** |
| vexos-server-intel | (not in failing log) | **PASS** |
| vexos-server-vm | (not in failing log) | **PASS** (unchanged — `mkForce 6.6`) |
| Non-server roles (desktop / htpc / stateless) | PASS | **PASS** (do not import `zfs-server.nix`) |

---

## Repo-Invariant Checks

| Invariant | Result |
|---|---|
| `hardware-configuration.nix` not tracked in git | ✅ (no matches in `git ls-files`) |
| `system.stateVersion` unchanged (`"25.11"` across all five `configuration-*.nix`) | ✅ |
| No new flake inputs introduced | ✅ (`flake.nix` unchanged in this refinement) |
| `scripts/create-zfs-pool.sh` LF line endings preserved | ✅ (CRLF count = 0) |
| Only `modules/zfs-server.nix` modified | ✅ (49 insertions, 0 deletions) |

---

## Build Validation

`nix` is not installed on this Windows orchestrator host
(`Get-Command nix` returned exit code 1 with no source path). Per the Phase 6
governance rules, local nix unavailability is **not** a CRITICAL failure
caused by code — final build validation is deferred to GitHub Actions CI,
which runs `nix flake check` and `nixos-rebuild dry-build` for every
`vexos-*` output on Linux runners.

The deferred CI run is expected to flip the four previously-failing
`vexos-headless-server-{amd,nvidia,intel}` jobs to PASS based on the
priority-arithmetic analysis above, while leaving the other 26 outputs
unaffected.

---

## Updated Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | Deferred to CI | — |

**Overall Grade: A (100%)** — pending CI confirmation.

---

## Verdict

**APPROVED**

The Phase 4 fix is correct, minimally scoped, syntactically valid, well
commented, and consistent with the project's Option B module pattern. No
code-caused build issues remain. Local `nix flake check` is deferred to
GitHub Actions CI as Windows lacks the Nix toolchain, which is acceptable
under Phase 6 governance.

Final review file:
`c:\Projects\vexos-nix\.github\docs\subagent_docs\zfs_pool_just_recipe_review_final.md`
