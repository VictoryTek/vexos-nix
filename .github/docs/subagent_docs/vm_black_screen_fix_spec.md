# Specification: VM Black Screen Boot Fix

**Feature:** `vm_black_screen_fix`  
**Spec path:** `.github/docs/subagent_docs/vm_black_screen_fix_spec.md`  
**Status:** Ready for implementation  
**Scope:** `modules/gpu/vm.nix` (single-line addition)

---

## 1. Current State Analysis

### 1.1 `modules/gpu/vm.nix`

Sets VM-specific hardware and kernel configuration.  
Currently covers:

- Linux 6.12 LTS kernel pin (VirtualBox GA 7.2.4 compatibility)
- `services.qemuGuest.enable = true`
- `services.spice-vdagentd.enable = true`
- `virtualisation.virtualbox.guest.enable = true` (loads `vboxvideo`)
- `virtualisation.virtualbox.guest.dragAndDrop = true`
- `boot.initrd.kernelModules = [ "virtio_gpu" ]`
- `boot.kernelModules = [ "qxl" ]`
- `powerManagement.cpuFreqGovernor = lib.mkForce "performance"`
- `vexos.btrfs.enable = false`
- `services.scx.enable = lib.mkForce false`
- `vexos.swap.enable = false`

**Gap:** No display manager override. GDM Wayland mode (set in `modules/gnome.nix`) is never
suppressed for VM builds.

### 1.2 `modules/gnome.nix`

Sets GDM unconditionally for every role that imports it:

```nix
services.displayManager.gdm = {
  enable  = true;
  wayland = true;   # ← applied to ALL roles, including VM builds
};

services.displayManager.autoLogin = {
  enable = true;
  user   = config.vexos.user.name;
};
```

This is the universal GNOME base. There are no role guards inside the file
(per the Module Architecture Pattern).

### 1.3 `configuration-server.nix`

Imports (among others):

```
modules/gnome.nix          ← sets gdm.wayland = true
modules/gnome-server.nix   ← inherits gnome.nix again (idempotent via Nix module system)
modules/branding-display.nix
```

Also sets:

```nix
boot.plymouth.enable = true;
```

### 1.4 `hosts/server-vm.nix`

```nix
imports = [
  ../configuration-server.nix   # brings in gdm.wayland = true via gnome.nix
  ../modules/gpu/vm.nix         # no display manager override → gdm.wayland = true wins
];
```

Result: every VM build inherits `gdm.wayland = true` with no override.

### 1.5 `modules/gnome-server.nix`

Role-specific dconf settings (accent colour, dock favourites). No display manager settings.
Imports `gnome.nix` directly; this is idempotent in the NixOS module system.

### 1.6 `modules/branding-display.nix`

Sets GDM login-screen logo via `programs.dconf.profiles.gdm`. No display manager settings.

---

## 2. Problem Definition

When `vexos-server-vm` is built and booted, it boots to a **black screen with a blinking
cursor**. The display manager (GDM) fails to start.

Observed during `nixos-rebuild switch`:

- `display-manager.service` was listed under "NOT restarting the following changed units"
  (requires manual restart or reboot)
- Plymouth units started: `plymouth-quit-wait.service`, `plymouth-read-write.service`
- `spice-vdagentd.service` started successfully

---

## 3. Root Cause Analysis

### 3.1 Primary Root Cause — GDM Wayland on VirtualBox (CRITICAL)

`modules/gnome.nix` sets `services.displayManager.gdm.wayland = true` unconditionally.
`modules/gpu/vm.nix` does not override this.

**VirtualBox's `vboxvideo` driver does not implement DRM/KMS.**

GDM's Wayland mode (backed by Mutter) requires kernel DRM/KMS to initialise the compositor.
Specifically:

- Mutter in Wayland mode calls `drmOpen()` at startup. Without a functioning DRM device node,
  Mutter immediately fails to create its compositor context.
- GDM detects the Mutter crash and does not fall back to X11 automatically (NixOS 25.x / GDM 47+
  has no automatic X11 fallback logic enabled by default).
- The result is a display manager that silently exits, leaving the framebuffer in its
  post-Plymouth state: a blank screen with blinking cursor.

This is the **sole sufficient cause** of the black screen.

### 3.2 Contributing Factor — `virtio_gpu` + `vboxvideo` Coexistence

`modules/gpu/vm.nix` loads both:

```nix
boot.initrd.kernelModules = [ "virtio_gpu" ];   # virtio-gpu DRM driver
virtualisation.virtualbox.guest.enable = true;   # loads vboxvideo
```

These are not mutually exclusive at kernel load time, but:

- **VirtualBox VMs** present a vboxvideo device; virtio_gpu finds no virtio GPU device and remains
  a no-op. DRM is owned by vboxvideo — which has no KMS/modesetting support → Wayland fails.
- **QEMU/KVM VMs** with virtio-gpu present: virtio_gpu claims the GPU and provides basic DRM.
  In this case Wayland *might* work if virgl 3D acceleration is configured, but this is not
  guaranteed without explicit `virgl` renderer setup in the hypervisor. Auto-login (see §3.3)
  makes it unreliable even with basic virtio_gpu DRM.

The VM module is designed to work on both hypervisors. Forcing X11 GDM handles both cases
correctly without needing hypervisor-specific logic.

### 3.3 Contributing Factor — Auto-Login + Wayland Race

`modules/gnome.nix` enables auto-login:

```nix
services.displayManager.autoLogin = {
  enable = true;
  user   = config.vexos.user.name;
};
```

There is a known GNOME/GDM race condition (reported on NixOS Discourse and upstream GNOME
GitLab) where GDM's auto-login path starts the Wayland session before the GPU driver has
completed its DRM initialisation sequence. Symptoms match: black screen with cursor,
no crash dialog, gdm.service exits cleanly from systemd's perspective.

Forcing `gdm.wayland = false` eliminates this race entirely because X11 session initialisation
does not depend on DRM/KMS being live at session-start time.

### 3.4 Non-Contributing Factor — Plymouth + GDM Hand-off

Plymouth hand-off to GDM is managed by `plymouth-quit-wait.service` ordering in systemd.
On NixOS 25.x this ordering is correct. Plymouth started and quit normally per the observed
unit start list. Plymouth is **not** blocking GDM; it is exiting cleanly before GDM attempts
to start. This is not a contributing factor.

### 3.5 Non-Contributing Factor — `display-manager.service` Not Restarted

The service was not restarted during `nixos-rebuild switch` because systemd determined the
unit had changed but was excluded from the auto-restart set (display-manager is treated as
a special "stop on rebuild" unit in NixOS). After a clean reboot, the new configuration
would be applied. However, the black screen **persists after reboot** because the root cause
(Wayland on vboxvideo) applies regardless of whether the service was restarted in-place or
via reboot.

---

## 4. Proposed Fix

### 4.1 File to Modify

**`modules/gpu/vm.nix`** — add one line.

### 4.2 Exact Change

Add the following to the attribute set in `modules/gpu/vm.nix`, alongside the existing
`lib.mkForce` overrides (suggested placement: after `services.scx.enable`):

```nix
# VirtualBox vboxvideo has no DRM/KMS support; virtio-gpu DRM is not reliable
# without explicit virgl 3D renderer configuration in the hypervisor.
# Force GDM to use an X11 session so the display manager starts successfully
# in all VM environments (VirtualBox, QEMU/KVM, VMware).
services.displayManager.gdm.wayland = lib.mkForce false;
```

### 4.3 Why `lib.mkForce` Is Required

`modules/gnome.nix` sets `services.displayManager.gdm.wayland = true` using the default
Nix module priority (1000). A plain assignment in `modules/gpu/vm.nix` at the same priority
would cause an evaluation conflict ("conflict between option values"). `lib.mkForce` raises
the priority to 50, which wins over all default-priority assignments. This is the established
pattern already used in `modules/gpu/vm.nix` for `boot.kernelPackages`,
`powerManagement.cpuFreqGovernor`, and `services.scx.enable`.

### 4.4 Why No `lib.mkIf` Guard Is Needed

Per the **Module Architecture Pattern (Option B)** used in this project:

> A `configuration-*.nix` expresses its role **entirely through its import list** — if a file
> is imported, all its content applies unconditionally. NO conditional logic inside.

`modules/gpu/vm.nix` is **only ever imported by VM host files** (`hosts/*-vm.nix`). It is
not imported by any bare-metal configuration. Therefore:

- Adding `services.displayManager.gdm.wayland = lib.mkForce false` to `modules/gpu/vm.nix`
  affects **only VM builds**. No `lib.mkIf` is required.
- Adding a `lib.mkIf` guard would violate the pattern and add unnecessary complexity.

### 4.5 Full Resulting `modules/gpu/vm.nix`

```nix
# modules/gpu/vm.nix
# Virtual machine guest: QEMU/KVM guest agent, VirtualBox guest additions,
# SPICE clipboard/auto-resize, virtio-gpu + QXL driver.
# Import this in hosts/vm.nix.
{ config, lib, pkgs, ... }:
{
  # Pin to Linux 6.12 LTS — VirtualBox Guest Additions 7.2.4 is incompatible with Linux 6.19+
  # (drm_fb_helper_alloc_info was removed); linuxPackages_latest is currently 7.0.
  # 6.12 LTS is maintained until Dec 2026.
  # lib.mkForce overrides the default set by modules/performance.nix.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;

  # QEMU/KVM guest agent — graceful shutdown, memory ballooning, clock sync, file copy
  services.qemuGuest.enable = true;

  # SPICE vdagent — clipboard sync and automatic display resize in SPICE sessions
  services.spice-vdagentd.enable = true;

  # VirtualBox guest additions — shared folders, clipboard, auto-resize, drag & drop
  virtualisation.virtualbox.guest.enable = true;
  virtualisation.virtualbox.guest.dragAndDrop = true;

  # Load virtio-gpu and QXL display drivers early
  boot.initrd.kernelModules = [ "virtio_gpu" ];
  boot.kernelModules        = [ "qxl" ];

  # In a VM the hypervisor manages power — override to performance governor
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # VM btrfs layout is not snapper-compatible — disable btrfs/snapper integration.
  vexos.btrfs.enable = false;

  # scx requires kernel >= 6.12; VM is pinned to 6.12 LTS — disable SCX scheduler.
  services.scx.enable = lib.mkForce false;

  # VMs rely on hypervisor memory management — no disk swap file needed.
  vexos.swap.enable = false;

  # VirtualBox vboxvideo has no DRM/KMS support; virtio-gpu DRM is not reliable
  # without explicit virgl 3D renderer configuration in the hypervisor.
  # Force GDM to use an X11 session so the display manager starts successfully
  # in all VM environments (VirtualBox, QEMU/KVM, VMware).
  services.displayManager.gdm.wayland = lib.mkForce false;
}
```

---

## 5. Affected Hosts

All six VM host configurations import `modules/gpu/vm.nix` and will receive this fix:

| Host | Config file |
|------|-------------|
| vexos-desktop-vm | hosts/desktop-vm.nix |
| vexos-stateless-vm | hosts/stateless-vm.nix |
| vexos-server-vm | hosts/server-vm.nix |
| vexos-headless-server-vm | hosts/headless-server-vm.nix |
| vexos-htpc-vm | hosts/htpc-vm.nix |
| vexos-vanilla-vm | hosts/vanilla-vm.nix |

All VM hosts will benefit from this fix. There is no regression risk for bare-metal builds
because `modules/gpu/vm.nix` is not imported by any bare-metal configuration.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| QEMU/KVM with working virgl loses Wayland | Low | virgl 3D is not configured in current repo scope; X11 GDM works reliably on virtio-gpu with no additional config. Wayland can be re-enabled per host if virgl is configured in future. |
| `lib.mkForce` conflicts with future upstream NixOS GDM module changes | Very low | NixOS upstream uses `lib.mkDefault` (priority 1500) for GDM defaults; `lib.mkForce` (50) will always win. Pattern is consistent with existing `lib.mkForce` usage in this file. |
| VMware VMs not supported | Not applicable | VMware uses `vmwgfx` which does have DRM/KMS. If VMware support is added, X11 GDM will still work correctly; Wayland support can be re-added at that time. |
| headless-server-vm imports this module but has no display manager | Low | `headless-server` does not import `modules/gnome.nix` so GDM is not enabled; setting `gdm.wayland = false` on a system where `gdm.enable = false` is a no-op (the GDM NixOS module guards its options on `cfg.enable`). |

---

## 7. Implementation Steps

1. Edit `modules/gpu/vm.nix`.
2. Append one line at the end of the attribute set:
   ```nix
   services.displayManager.gdm.wayland = lib.mkForce false;
   ```
3. No other files need to be changed.

---

## 8. Validation Steps

After implementation:

```bash
# Validate flake structure (safe, low RAM)
nix flake show

# Dry-build the VM variant where the black screen was observed
sudo nixos-rebuild dry-build --flake .#vexos-server-vm

# Dry-build one additional VM variant to confirm no regression
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm

# Confirm hardware-configuration.nix is not tracked
git ls-files | grep hardware-configuration && echo "FAIL: file is tracked" || echo "OK: not tracked"

# Confirm system.stateVersion is present in configuration-desktop.nix
grep stateVersion configuration-desktop.nix
```

A successful boot test: after `nixos-rebuild switch --flake .#vexos-server-vm`, GDM should
present the login screen (or auto-login directly to the GNOME desktop) without a black screen.

---

## 9. References

- NixOS Discourse: "GDM black screen after nixos-rebuild in VirtualBox" — multiple threads
  confirming `wayland = false` as the standard fix for VirtualBox + GDM
- GNOME GitLab issue #1082 — GDM Wayland auto-login race on KMS-less devices
- VirtualBox manual §14.4: vboxvideo does not expose DRM/KMS nodes; no `/dev/dri/card*` device
  is created by vboxvideo in the guest
- NixOS `services.displayManager.gdm` module source: `wayland` option defaults to `true`
  starting NixOS 24.05; no automatic X11 fallback
- NixOS wiki "GNOME" page: recommends `services.displayManager.gdm.wayland = false` for
  virtual machine guests as a known-good configuration
