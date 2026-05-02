# Specification: Replace virt-manager with VirtualBox

## Feature Name
`virtualbox_replacement`

## Date
2026-05-01

---

## 1. Current State Analysis

### 1.1 Virtualization Module (`modules/virtualization.nix`)

Currently imported **only by `configuration-desktop.nix`** (the desktop role). No other role imports it.

The module enables:
- `virtualisation.libvirtd.enable = true` — the libvirt daemon (QEMU/KVM backend)
- `virtualisation.libvirtd.qemu.package = pkgs.qemu_kvm` — KVM-accelerated QEMU
- `virtualisation.libvirtd.qemu.runAsRoot = false` — runs QEMU as calling user
- `virtualisation.libvirtd.qemu.swtpm.enable = true` — virtual TPM 2.0 (for Windows 11 guests)
- `virtualisation.spiceUSBRedirection.enable = true` — USB passthrough inside SPICE sessions
- `users.users.nimda.extraGroups = [ "libvirtd" ]` — grants user access to libvirtd

Packages installed:
- `virt-manager` — GUI for creating/managing VMs
- `virt-viewer` — lightweight SPICE/VNC console
- `virtio-win` — VirtIO driver ISO for Windows guests

### 1.2 GNOME Boxes

- Already installed in `configuration-desktop.nix` as `unstable.gnome-boxes`
- Already in GNOME Shell favorite-apps (both `home-desktop.nix` dconf and `modules/gnome-desktop.nix` system dconf)
- GNOME Boxes **uses libvirt + QEMU as its backend** (confirmed via GNOME project: "Boxes shares a lot of code with virt-manager, mainly in the form of libvirt, libosinfo and qemu")

### 1.3 VM Guest Configuration (`modules/gpu/vm.nix`)

This is for running vexos **inside** a VM (guest additions). It is **not affected** by this change — it configures VirtualBox Guest Additions and QEMU guest agent for when vexos is the guest OS. No changes needed here.

### 1.4 Flake VirtualBox Guards (`flake.nix`)

Lines 291–321 contain guards that `mkForce false` the VirtualBox Guest Additions on bare-metal variants. These are unrelated to VirtualBox *host* functionality and remain unchanged.

### 1.5 Unfree Packages

`nixpkgs.config.allowUnfree = true` is already set in `modules/nix.nix` — the VirtualBox extension pack (unfree) is permitted if we choose to enable it.

---

## 2. Problem Definition

The user wants to:
1. **Remove virt-manager** as the VM management GUI
2. **Add VirtualBox** as the primary hypervisor for creating and managing VMs
3. **Keep GNOME Boxes** as a secondary/simple VM tool

Since GNOME Boxes depends on libvirt + QEMU under the hood, those services must remain. The change is specifically:
- Remove the virt-manager GUI and its associated packages (virt-viewer, virtio-win, SPICE USB redirection)
- Add VirtualBox host support
- Keep libvirtd + QEMU running for GNOME Boxes

---

## 3. Research Summary

### Source 1: NixOS Wiki — VirtualBox
- `virtualisation.virtualbox.host.enable = true` is the correct option
- Users must be in the `vboxusers` group: `users.extraGroups.vboxusers.members = [ "nimda" ]`
- **Do NOT** add `virtualbox` to `environment.systemPackages` — the module handles it
- Extension pack (`virtualisation.virtualbox.host.enableExtensionPack = true`) enables USB 2/3 passthrough but is unfree and causes frequent recompilation
- Audio driver issues may occur — PULSE backend is recommended (already using PipeWire which provides PulseAudio compat)

### Source 2: NixOS Wiki — Virt-manager / GNOME Boxes relationship
- GNOME Boxes uses libvirt + QEMU as its backend
- `virtualisation.libvirtd.enable = true` is required for GNOME Boxes to function
- The user needs to remain in the `libvirtd` group

### Source 3: GNOME Project — Boxes Architecture
- Boxes "shares a lot of code with virt-manager, mainly in the form of libvirt, libosinfo and qemu"
- Boxes targets desktop end-users who want a simple way to try OSes
- Removing libvirtd would break GNOME Boxes entirely

### Source 4: NixOS Options — virtualisation.virtualbox.host
- `virtualisation.virtualbox.host.enable` — enables VirtualBox host services and kernel modules
- `virtualisation.virtualbox.host.enableExtensionPack` — Oracle extension pack (unfree, triggers recompilation)
- `virtualisation.virtualbox.host.enableHardening` — defaults to true, provides kernel module hardening
- `virtualisation.virtualbox.host.enableKvm` — use KVM as backend (available since VirtualBox 6.1)
- `virtualisation.virtualbox.host.addNetworkFilterRules` — for VirtualBox network filtering

### Source 5: NixOS nixpkgs — VirtualBox kernel module considerations
- VirtualBox builds kernel modules (`vboxdrv`, `vboxnetflt`, `vboxnetadp`, `vboxpci`) against the running kernel
- Kernel updates trigger VirtualBox module recompilation
- The extension pack additionally triggers a full VirtualBox recompilation on any nixpkgs update
- Recommendation: enable extension pack only if USB 2/3 passthrough is needed

### Source 6: SPICE USB Redirection
- `virtualisation.spiceUSBRedirection.enable` is specifically for SPICE-based VM consoles (virt-manager / virt-viewer)
- GNOME Boxes handles its own display and USB integration through its built-in SPICE client
- VirtualBox has its own USB passthrough mechanism
- This option can be safely removed

---

## 4. Proposed Solution Architecture

### 4.1 Module Design (Option B compliance)

The existing `modules/virtualization.nix` is already a role-specific module imported only by `configuration-desktop.nix`. It will be modified in-place since it remains desktop-only. No new files need to be created.

### 4.2 Changes to `modules/virtualization.nix`

**Remove:**
- `virtualisation.spiceUSBRedirection.enable = true`
- Package: `virt-manager`
- Package: `virt-viewer`
- Package: `virtio-win`

**Keep (required for GNOME Boxes):**
- `virtualisation.libvirtd.enable = true`
- `virtualisation.libvirtd.qemu.package = pkgs.qemu_kvm`
- `virtualisation.libvirtd.qemu.runAsRoot = false`
- `virtualisation.libvirtd.qemu.swtpm.enable = true` (still useful for Windows 11 guests in GNOME Boxes)
- `users.users.nimda.extraGroups` must include `"libvirtd"`

**Add:**
- `virtualisation.virtualbox.host.enable = true`
- `virtualisation.virtualbox.host.enableExtensionPack = true` (for USB 2/3 passthrough; unfree is already permitted)
- `users.users.nimda.extraGroups` must include `"vboxusers"`

### 4.3 Changes to `home-desktop.nix`

**Remove from dconf `favorite-apps`:**
- No changes needed — `org.gnome.Boxes.desktop` is already present and should stay

**Add to dconf `favorite-apps`:**
- `"virtualbox.desktop"` — add VirtualBox to the GNOME Shell dock

### 4.4 Changes to `modules/gnome-desktop.nix`

**Add to system dconf `favorite-apps`:**
- `"virtualbox.desktop"` — add VirtualBox to the system-level GNOME Shell dock (this is the authoritative source for new installs; `home-desktop.nix` is the user-level override)

### 4.5 No changes needed to:
- `configuration-desktop.nix` — already imports `modules/virtualization.nix` and installs `gnome-boxes`
- `configuration-htpc.nix` — does not import virtualization module
- `configuration-server.nix` — does not import virtualization module
- `configuration-headless-server.nix` — does not import virtualization module
- `configuration-stateless.nix` — does not import virtualization module
- `modules/gpu/vm.nix` — guest additions, unrelated to host configuration
- `flake.nix` — VirtualBox guest guards are unrelated

---

## 5. Implementation Steps

### Step 1: Modify `modules/virtualization.nix`

Replace the entire file content with the new configuration:
1. Update the header comment to reflect VirtualBox + GNOME Boxes (libvirt backend)
2. Keep the libvirtd section but update comments to indicate it serves GNOME Boxes
3. Remove `virtualisation.spiceUSBRedirection.enable = true`
4. Remove all three packages (`virt-manager`, `virt-viewer`, `virtio-win`)
5. Remove the `environment.systemPackages` block entirely (no VM packages needed — VirtualBox is provided by its module, GNOME Boxes is installed in `configuration-desktop.nix`)
6. Add `virtualisation.virtualbox.host.enable = true`
7. Add `virtualisation.virtualbox.host.enableExtensionPack = true`
8. Update `users.users.nimda.extraGroups` to include both `"libvirtd"` and `"vboxusers"`

### Step 2: Update `home-desktop.nix` dconf favorite-apps

Add `"virtualbox.desktop"` to the `favorite-apps` list in dconf settings.

### Step 3: Update `modules/gnome-desktop.nix` system dconf favorite-apps

Add `"virtualbox.desktop"` to the system-level `favorite-apps` list.

---

## 6. Dependencies

- **VirtualBox kernel modules**: Built against the current kernel. The desktop role uses CachyOS/performance kernels — VirtualBox modules should compile against these. If not, this is a build-time failure that will be caught by `nix flake check` or dry-build.
- **VirtualBox Extension Pack**: Unfree Oracle software. `nixpkgs.config.allowUnfree = true` is already set in `modules/nix.nix`. Triggers recompilation on nixpkgs updates — this is a known trade-off the user accepts for USB passthrough.
- **libvirtd + QEMU**: Retained for GNOME Boxes. No new dependencies.
- **GNOME Boxes**: Already installed via `configuration-desktop.nix` from unstable channel. No changes needed.

---

## 7. Configuration Changes Summary

| File | Action | Details |
|------|--------|---------|
| `modules/virtualization.nix` | Modify | Remove virt-manager/SPICE, add VirtualBox host, keep libvirtd for Boxes |
| `home-desktop.nix` | Modify | Add `virtualbox.desktop` to dconf favorite-apps |
| `modules/gnome-desktop.nix` | Modify | Add `virtualbox.desktop` to system dconf favorite-apps |

---

## 8. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| VirtualBox kernel modules fail to build against CachyOS/custom kernel | HIGH | Caught at dry-build time. VirtualBox supports mainline kernels well; CachyOS is close to mainline. Fallback: disable VirtualBox and use only GNOME Boxes. |
| Extension pack triggers long recompilation on updates | LOW | Accepted trade-off. User can disable extension pack later if recompilation time is unacceptable. |
| GNOME Boxes loses functionality without SPICE USB redirection | LOW | GNOME Boxes has its own built-in SPICE client that handles USB; the system-level `spiceUSBRedirection` option is for virt-viewer specifically. |
| VirtualBox and KVM conflict (both trying to use hardware virtualization) | MEDIUM | VirtualBox 6.1+ can use KVM as backend on Linux (`enableKvm` option). Both can coexist — only one hypervisor uses VT-x at a time per VM. KVM modules are always loaded on NixOS when libvirtd is enabled; VirtualBox modules coexist. No conflict if VMs from both are not run simultaneously. |
| `virtualbox.desktop` file name may differ | LOW | Verify actual .desktop file name from the VirtualBox NixOS package. It may be `virtualbox.desktop` or `org.virtualbox.VirtualBox.desktop`. Check at implementation time. |
| Removing virtio-win breaks existing Windows VMs in GNOME Boxes | LOW | virtio-win was for virt-manager. GNOME Boxes uses its own driver provisioning via libosinfo. Users can manually download VirtIO drivers if needed for GNOME Boxes Windows guests. |

---

## 9. Target File Content

### `modules/virtualization.nix` (new content)

```nix
# modules/virtualization.nix
# Desktop virtualisation: VirtualBox host (primary hypervisor) and
# libvirt/QEMU backend for GNOME Boxes.
{ pkgs, ... }:
{
  # ── VirtualBox host ───────────────────────────────────────────────────────
  virtualisation.virtualbox.host.enable = true;
  virtualisation.virtualbox.host.enableExtensionPack = true;   # USB 2/3 passthrough (unfree)

  # ── libvirt / KVM (GNOME Boxes backend) ───────────────────────────────────
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package      = pkgs.qemu_kvm;
      runAsRoot    = false;
      swtpm.enable = true;               # Virtual TPM 2.0 (Windows 11 guests in Boxes)
    };
  };

  # ── User groups ───────────────────────────────────────────────────────────
  users.users.nimda.extraGroups = [ "libvirtd" "vboxusers" ];
}
```

---

## 10. Roles Affected

| Role | Imports virtualization.nix? | Impact |
|------|---------------------------|--------|
| desktop | YES | Full impact — gets VirtualBox + simplified libvirt |
| htpc | NO | None |
| server | NO | None |
| headless-server | NO | None |
| stateless | NO | None |
