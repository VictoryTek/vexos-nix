# NVIDIA on kernel 7.2 — Phase 3 Review

Spec: `nvidia_kernel72_compat_spec.md`
Commit under review: `2b59999` — *feat(gpu): build NVIDIA on 7.2, pin legacy_580 hosts to 7.1*

## Files changed

- `flake.nix`
- `modules/gpu/nvidia.nix`
- `modules/gpu/nvidia-legacy-kernel.nix` (new)
- `modules/system-custom-kernel.nix`
- `template/etc-nixos-flake.nix`
- `.github/docs/subagent_docs/nvidia_kernel72_compat_spec.md` (new)
- `.github/docs/subagent_docs/nvidia_kernel71_pin_spec.md` (new, superseded)

## Resolved variant matrix (verified by `nix eval`)

| output | kernel | driver | open |
|---|---|---|---|
| `vexos-desktop-nvidia` | **7.2** | 595.71.05 | true |
| `vexos-desktop-nvidia-legacy580` | **7.1.10** | 580.173.02 | false |
| `vexos-stateless-nvidia-legacy580` | **7.1.10** | 580.173.02 | false |
| `vexos-server-nvidia` | 6.18.46 | 595.71.05 | true |
| `vexos-server-nvidia-legacy580` | 6.18.46 | 580.173.02 | false |
| `vexos-htpc-nvidia-legacy580` | 6.12.105 | 580.173.02 | false |
| `vexos-desktop-amd` | 7.2 | — | — |
| `vexos-desktop-vm` | 6.18.46 | — | — |

The 7.1 pin lands **only** on the two latest-kernel-role legacy_580 variants, as
designed. Server/htpc legacy_580 keep their role kernel (6.18 via the ZFS pin,
6.12 for htpc). Non-NVIDIA desktop variants are untouched.

Driver builds verified against every kernel that now pairs with it:
580.173.02 on 6.12 ✅, 6.18 ✅, 7.1 ✅ (and confirmed failing on 7.2, which is
why the pin exists). 595.71.05 + CachyOS patch on 6.12 ✅ and 7.2 ✅.

## Build validation

| check | result |
|---|---|
| `nix flake show --impure` | ✅ exit 0, 30 outputs, all 6 `legacy580` present, no `legacy535` |
| dry-build `vexos-desktop-amd` | ✅ |
| dry-build `vexos-desktop-nvidia` | ✅ |
| dry-build `vexos-desktop-vm` | ✅ |
| dry-build `vexos-desktop-nvidia-legacy580` | ✅ |
| dry-build `vexos-stateless-amd` | ✅ |
| dry-build `vexos-htpc-amd` | ✅ |
| dry-build `vexos-server-amd` | ⚠️ pre-existing failure — see below |
| dry-build `vexos-headless-server-amd` | ⚠️ pre-existing failure — see below |
| **real build** of `config.hardware.nvidia.package.open` for `vexos-desktop-nvidia` | ✅ `/nix/store/bmc8rh8my9p7vgkaamjw9fi5qrqg4vr4-nvidia-open-595.71.05-7.2` |
| `hardware-configuration.nix` tracked? | ✅ not tracked |
| `system.stateVersion` changed? | ✅ unchanged; present ("25.11") in all 6 `configuration-*.nix` |
| new flake inputs? | ✅ none added |
| `scripts/preflight.sh` | ✅ **exit 0 — Preflight PASSED** |

### Pre-existing server dry-build failure (not a regression)

`vexos-server-amd` and `vexos-headless-server-amd` fail a ZFS assertion:

> ZFS requires a unique networking.hostId per host — this is still a shared
> placeholder committed in hosts/<role>-<gpu>.nix

Confirmed pre-existing by re-running the same dry-build against `HEAD~1`, which
produces the identical assertion. This commit touches **no** files under
`hosts/`. It is a deliberate guard requiring per-machine configuration on ZFS
server roles, unrelated to NVIDIA. Out of scope; not addressed here.

## Review criteria

| criterion | finding |
|---|---|
| **Specification compliance** | Matches the spec exactly. Part A (CachyOS patch, stay on 7.2) and Part B1 (legacy_580 + 7.1 pin) both implemented as specified; B2 was not attempted per the user's decision. |
| **Best practices** | `fetchpatch` pinned to a commit SHA + hash, not a branch — reproducible. Mirrors nixpkgs' own vendoring of CachyOS patches. Comment explains why `.override { patchesOpen = …; }` cannot be used (consumed by generic.nix before `callPackage`). |
| **Consistency (Option B)** | Compliant. `nvidia-legacy-kernel.nix` is a feature-addition module with no internal conditional logic, imported only where it applies. The role/variant condition lives in `flake.nix`'s `mkHost`, which is already the file that composes by role. No new `lib.mkIf` guards in shared modules. |
| **Maintainability** | Both new/changed modules carry explicit removal triggers. The `boot.kernelPackages` priority ladder in `system-custom-kernel.nix` was updated with the new rung (95), keeping that comment the single source of truth. |
| **Completeness** | All 6 `legacy535` outputs renamed across `flake.nix` and the installer template; no stale references remain except one deliberate historical note in `nvidia.nix`. |
| **Performance** | The patched driver is not on `cache.nixos.org`, so NVIDIA hosts compile it locally (~minutes) per driver/kernel bump. Accepted tradeoff, documented in the spec. Net improvement: today the same hosts attempt a local build that *fails*. |
| **Security** | No secrets, no world-writable files, no credential assignments. The patch is hash-pinned, so its content cannot change underneath the build. |
| **API currency** | Driver/kernel pairings verified empirically by building, not inferred. |

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 90% | A- |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (97%)**

## Result: PASS

No CRITICAL or RECOMMENDED issues. No refinement cycle required.

## Follow-ups noted, deliberately out of scope

1. **CI cannot catch this class of bug.** `.github/workflows/ci.yml:202` runs
   `nix eval …toplevel.drvPath`, which evaluates without compiling. That is why
   `legacy_535` sat broken and green for months. Building the NVIDIA kernel
   module for at least one variant in CI would close the gap.
2. **Pre-existing ZFS `networking.hostId` placeholder** blocks server-role
   dry-builds (above).
3. **Repo-wide `nixpkgs-fmt` drift** — 99 of 191 files would be reformatted.
   All three reformattable files in this commit were already non-conforming at
   `HEAD~1` (verified individually); the new module is clean. Not addressed, as
   reformatting is unrelated churn.
