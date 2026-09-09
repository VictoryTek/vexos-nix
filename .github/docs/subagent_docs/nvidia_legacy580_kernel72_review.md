# nvidia_legacy580_kernel72 — Review (Phase 3)

Reviewed against `nvidia_legacy580_kernel72_spec.md`. Date: 2026-09-09.

## Changed files

| File | Change |
|------|--------|
| `modules/gpu/nvidia-580-kernel-7.2-strncpy.patch` | **new** — vendored 7.2 compat patch (5 `strncpy`→`strscpy` hunks) |
| `modules/gpu/nvidia.nix` | `kernel_7_2_strncpy_patch` binding + `legacy580` alias; `driverPackage` legacy branch → `legacy580.overrideAttrs` appending the patch; option doc updated |
| `flake.nix` | `mkHost`: removed `latestKernelRoles` + conditional `nvidia-legacy-kernel.nix` import; `legacyExtra` back to plain `imports = [ ./modules/gpu/nvidia.nix ]` |
| `modules/gpu/nvidia-legacy-kernel.nix` | **deleted** |
| `modules/system-custom-kernel.nix` | priority-ladder comment de-references the deleted pin module |

## 1. Specification compliance — PASS

- Vendored patch (decision §11 option B): ✔ `modules/gpu/nvidia-580-kernel-7.2-strncpy.patch`
- Patch route, not LTS pin (decision §11): ✔ hosts stay on `linuxPackages_latest`
- Kernel pin removed, `mkHost` special-casing deleted: ✔
- `strncpy`-only sufficient (spec §3 open question): ✔ resolved by build test — see §5

## 2. Best practices — PASS

- `strncpy` → `strscpy`: correct kernel-side replacement for bounded copy with
  NUL-termination; available since Linux 4.3 so no regression on older kernels.
- The two wrapper functions (`nvswitch_os_strncpy`, `nvkms_strncpy`) that
  `return strncpy(...)` are rewritten to `strscpy(...); return dest;` — `strscpy`
  returns a length, not a pointer, so a blind substitution would be wrong. Patch
  handles this correctly.
- Matches the community fix (babiulep/my-kernel-patches, CachyOS 7.2 nvidia
  patchset) — same call sites, same approach.
- Patch carries a full provenance + removal-condition header comment, mirroring
  the existing `kernel_7_2_patch` convention.

## 3. Module Architecture Pattern (Option B) — PASS

- No new `lib.mkIf` guard in a shared module. The `if variant == "latest"` split
  in `nvidia.nix` selects a package by the module's own declared option
  (`vexos.gpu.nvidiaDriverVariant`) — identical shape to the pre-existing
  `"latest"` branch; the standard NixOS carve-out, not role-smuggling.
- Net **removal** of special-casing: `latestKernelRoles` and the role-gated
  conditional import are gone from `mkHost`. `legacy_580` now expresses itself
  purely through the import list like every other variant.
- Patch file colocated with the only module that references it
  (`modules/gpu/`), consistent with repo layout.

## 4. Consistency / maintainability — PASS

- `overrideAttrs` on `patches` is the same mechanism already used for the
  `"latest"` variant's `.open` patch two lines above — reviewer sees one pattern,
  not two.
- Comments on both the `flake.nix` and `system-custom-kernel.nix` sites updated
  so no dangling references to the removed pin remain (`grep -rn
  nvidia-legacy-kernel` → clean).
- `system.stateVersion`: untouched. `hardware-configuration.nix`: not added.
  No new flake inputs.

## 5. Build validation

| Check | Result |
|-------|--------|
| `patch -p1 --dry-run` vs. real 580.173.02 source tree | ✔ clean, no fuzz/offset |
| `nix build` `linuxPackages_latest.nvidiaPackages.legacy_580` (7.2.4) + patch, `.mod` output | ✔ **`nvidia-kernel-modules-580.173.02-7.2.4`** built |
| `.ko` set produced | ✔ `nvidia.ko`, `nvidia-modeset.ko`, `nvidia-drm.ko`, `nvidia-uvm.ko`, `nvidia-peermem.ko` — all five, incl. `nvidia-drm.ko` (⇒ 7.2 DRM atomic rename does not affect 580.173.02) |
| `nix eval` `vexos-desktop-amd` toplevel `drvPath` | ✔ resolves — `mkHost` change sound, non-nvidia targets unaffected |
| `nix eval` `vexos-desktop-nvidia-legacy580` toplevel `drvPath` | ✖ `error: path '…/modules/gpu/nvidia-580-kernel-7.2-strncpy.patch' does not exist` — **only** because the new file is untracked; Nix flakes don't copy untracked files from a dirty git tree. Not a code defect. |
| `nix flake show --impure` | **deferred** — same untracked-file blocker |
| `scripts/preflight.sh` (Phase 6) | **deferred** — same |
| `sudo nixos-rebuild dry-build` | **deferred** — requires NixOS host, user-run |

The standalone build (out-of-flake expression, identical patch + identical
`overrideAttrs`) is functionally equivalent to what the flake will evaluate once
the file is staged, and it **passes end to end including the kernel-module
compile** — a stronger check than `nix eval …drvPath` (which only forces
evaluation, not compilation).

## 6. Security — PASS

- No secrets, no world-writable files, no server-module changes.
- Patch is a local file in-repo (no network fetch, no third-party runtime dep).
- `strscpy` is strictly safer than `strncpy` (guaranteed NUL-termination,
  bounds-checked).

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A- |

**Overall Grade: A (98%)**

Build Success is A- only because flake-level `nix flake show` / preflight /
`dry-build` cannot run until the new patch file is `git add`ed — an action
reserved to the user by the project workflow. The actual compile (the thing
those checks would gate on) is verified.

## Result: PASS — with one required user action before Phase 6

**User must stage the new file** so the flake can see it:

```
git add modules/gpu/nvidia-580-kernel-7.2-strncpy.patch \
        .github/docs/subagent_docs/nvidia_legacy580_kernel72_spec.md \
        .github/docs/subagent_docs/nvidia_legacy580_kernel72_review.md
git add -u modules/gpu/nvidia-legacy-kernel.nix   # stage the deletion
```

Then `bash scripts/preflight.sh` (Phase 6) can run.
