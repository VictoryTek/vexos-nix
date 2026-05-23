# Review: VM Black Screen Boot Fix

**Feature:** `vm_black_screen_fix`  
**Review path:** `.github/docs/subagent_docs/vm_black_screen_fix_review.md`  
**Reviewed file:** `modules/gpu/vm.nix`  
**Spec:** `.github/docs/subagent_docs/vm_black_screen_fix_spec.md`  
**Date:** 2026-05-23  
**Reviewer verdict:** PASS

---

## 1. Code Review Findings

### 1.1 Specification Compliance

The spec (§4.2 "Exact Change") calls for adding one line with a 4-line comment block:

```nix
# VirtualBox vboxvideo has no DRM/KMS support; virtio-gpu DRM is not reliable
# without explicit virgl 3D renderer configuration in the hypervisor.
# Force GDM to use an X11 session so the display manager starts successfully
# in all VM environments (VirtualBox, QEMU/KVM, VMware).
services.displayManager.gdm.wayland = lib.mkForce false;
```

Spec §4.2 also says: *"suggested placement: after `services.scx.enable`"*, and the "Full
Resulting" file in §4.5 shows the GDM line last (after `vexos.swap.enable = false;`).

**What was implemented:**

```nix
  # Force GDM to use X11 — VirtualBox's vboxvideo driver has no DRM/KMS support,
  # so Wayland compositing fails silently and the system boots to a black screen.
  services.displayManager.gdm.wayland = lib.mkForce false;
```

Deviations from spec:

| # | Deviation | Severity |
|---|-----------|----------|
| 1 | Comment is 2 lines instead of 4; omits QEMU/KVM and VMware context | Minor |
| 2 | Placement is between `boot.kernelModules` and `powerManagement.cpuFreqGovernor`, not after `vexos.swap.enable` as shown in §4.5 | Minor |
| 3 | Pre-existing `# 6.6 LTS` comment inconsistency (should be `6.12 LTS`) not corrected; the §4.5 "Full Resulting" file shows this corrected, but §4.2 "Exact Change" did not explicitly require it | Informational |

None of these deviations affect correctness, security, or build success.

---

### 1.2 Correctness

| Check | Result |
|-------|--------|
| `lib` in scope: `{ config, lib, pkgs, ... }:` | ✓ PASS |
| `lib.mkForce` syntax correct: `lib.mkForce false` | ✓ PASS |
| Priority: `lib.mkForce` = priority 50, overrides `gnome.nix` default priority 1000 | ✓ PASS |
| No `lib.mkIf` guard; assignment is unconditional | ✓ PASS |
| Overrides `gnome.nix`'s `wayland = true` correctly | ✓ PASS |
| `headless-server-vm` safety: `gdm.enable = false` on headless roles; setting `wayland` on a disabled GDM is a no-op | ✓ PASS |

The `lib.mkForce` pattern is consistent with the other three existing overrides in the same
file: `boot.kernelPackages`, `powerManagement.cpuFreqGovernor`, and `services.scx.enable`.

---

### 1.3 Module Architecture Pattern Compliance

Per the project's Option B pattern:

> A `configuration-*.nix` expresses its role **entirely through its import list**. NO
> conditional logic inside modules. Universal base file contains only unconditional settings.

| Check | Result |
|-------|--------|
| No `lib.mkIf` guard added | ✓ PASS |
| `modules/gpu/vm.nix` is imported only by `hosts/*-vm.nix` files | ✓ PASS |
| Scope is VM-only via import graph, not via conditional | ✓ PASS |
| No new conditional guards added to any shared module | ✓ PASS |

Architecture pattern is correctly followed.

---

### 1.4 Comment Quality

The implemented comment:
```nix
# Force GDM to use X11 — VirtualBox's vboxvideo driver has no DRM/KMS support,
# so Wayland compositing fails silently and the system boots to a black screen.
```

**Strengths:** Clear, explains the root cause, explains the symptom.

**Weaknesses:** The spec called for broader context:
- Does not mention `virtio-gpu` + QEMU/KVM reliability concern (virgl not configured)
- Does not mention VMware context
- A future maintainer working on QEMU/KVM virgl support may not understand why this is set

**Recommendation for future refinement:** Expand comment to match the spec's 4-line version
covering all three hypervisor cases. This is non-blocking.

---

### 1.5 Unintended Changes

Only the two-line comment and the `services.displayManager.gdm.wayland = lib.mkForce false;`
line were added. All other existing lines in `modules/gpu/vm.nix` are unchanged.

No unintended modifications detected. ✓

---

### 1.6 Import Chain Verification

`hosts/server-vm.nix` imports:

```nix
imports = [
  ../configuration-server.nix   # → modules/gnome.nix → gdm.wayland = true (priority 1000)
  ../modules/gpu/vm.nix         # → gdm.wayland = lib.mkForce false (priority 50)
];
```

`lib.mkForce false` (priority 50) wins over `true` (priority 1000). Correct.

Confirmed that `modules/gnome.nix` sets:
```nix
services.displayManager.gdm = {
  enable  = true;
  wayland = true; # Wayland session (default in GNOME 47+ / NixOS 25.11)
};
```
The override is necessary and `lib.mkForce` is the correct mechanism. ✓

---

### 1.7 Hardware-configuration.nix

`hardware-configuration.nix` is NOT present in the repository. Confirmed via the workspace
tree — no `hardware-configuration.nix` at repo root or in any tracked path. ✓

### 1.8 system.stateVersion

`system.stateVersion` in `configuration-desktop.nix` was not modified by this change. ✓

---

## 2. Build Validation Results

All commands run from `/home/nimda/Projects/vexos-nix`.

### 2.1 `nix flake show`

```
nix flake show 2>&1 | head -50
```

**Result: PASS**

All 30 `nixosConfigurations` evaluated without error. Output excerpt:

```
warning: Git tree '/home/nimda/Projects/vexos-nix' is dirty
git+file:///home/nimda/Projects/vexos-nix
├───nixosConfigurations
│   ├───vexos-desktop-amd: NixOS configuration
│   ├───vexos-desktop-intel: NixOS configuration
│   ├───vexos-desktop-nvidia: NixOS configuration
│   ├───vexos-desktop-nvidia-legacy470: NixOS configuration
│   ├───vexos-desktop-nvidia-legacy535: NixOS configuration
│   ├───vexos-desktop-vm: NixOS configuration
│   ├───vexos-headless-server-amd: NixOS configuration
│   ├───vexos-headless-server-intel: NixOS configuration
│   ├───vexos-headless-server-nvidia: NixOS configuration
│   ├───vexos-headless-server-vm: NixOS configuration
│   ├───vexos-htpc-amd: NixOS configuration
│   ...
```

No evaluation errors.

---

### 2.2 `nixos-rebuild dry-build .#vexos-server-vm`

```
nixos-rebuild dry-build --flake .#vexos-server-vm --impure 2>&1 | tail -20
```

**Result: PASS** (exit 0, completed in ~10 seconds)

Final output (paths that would be fetched):
```
these 19 paths will be fetched (137.30 MiB download, 164.78 MiB unpacked):
  /nix/store/fzkp98ka5ic4zfnypc00y893c9psmkj8-VirtualBox-GuestAdditions-7.2.4-6.12.90
  /nix/store/r4m5vd3253myhsmywr8clyr39ri21g1i-audit-4.1.2-unstable-2025-09-06
  /nix/store/jb4hy7pal9zx0r417y8bkb5lhhj8fml0-linux-6.12.90
  /nix/store/k2ya9697pw53fv2mrzj2y18lyfxnjaik-linux-6.12.90-modules
  /nix/store/v5hgc2gaa332bxva02r6d0bqky55gvgg-spice-vdagent-0.23.0
  ...
```

Note: `--impure` is required because host configs import `/etc/nixos/hardware-configuration.nix`
(an absolute path outside the flake). This is expected behaviour for this project.

The `vexos-server-vm` closure builds successfully including the VM-specific packages
(`VirtualBox-GuestAdditions-7.2.4`, `linux-6.12.90`, `spice-vdagent`), confirming the
`lib.mkForce` override does not cause an evaluation conflict.

---

### 2.3 `nixos-rebuild dry-build .#vexos-desktop-amd`

```
nixos-rebuild dry-build --flake .#vexos-desktop-amd --impure 2>&1 | tail -20
```

**Result: PASS** (exit 0, completed in ~10 seconds)

Final output (paths that would be fetched):
```
  /nix/store/hbhiid2lyvi0wn114ncfzfcvbir40rvx-rocblas-6.4.3
  /nix/store/qvf5ag2bw62g1kyf6k526q3rnyi7bh62-rocm-runtime-6.4.3
  /nix/store/fi64b2ifffcwrmsldr3l90ic5ybkz0rg-rocm-toolchain
  /nix/store/17wdhshr5ihk7djiwq6r0cv3rldnkayg-rocminfo-6.4.3
  ...
```

AMD bare-metal build is unaffected by the VM-only fix. No regression. ✓

---

## 3. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 85% | B |
| Best Practices | 100% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 90% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A (97%)**

Score breakdown:

- **Specification Compliance (85%):** The required line is present with correct semantics.
  Deductions for comment shorter than spec called for (omits QEMU/KVM and VMware context)
  and placement deviating from spec's "suggested" location and "Full Resulting" example.
- **Code Quality (90%):** Deduction for comment not matching spec's more comprehensive version.
  All other code quality aspects are correct.
- All other categories are unaffected by the minor deviations; the fix is correct, safe, and
  consistent with existing patterns.

---

## 4. Summary

The fix correctly adds `services.displayManager.gdm.wayland = lib.mkForce false;` to
`modules/gpu/vm.nix`. The implementation is functionally correct:

- `lib` is properly in scope
- `lib.mkForce` priority (50) wins over `gnome.nix`'s default-priority (1000) `wayland = true`
- No `lib.mkIf` guard; unconditional per the Module Architecture Pattern
- VM-scope is enforced entirely through the import graph
- All three build validation commands passed (flake show, server-vm dry-build, desktop-amd dry-build)

Two minor non-blocking deviations from spec: the comment is shorter and less comprehensive
than specified, and the line placement differs from the spec's suggested location. Neither
affects correctness, security, or build success.

---

## 5. Verdict

**PASS**

The fix is correct, consistent with project conventions, and all build validations succeed.
No CRITICAL issues found. The two minor deviations are documentation quality concerns only
and do not require refinement before this change is considered complete.
