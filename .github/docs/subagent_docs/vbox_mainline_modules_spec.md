# Specification: Use Mainline VirtualBox Guest Kernel Modules

## Feature Name
`vbox_mainline_modules`

## Date
2026-08-17

---

## 1. Current State Analysis

`modules/gpu/vm.nix` and `modules/gpu/vanilla-vm.nix` both:

1. Pin `boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;` — justified solely by
   the comment "VirtualBox Guest Additions 7.2.4 is incompatible with Linux 6.19+
   (drm_fb_helper_alloc_info was removed)".
2. Unconditionally enable `virtualisation.virtualbox.guest.enable = true;` for every
   `gpu = "vm"` host across all six roles (desktop, stateless, server, headless-server,
   htpc, vanilla) regardless of which hypervisor actually runs the guest.

`virtualisation.virtualbox.guest.enable` defaults `use3rdPartyModules = true`, which
builds VirtualBox's own out-of-tree `vboxguest`/`vboxsf`/`vboxvideo` kernel modules
against the active `boot.kernelPackages`. The `vboxvideo` module fails to compile on
current kernels because `drm_fb_helper_alloc_info` (used by VirtualBox's DRM helper
code) was removed upstream — confirmed by a live build failure on `vexos-server-vm`
(a Proxmox/QEMU-KVM guest, not real VirtualBox).

## 2. Problem Definition

- The kernel pin is a workaround for an out-of-tree module compile failure, not a real
  version requirement — it blocks the VM roles from tracking `linuxPackages_latest`
  like every other role.
- `vexos-server-vm` doesn't run under real VirtualBox at all (it's Proxmox/QEMU-KVM),
  yet it still builds the full VirtualBox out-of-tree module stack and fails.
- The user's actual requirement: the same `gpu = "vm"` output must work unmodified on
  both real VirtualBox hosts (Windows) and QEMU/KVM/Proxmox hosts (Linux), without a
  per-host branch or install-time prompt.

## 3. Proposed Solution

Linux has shipped in-tree `vboxguest`/`vboxvideo` drivers since ~4.14, maintained by
kernel developers in lockstep with internal DRM API changes — unlike VirtualBox's
out-of-tree copy, which lags behind and breaks on DRM churn.

Set `virtualisation.virtualbox.guest.use3rdPartyModules = false;` in both
`modules/gpu/vm.nix` and `modules/gpu/vanilla-vm.nix`. This:

- Uses the kernel's built-in VirtualBox drivers instead of compiling VirtualBox's own
  out-of-tree copy — eliminates the compile failure at its root, and stays correct
  across future kernel bumps without further pinning.
- Requires no hypervisor detection: on a real VirtualBox host the in-tree driver binds
  normally; on Proxmox/QEMU-KVM it simply never activates (no VirtualBox device
  present) — no per-host module, no install-time question.
- Removes the sole justification for the `linuxPackages_6_12` pin, so the pin is
  removed and both files revert to the shared kernel default
  (`modules/system.nix`'s `boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;`).

### Out of scope

- `modules/gpu/vm.nix`'s `services.scx.enable = lib.mkForce false;` line and its stale
  comment (says "pinned to 6.6 LTS" while the pin was actually 6.12) are pre-existing,
  unrelated tech debt — not touched by this change, but noted for the user.

## 4. Implementation Steps (Module Architecture Pattern — no new files needed)

1. `modules/gpu/vm.nix`: remove the `boot.kernelPackages = lib.mkForce ...` line and its
   comment block; add `virtualisation.virtualbox.guest.use3rdPartyModules = false;` next
   to the existing `virtualisation.virtualbox.guest.*` lines.
2. `modules/gpu/vanilla-vm.nix`: same change.

## 5. Dependencies

None — no new flake inputs, no new packages. Pure NixOS option change using an
already-declared upstream option (`virtualisation.virtualbox.guest.use3rdPartyModules`,
nixpkgs `nixos/modules/virtualisation/virtualbox-guest.nix`).

## 6. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| In-tree `vboxvideo` lacks a feature real VirtualBox users need (e.g. dynamic resize) | LOW | `dragAndDrop`, `clipboard`, `seamless` are handled by `VBoxService` talking to the in-kernel `vboxguest` char device — unaffected by which module built the driver. Only the DRM video path changes, and the in-tree driver implements the same VBoxVGA/VMSVGA modesetting. |
| Removing the kernel pin re-exposes an unrelated latent incompatibility on `linuxPackages_latest` | LOW | The pin's only documented purpose was the vboxvideo compile failure; no other issue was recorded against it in this repo's docs. |
| `vanilla-vm.nix` regresses independently of `vm.nix` | LOW | Both files are edited identically; vanilla role has no other kernel-related imports. |

## 7. Configuration Changes Summary

| File | Action |
|------|--------|
| `modules/gpu/vm.nix` | Remove kernel pin; add `use3rdPartyModules = false` |
| `modules/gpu/vanilla-vm.nix` | Remove kernel pin; add `use3rdPartyModules = false` |
