# Privacy Role Specification
## vexos-nix — `vexos-privacy-{amd,nvidia,intel,vm}` Flake Outputs

**Date:** 2026-04-09  
**Status:** Draft — awaiting implementation  

---

## 1. Current State Analysis

### 1.1 Flake Output Structure

`flake.nix` currently defines four `nixosConfigurations`:

| Output name              | Host file          |
|--------------------------|--------------------|
| `vexos-desktop-amd`      | `hosts/amd.nix`    |
| `vexos-desktop-nvidia`   | `hosts/nvidia.nix` |
| `vexos-desktop-intel`    | `hosts/intel.nix`  |
| `vexos-desktop-vm`       | `hosts/vm.nix`     |

Every configuration is assembled as:

```nix
nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/<variant>.nix ];
  specialArgs = { inherit inputs; };
}
```

`commonModules` is a let-binding shared by all four:

```nix
commonModules = [
  /etc/nixos/hardware-configuration.nix          # host-generated, never committed
  nix-gaming.nixosModules.pipewireLowLatency      # low-latency PipeWire tuning
  unstableOverlayModule                           # exposes pkgs.unstable.*
  homeManagerModule                               # home-manager wiring for user nimda
];
```

### 1.2 Host File Pattern

Each host file follows one of two patterns:

**Pattern A — bare-metal (amd, nvidia, intel):**
```nix
{ lib, ... }: {
  imports = [
    ../configuration.nix          # shared base
    ../modules/gpu/<brand>.nix    # GPU-specific driver config
    ../modules/asus.nix           # ASUS hardware (amd + nvidia only; absent in intel)
  ];
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Desktop <Brand>";
}
```

**Pattern B — VM guest (vm):**
```nix
{ inputs, ... }: {
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];
  networking.hostName = "vexos-desktop-vm";
  environment.systemPackages = [ inputs.up.packages.x86_64-linux.default ];
  system.nixos.distroName = "VexOS Desktop VM";
}
```

### 1.3 `configuration.nix` Import List

`configuration.nix` unconditionally imports all of the following modules:

```
modules/gnome.nix          — GNOME desktop, GDM, Wayland, extensions
modules/gaming.nix         — Steam, Proton, Gamescope, GameMode, controllers  ← EXCLUDED from privacy
modules/audio.nix          — PipeWire, ALSA/Pulse/JACK, Bluetooth codecs
modules/gpu.nix            — Common VA-API/Vulkan base (all GPU brands)
modules/flatpak.nix        — Flatpak runtime + Flathub bootstrapping + app list
modules/network.nix        — NetworkManager, Avahi, firewall, systemd-resolved
modules/development.nix    — VS Code, Python/Rust/Node, Podman, GH CLI, etc.   ← EXCLUDED from privacy
modules/virtualization.nix — libvirt/KVM, virt-manager, SPICE redirection       ← EXCLUDED from privacy
modules/branding.nix       — Plymouth theme, OS identity, pixmaps logos
modules/system.nix         — Kernel, boot params, ZRAM, sysctl tunables, swap
```

`modules/asus.nix` is imported at the **host level** (in `hosts/amd.nix` and `hosts/nvidia.nix`), not in `configuration.nix`. It must be absent from all privacy host files.

`modules/packages.nix` exists in the repo but is **not currently imported** anywhere. It contains basic utilities (brave, inxi, git, curl, wget, htop) that are otherwise provided by `modules/development.nix`. Removing `development.nix` in the privacy build makes this module necessary.

### 1.4 User Group Dependencies

`configuration.nix` adds the following groups to `users.users.nimda.extraGroups`:

```nix
[ "wheel" "networkmanager" "gamemode" "audio" "input" "plugdev" ]
```

`gamemode` is only defined when `programs.gamemode.enable = true` (in `modules/gaming.nix`). If `gaming.nix` is absent, this group does not exist and NixOS evaluation **will fail** with an undefined group error. `input` and `plugdev` are standard Linux groups (always present via shadow/udev); they are safe to retain or remove, but are gaming-peripheral-related and should be dropped in the privacy profile for minimal footprint.

`libvirtd` is added to `extraGroups` inside `modules/virtualization.nix` itself, not in `configuration.nix`, so it requires no change.

### 1.5 `nix-gaming` Interaction

`nix-gaming.nixosModules.pipewireLowLatency` is imported in `commonModules` (flake.nix) and activated in `modules/audio.nix` via `lowLatency.enable = true`. Since `audio.nix` is retained in the privacy build, this interaction is unchanged and correct.

---

## 2. Problem Definition

A new **Privacy** role is required with:

- Four variants: `vexos-privacy-amd`, `vexos-privacy-nvidia`, `vexos-privacy-intel`, `vexos-privacy-vm`
- Identical GPU/VM driver wiring as the corresponding desktop variants
- The following modules **must be absent**:
  - `modules/asus.nix`
  - `modules/development.nix`
  - `modules/gaming.nix`
  - `modules/virtualization.nix`

The current `configuration.nix` imports three of those four excluded modules unconditionally, so the privacy variants cannot reuse it. A separate base configuration is required.

---

## 3. Proposed Solution Architecture

### 3.1 Overview

Create a new `configuration-privacy.nix` that mirrors `configuration.nix` but omits the four excluded modules and adjusts the user group list accordingly. Create four new privacy host files in `hosts/`. Add four new `nixosConfigurations` entries to `flake.nix`.

No existing files are deleted or restructured. `configuration.nix` and all existing desktop host files remain fully intact.

### 3.2 Module Inclusion Matrix

| Module                    | Desktop | Privacy |
|---------------------------|---------|---------|
| `modules/gnome.nix`       | ✓       | ✓       |
| `modules/audio.nix`       | ✓       | ✓       |
| `modules/gpu.nix`         | ✓       | ✓       |
| `modules/flatpak.nix`     | ✓       | ✓       |
| `modules/network.nix`     | ✓       | ✓       |
| `modules/branding.nix`    | ✓       | ✓       |
| `modules/system.nix`      | ✓       | ✓       |
| `modules/packages.nix`    | ✗       | ✓ (new) |
| `modules/gaming.nix`      | ✓       | ✗       |
| `modules/development.nix` | ✓       | ✗       |
| `modules/virtualization.nix` | ✓    | ✗       |
| `modules/asus.nix`        | ✓ (amd/nvidia hosts) | ✗ |

`modules/packages.nix` is added to `configuration-privacy.nix` to supply the basic utilities (git, curl, wget, htop, brave, inxi) that `development.nix` normally provides.

### 3.3 Files to Create

#### 3.3.1 `configuration-privacy.nix`

Mirrors `configuration.nix` with the following differences:

- **Imports**: remove `gaming.nix`, `development.nix`, `virtualization.nix`; add `packages.nix`
- **User extraGroups**: remove `"gamemode"`, `"input"`, `"plugdev"` (gaming-specific)
- **`networking.hostName`**: change `mkDefault` value to `"vexos-privacy"` 
- All Nix settings blocks, time/locale, and `nix.gc` configuration are identical to `configuration.nix` and must be copied verbatim

Planned imports section:
```nix
imports = [
  ./modules/gnome.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/flatpak.nix
  ./modules/network.nix
  ./modules/packages.nix
  ./modules/branding.nix
  ./modules/system.nix
];
```

Planned user groups:
```nix
users.users.nimda.extraGroups = [
  "wheel"
  "networkmanager"
  "audio"
];
```

#### 3.3.2 `hosts/privacy-amd.nix`

```nix
# hosts/privacy-amd.nix
# vexos — Privacy AMD GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-privacy-amd
{ lib, ... }:
{
  imports = [
    ../configuration-privacy.nix
    ../modules/gpu/amd.nix
  ];
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Privacy AMD";
}
```

#### 3.3.3 `hosts/privacy-nvidia.nix`

```nix
# hosts/privacy-nvidia.nix
# vexos — Privacy NVIDIA GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-privacy-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-privacy.nix
    ../modules/gpu/nvidia.nix
  ];
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Privacy NVIDIA";
}
```

#### 3.3.4 `hosts/privacy-intel.nix`

```nix
# hosts/privacy-intel.nix
# vexos — Privacy Intel GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-privacy-intel
{ lib, ... }:
{
  imports = [
    ../configuration-privacy.nix
    ../modules/gpu/intel.nix
  ];
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Privacy Intel";
}
```

#### 3.3.5 `hosts/privacy-vm.nix`

```nix
# hosts/privacy-vm.nix
# vexos — Privacy VM guest build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-privacy-vm
{ inputs, ... }:
{
  imports = [
    ../configuration-privacy.nix
    ../modules/gpu/vm.nix
  ];
  networking.hostName = "vexos-privacy-vm";
  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
  system.nixos.distroName = "VexOS Privacy VM";
}
```

### 3.4 Files to Modify

#### 3.4.1 `flake.nix`

Add four new `nixosConfigurations` entries inside the `outputs` attrset, after the existing `vexos-desktop-intel` block and before the `nixosModules` block:

```nix
# ── Privacy AMD build ────────────────────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-privacy-amd
nixosConfigurations.vexos-privacy-amd = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/privacy-amd.nix ];
  specialArgs = { inherit inputs; };
};

# ── Privacy NVIDIA build ─────────────────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-privacy-nvidia
nixosConfigurations.vexos-privacy-nvidia = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/privacy-nvidia.nix ];
  specialArgs = { inherit inputs; };
};

# ── Privacy Intel build ──────────────────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-privacy-intel
nixosConfigurations.vexos-privacy-intel = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/privacy-intel.nix ];
  specialArgs = { inherit inputs; };
};

# ── Privacy VM build ─────────────────────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-privacy-vm
nixosConfigurations.vexos-privacy-vm = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/privacy-vm.nix ];
  specialArgs = { inherit inputs; };
};
```

No other changes to `flake.nix` are needed. `commonModules`, inputs, overlays, and `nixosModules` are untouched.

---

## 4. Implementation Steps

Execute in the order listed. Each step must succeed before proceeding.

1. **Create `configuration-privacy.nix`** at repo root.  
   - Copy the full text of `configuration.nix`.  
   - Replace the `imports` block with the privacy-specific list (add `packages.nix`, remove `gaming.nix`, `development.nix`, `virtualization.nix`).  
   - Remove `"gamemode"`, `"input"`, `"plugdev"` from `users.users.nimda.extraGroups`.  
   - Change `networking.hostName = lib.mkDefault "vexos-desktop"` to `lib.mkDefault "vexos-privacy"`.  
   - All other settings (`nix.settings`, `time.timeZone`, `i18n`, `nix.gc`, etc.) are kept verbatim.

2. **Create `hosts/privacy-amd.nix`** with the content from section 3.3.2.

3. **Create `hosts/privacy-nvidia.nix`** with the content from section 3.3.3.

4. **Create `hosts/privacy-intel.nix`** with the content from section 3.3.4.

5. **Create `hosts/privacy-vm.nix`** with the content from section 3.3.5.

6. **Modify `flake.nix`** — insert the four new `nixosConfigurations` entries from section 3.4.1 after the `vexos-desktop-intel` block.

7. **Run `nix flake check`** to validate flake structure and evaluate all eight outputs (4 desktop + 4 privacy).

8. **Run dry-build for each privacy variant** to confirm the system closure evaluates without errors:
   ```
   sudo nixos-rebuild dry-build --flake .#vexos-privacy-amd
   sudo nixos-rebuild dry-build --flake .#vexos-privacy-nvidia
   sudo nixos-rebuild dry-build --flake .#vexos-privacy-intel
   sudo nixos-rebuild dry-build --flake .#vexos-privacy-vm
   ```

---

## 5. Risks and Mitigations

### 5.1 `gamemode` group undefined — CRITICAL

**Risk:** `configuration.nix` references the `"gamemode"` group in `users.users.nimda.extraGroups`. This group is created by `programs.gamemode.enable = true` inside `modules/gaming.nix`. If `gaming.nix` is absent and `"gamemode"` remains in `extraGroups`, NixOS evaluation will abort with:
```
error: The group 'gamemode' specified in extraGroups does not exist.
```

**Mitigation:** `configuration-privacy.nix` must remove `"gamemode"` from `extraGroups`. This is specified explicitly in section 3.3.1 and step 1.

### 5.2 `modules/packages.nix` not currently imported anywhere

**Risk:** Basic CLI utilities (git, curl, wget, htop, brave, inxi) are currently provided exclusively by `modules/development.nix`. Removing `development.nix` without adding `packages.nix` leaves the privacy build without these tools.

**Mitigation:** `configuration-privacy.nix` imports `./modules/packages.nix`. This module already exists and is otherwise unused — no new file needs to be written.

### 5.3 `nix-gaming.nixosModules.pipewireLowLatency` in `commonModules`

**Risk:** The `pipewireLowLatency` module is always imported (it is part of `commonModules`). Without `modules/audio.nix` it would be a no-op, but `audio.nix` IS retained in the privacy build and activates it via `lowLatency.enable = true`. No conflict.

**Mitigation:** No action required. Verified compatible.

### 5.4 `modules/flatpak.nix` installs gaming-adjacent Flatpak apps (Lutris, ProtonPlus)

**Risk:** `flatpak.nix` is retained in the privacy build. Its bootstrapping service installs `net.lutris.Lutris` and `com.vysp3r.ProtonPlus` alongside general apps. These are gaming-adjacent but are installed as Flatpaks (sandboxed), not system packages.

**Mitigation:** Out of scope for this specification — the requirement excludes the `gaming.nix` *module* specifically, not Flatpak-distributed gaming apps. If stricter control is desired, a future `modules/flatpak-privacy.nix` variant can be created; that is a separate concern.

### 5.5 `hardware-configuration.nix` must not be committed

**Risk:** `commonModules` still references `/etc/nixos/hardware-configuration.nix`. Privacy builds use the same `commonModules`, so this constraint is unchanged and correctly handled.

**Mitigation:** No action required. The privacy builds inherit this behaviour.

### 5.6 `system.stateVersion` must not change

**Risk:** Copying `configuration.nix` to `configuration-privacy.nix` must not alter `system.stateVersion`.

**Mitigation:** `configuration.nix` does not set `system.stateVersion` directly (it is set by `hardware-configuration.nix` on the host). Confirmed safe.

### 5.7 Dry-build requires `/etc/nixos/hardware-configuration.nix` to exist on the build host

**Risk:** `nix flake check` evaluates all outputs. If run on a host where `/etc/nixos/hardware-configuration.nix` does not exist, evaluation of all eight `nixosConfigurations` entries will fail.

**Mitigation:** Run `nix flake check` and `nixos-rebuild dry-build` on the actual NixOS host where `/etc/nixos/hardware-configuration.nix` is present. This is the standard workflow for this project.

---

## 6. Summary of Files

### Created (5 new files)

| File | Description |
|------|-------------|
| `configuration-privacy.nix` | Privacy base config: gnome + audio + gpu + flatpak + network + packages + branding + system |
| `hosts/privacy-amd.nix` | AMD privacy host: configuration-privacy + gpu/amd |
| `hosts/privacy-nvidia.nix` | NVIDIA privacy host: configuration-privacy + gpu/nvidia |
| `hosts/privacy-intel.nix` | Intel privacy host: configuration-privacy + gpu/intel |
| `hosts/privacy-vm.nix` | VM privacy host: configuration-privacy + gpu/vm + Up package |

### Modified (1 existing file)

| File | Change |
|------|--------|
| `flake.nix` | Add 4 new `nixosConfigurations` entries: `vexos-privacy-{amd,nvidia,intel,vm}` |

### Untouched

All existing desktop host files, `configuration.nix`, all existing modules, `home.nix`, `flake.lock`, and `scripts/` remain unchanged.
