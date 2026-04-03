# Spec: VirtualBox Guest Additions Kernel Compatibility Fix

**Feature Name:** `vbox_kernel_fix`
**Date:** 2026-04-03
**Status:** Proposed

---

## 1. Current State Analysis

### Files Involved

| File | Role |
|------|------|
| `flake.nix` | Defines three NixOS outputs; uses `nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"` |
| `hosts/vm.nix` | VM-specific host config; imports `configuration.nix` + `modules/gpu/vm.nix` |
| `modules/gpu/vm.nix` | VM guest stack: QEMU agent, SPICE, VirtualBox guest additions, virtio/QXL modules |
| `configuration.nix` | Shared base; sets `system.stateVersion = "25.11"`; no kernel pin |
| `modules/virtualization.nix` | Host-side libvirtd / KVM / virt-manager; no VM guest kernel config |

### Current Kernel

No `boot.kernelPackages` is set anywhere in the repository. NixOS 25.11 defaults to its
bundled kernel, which is **Linux 6.19.x** at the time this build is failing. That kernel
removed the DRM helper API that VirtualBox Guest Additions 7.2.4 depends on.

### VirtualBox Guest Additions Version

`virtualisation.virtualbox.guest.enable = true` in `modules/gpu/vm.nix` pulls in the
VirtualBox Guest Additions version bundled with nixpkgs 25.11 — **7.2.4** at the time of
this failure.

---

## 2. Problem Definition

### Build Error

```
vbox_fb.c: In function 'vboxfb_create':
vbox_fb.c:334:16: warning: implicit declaration of function 'drm_fb_helper_alloc_info';
  did you mean 'drm_fb_helper_fill_info'? [-Wimplicit-function-declaration]
vbox_fb.c:334:14: error: assignment to 'struct fb_info *' from 'int' makes pointer from
  integer without a cast [-Wint-conversion]
```

### Root Cause

`drm_fb_helper_alloc_info()` was removed from the Linux DRM subsystem API in the Linux 6.19
development cycle as part of the ongoing `fbdev → DRM` migration cleanup. VirtualBox Guest
Additions 7.2.4 has not yet been updated to use the replacement API
(`drm_fb_helper_fill_info()` or the newer `drm_client_framebuffer_create()` path).

This is an **out-of-tree kernel module build failure** — the vboxvideo driver's source code
references a symbol that no longer exists in the kernel headers at 6.19.

### Scope

- **Affected output:** `vexos-vm` only.
- **Unaffected outputs:** `vexos-amd`, `vexos-nvidia`, `vexos-intel` — AMD and NVIDIA hosts
  do not enable VirtualBox Guest Additions and are pinned separately by their own GPU modules
  (which do not set `boot.kernelPackages`), so they would inherit whatever default kernel
  nixpkgs 25.11 ships and are unaffected by this fix.

---

## 3. Research Findings

### LTS Kernels Available in nixpkgs 25.11

| Attribute | Kernel | LTS EOL | VBox 7.2.4 Compatible | Notes |
|-----------|--------|---------|----------------------|-------|
| `pkgs.linuxPackages_6_6` | 6.6.x | Dec 2026 | ✅ Yes | Stable, proven VBox track record |
| `pkgs.linuxPackages_6_12` | 6.12.x | Dec 2027 | ✅ Yes | Latest LTS; `drm_fb_helper_alloc_info` still present |
| `pkgs.linuxPackages_6_1` | 6.1.x | Dec 2026 | ✅ Yes | Older LTS; works but unnecessarily old |
| `pkgs.linuxPackages` (default) | 6.19.x | — | ❌ No | Removed `drm_fb_helper_alloc_info` |

**Selected kernel:** `pkgs.linuxPackages_6_6`

Rationale:
- Linux 6.6 is a well-established LTS kernel with proven VirtualBox Guest Additions
  compatibility across the entire 7.x release train.
- It pre-dates the DRM API changes that first appeared in 6.9+ and were completed in 6.19.
- It is actively maintained until December 2026 and is explicitly available as
  `pkgs.linuxPackages_6_6` in nixpkgs 25.11.
- More conservative than 6.12 while still fully security-maintained.

### Does `virtualisation.virtualbox.guest.enable` Auto-Handle Compatibility?

No. The NixOS option builds the VirtualBox kernel modules (vboxguest, vboxsf, vboxvideo)
against the **currently configured kernel** at evaluation time. There is no automatic
fallback to a compatible kernel — if the module source is incompatible with the kernel
version, the build fails as observed.

### Does nixpkgs 25.11 Have a Patched VirtualBox for 6.19?

As of the date of this spec (2026-04-03), no nixpkgs patch for VBoxGuest adapting to the
6.19 DRM API removal has been verified or confirmed merged. Even if such a patch lands later,
pinning to an LTS kernel is the safer, more stable approach for a VM guest configuration
that does not need cutting-edge kernel features.

### Per-Host vs Global Kernel Pin

- **Global pin** (in `configuration.nix`): would affect AMD, NVIDIA, and Intel hosts
  unnecessarily — those machines benefit from the newer default kernel.
- **Per-host pin** (in `hosts/vm.nix` or `modules/gpu/vm.nix`): scoped to VM output only.
  This is the correct NixOS pattern — use `boot.kernelPackages` inside the host-specific
  module or the guest-stack module.

**Decision:** Pin in `modules/gpu/vm.nix`, alongside the existing VirtualBox guest additions
declaration. This co-locates the kernel requirement with the module that creates it.

---

## 4. Proposed Solution

### Exact Change

**File:** `modules/gpu/vm.nix`

**Change 1:** Add `pkgs` to the module function arguments (currently only `config` and `lib`
are destructured; `pkgs` is required to reference `pkgs.linuxPackages_6_6`).

**Change 2:** Add `boot.kernelPackages = pkgs.linuxPackages_6_6;` inside the module body.

#### Before

```nix
{ config, lib, ... }:
{
  # QEMU/KVM guest agent — graceful shutdown, memory ballooning, clock sync, file copy
  services.qemuGuest.enable = true;
  ...
```

#### After

```nix
{ config, lib, pkgs, ... }:
{
  # Pin to Linux 6.6 LTS: VirtualBox Guest Additions 7.2.4 cannot build against
  # kernel 6.19+ (drm_fb_helper_alloc_info was removed). 6.6 LTS is maintained
  # until Dec 2026 and is the last LTS series proven compatible with VBox 7.2.x.
  boot.kernelPackages = pkgs.linuxPackages_6_6;

  # QEMU/KVM guest agent — graceful shutdown, memory ballooning, clock sync, file copy
  services.qemuGuest.enable = true;
  ...
```

### No Other Files Modified

- `flake.nix` — no change (no new inputs needed)
- `hosts/vm.nix` — no change
- `configuration.nix` — no change (`system.stateVersion` untouched)
- `modules/virtualization.nix` — no change (this is the host-side KVM stack)
- `hosts/amd.nix`, `hosts/nvidia.nix`, `hosts/intel.nix` — no change

---

## 5. Implementation Steps

1. Open `modules/gpu/vm.nix`.
2. Change the first line from `{ config, lib, ... }:` to `{ config, lib, pkgs, ... }:`.
3. As the **first attribute** inside the `{...}` block body (before `services.qemuGuest`),
   add:
   ```nix
   # Pin to Linux 6.6 LTS: VirtualBox Guest Additions 7.2.4 cannot build against
   # kernel 6.19+ (drm_fb_helper_alloc_info was removed). 6.6 LTS is maintained
   # until Dec 2026 and is the last LTS series proven compatible with VBox 7.2.x.
   boot.kernelPackages = pkgs.linuxPackages_6_6;
   ```
4. Save the file.
5. Verify with `nix flake check`.
6. Verify with `sudo nixos-rebuild dry-build --flake .#vexos-vm`.
7. Confirm `vexos-amd`, `vexos-nvidia`, and `vexos-intel` dry-builds still pass (kernel
   unchanged for those outputs).

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `linuxPackages_6_6` not in nixpkgs 25.11 | Very Low | 6.6 LTS has been in nixpkgs since 24.05; it will be present in 25.11. Fallback: use `pkgs.linuxPackages_6_12`. |
| 6.6 kernel missing feature needed by another VM module | Very Low | VM module only uses `virtio_gpu`, `qxl`, QEMU agent, SPICE, VBox additions — all of which predate and work on 6.6. |
| Future VBox upgrade still broken on 6.6 | Unlikely | VBox 7.3+ is expected to address 6.19 compatibility; when that lands in nixpkgs, the pin can be removed or updated to 6.12. |
| AMD/NVIDIA host regressions | None | Fix is strictly scoped to `modules/gpu/vm.nix`, which is only imported by `hosts/vm.nix`. |
| `system.stateVersion` change | None (Non-issue) | `system.stateVersion = "25.11"` stays in `configuration.nix`, untouched. |
| New flake input required | None (Non-issue) | `pkgs.linuxPackages_6_6` is already in nixpkgs 25.11; no new input needed. |

---

## 7. Alternatives Considered

| Alternative | Verdict |
|-------------|---------|
| Pin to `pkgs.linuxPackages_6_12` | Valid fallback. 6.12 LTS (EOL Dec 2027) also works with VBox 7.2.4 and has newer security fixes. Slightly higher risk than 6.6 but still safe. Can substitute if 6.6 is ever removed. |
| Wait for patched VBox in nixpkgs | Unreliable timeline; no confirmed landing date. Not actionable as a fix today. |
| Disable VirtualBox guest additions | Breaks shared folders, clipboard, auto-resize for VirtualBox users. Not acceptable. |
| Apply a Nix overlay to patch VBox source | High complexity, fragile, hard to maintain. Out of scope for this targeted fix. |
| Move kernel pin to `hosts/vm.nix` | Also valid. Marginally less cohesive than `modules/gpu/vm.nix` since the kernel requirement is caused by the VBox additions declaration that lives in that module. |

---

## 8. Summary

**Root cause:** nixpkgs 25.11 defaults to Linux 6.19.x, which removed `drm_fb_helper_alloc_info()` from
the DRM API. VirtualBox Guest Additions 7.2.4 calls that function during its kernel module
build, causing a hard compile error only for the `vexos-vm` output.

**Fix:** Add one line to `modules/gpu/vm.nix`:

```nix
boot.kernelPackages = pkgs.linuxPackages_6_6;
```

This pins the VM guest to Linux 6.6 LTS, which is fully compatible with VBox 7.2.4 and is
maintained until December 2026. AMD, NVIDIA, and Intel host outputs are completely unaffected.
