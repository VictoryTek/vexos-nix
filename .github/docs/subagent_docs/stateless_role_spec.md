# Stateless Role Specification
## vexos-nix — `vexos-stateless-{amd,nvidia,intel,vm}` Flake Outputs

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
modules/gaming.nix         — Steam, Proton, Gamescope, GameMode, controllers  ← EXCLUDED from stateless
modules/audio.nix          — PipeWire, ALSA/Pulse/JACK, Bluetooth codecs
modules/gpu.nix            — Common VA-API/Vulkan base (all GPU brands)
modules/flatpak.nix        — Flatpak runtime + Flathub bootstrapping + app list
modules/network.nix        — NetworkManager, Avahi, firewall, systemd-resolved
modules/development.nix    — VS Code, Python/Rust/Node, Podman, GH CLI, etc.   ← EXCLUDED from stateless
modules/virtualization.nix — libvirt/KVM, virt-manager, SPICE redirection       ← EXCLUDED from stateless
modules/branding.nix       — Plymouth theme, OS identity, pixmaps logos
modules/system.nix         — Kernel, boot params, ZRAM, sysctl tunables, swap
```

`modules/asus.nix` is imported at the **host level** (in `hosts/amd.nix` and `hosts/nvidia.nix`), not in `configuration.nix`. It must be absent from all stateless host files.

`modules/packages.nix` exists in the repo but is **not currently imported** anywhere. It contains basic utilities (brave, inxi, git, curl, wget, htop) that are otherwise provided by `modules/development.nix`. Removing `development.nix` in the stateless build makes this module necessary.

### 1.4 User Group Dependencies

`configuration.nix` adds the following groups to `users.users.nimda.extraGroups`:

```nix
[ "wheel" "networkmanager" "gamemode" "audio" "input" "plugdev" ]
```

`gamemode` is only defined when `programs.gamemode.enable = true` (in `modules/gaming.nix`). If `gaming.nix` is absent, this group does not exist and NixOS evaluation **will fail** with an undefined group error. `input` and `plugdev` are standard Linux groups (always present via shadow/udev); they are safe to retain or remove, but are gaming-peripheral-related and should be dropped in the stateless profile for minimal footprint.

`libvirtd` is added to `extraGroups` inside `modules/virtualization.nix` itself, not in `configuration.nix`, so it requires no change.

### 1.5 `nix-gaming` Interaction

`nix-gaming.nixosModules.pipewireLowLatency` is imported in `commonModules` (flake.nix) and activated in `modules/audio.nix` via `lowLatency.enable = true`. Since `audio.nix` is retained in the stateless build, this interaction is unchanged and correct.

---

## 2. Problem Definition

A new **Stateless** role is required with:

- Four variants: `vexos-stateless-amd`, `vexos-stateless-nvidia`, `vexos-stateless-intel`, `vexos-stateless-vm`
- Identical GPU/VM driver wiring as the corresponding desktop variants
- The following modules **must be absent**:
  - `modules/asus.nix`
  - `modules/development.nix`
  - `modules/gaming.nix`
  - `modules/virtualization.nix`

The current `configuration.nix` imports three of those four excluded modules unconditionally, so the stateless variants cannot reuse it. A separate base configuration is required.

---

## 3. Proposed Solution Architecture

### 3.1 Overview

Create a new `configuration-stateless.nix` that mirrors `configuration.nix` but omits the four excluded modules and adjusts the user group list accordingly. Create four new stateless host files in `hosts/`. Add four new `nixosConfigurations` entries to `flake.nix`.

No existing files are deleted or restructured. `configuration.nix` and all existing desktop host files remain fully intact.

### 3.2 Module Inclusion Matrix

| Module                    | Desktop | Stateless |
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

`modules/packages.nix` is added to `configuration-stateless.nix` to supply the basic utilities (git, curl, wget, htop, brave, inxi) that `development.nix` normally provides.

### 3.3 Files to Create

#### 3.3.1 `configuration-stateless.nix`

Mirrors `configuration.nix` with the following differences:

- **Imports**: remove `gaming.nix`, `development.nix`, `virtualization.nix`; add `packages.nix`
- **User extraGroups**: remove `"gamemode"`, `"input"`, `"plugdev"` (gaming-specific)
- **`networking.hostName`**: change `mkDefault` value to `"vexos-stateless"` 
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

#### 3.3.2 `hosts/stateless-amd.nix`

```nix
# hosts/stateless-amd.nix
# vexos — Stateless AMD GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-amd
{ lib, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/amd.nix
  ];
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Stateless AMD";
}
```

#### 3.3.3 `hosts/stateless-nvidia.nix`

```nix
# hosts/stateless-nvidia.nix
# vexos — Stateless NVIDIA GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/nvidia.nix
  ];
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Stateless NVIDIA";
}
```

#### 3.3.4 `hosts/stateless-intel.nix`

```nix
# hosts/stateless-intel.nix
# vexos — Stateless Intel GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-intel
{ lib, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/intel.nix
  ];
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Stateless Intel";
}
```

#### 3.3.5 `hosts/stateless-vm.nix`

```nix
# hosts/stateless-vm.nix
# vexos — Stateless VM guest build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-vm
{ inputs, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/vm.nix
  ];
  networking.hostName = "vexos-stateless-vm";
  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
  system.nixos.distroName = "VexOS Stateless VM";
}
```

### 3.4 Files to Modify

#### 3.4.1 `flake.nix`

Add four new `nixosConfigurations` entries inside the `outputs` attrset, after the existing `vexos-desktop-intel` block and before the `nixosModules` block:

```nix
# ── Stateless AMD build ────────────────────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-stateless-amd
nixosConfigurations.vexos-stateless-amd = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/stateless-amd.nix ];
  specialArgs = { inherit inputs; };
};

# ── Stateless NVIDIA build ─────────────────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-stateless-nvidia
nixosConfigurations.vexos-stateless-nvidia = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/stateless-nvidia.nix ];
  specialArgs = { inherit inputs; };
};

# ── Stateless Intel build ──────────────────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-stateless-intel
nixosConfigurations.vexos-stateless-intel = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/stateless-intel.nix ];
  specialArgs = { inherit inputs; };
};

# ── Stateless VM build ─────────────────────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-stateless-vm
nixosConfigurations.vexos-stateless-vm = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/stateless-vm.nix ];
  specialArgs = { inherit inputs; };
};
```

No other changes to `flake.nix` are needed. `commonModules`, inputs, overlays, and `nixosModules` are untouched.

---

## 4. Implementation Steps

Execute in the order listed. Each step must succeed before proceeding.

1. **Create `configuration-stateless.nix`** at repo root.  
   - Copy the full text of `configuration.nix`.  
   - Replace the `imports` block with the stateless-specific list (add `packages.nix`, remove `gaming.nix`, `development.nix`, `virtualization.nix`).  
   - Remove `"gamemode"`, `"input"`, `"plugdev"` from `users.users.nimda.extraGroups`.  
   - Change `networking.hostName = lib.mkDefault "vexos-desktop"` to `lib.mkDefault "vexos-stateless"`.  
   - All other settings (`nix.settings`, `time.timeZone`, `i18n`, `nix.gc`, etc.) are kept verbatim.

2. **Create `hosts/stateless-amd.nix`** with the content from section 3.3.2.

3. **Create `hosts/stateless-nvidia.nix`** with the content from section 3.3.3.

4. **Create `hosts/stateless-intel.nix`** with the content from section 3.3.4.

5. **Create `hosts/stateless-vm.nix`** with the content from section 3.3.5.

6. **Modify `flake.nix`** — insert the four new `nixosConfigurations` entries from section 3.4.1 after the `vexos-desktop-intel` block.

7. **Run `nix flake check`** to validate flake structure and evaluate all eight outputs (4 desktop + 4 stateless).

8. **Run dry-build for each stateless variant** to confirm the system closure evaluates without errors:
   ```
   sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd
   sudo nixos-rebuild dry-build --flake .#vexos-stateless-nvidia
   sudo nixos-rebuild dry-build --flake .#vexos-stateless-intel
   sudo nixos-rebuild dry-build --flake .#vexos-stateless-vm
   ```

---

## 5. Risks and Mitigations

### 5.1 `gamemode` group undefined — CRITICAL

**Risk:** `configuration.nix` references the `"gamemode"` group in `users.users.nimda.extraGroups`. This group is created by `programs.gamemode.enable = true` inside `modules/gaming.nix`. If `gaming.nix` is absent and `"gamemode"` remains in `extraGroups`, NixOS evaluation will abort with:
```
error: The group 'gamemode' specified in extraGroups does not exist.
```

**Mitigation:** `configuration-stateless.nix` must remove `"gamemode"` from `extraGroups`. This is specified explicitly in section 3.3.1 and step 1.

### 5.2 `modules/packages.nix` not currently imported anywhere

**Risk:** Basic CLI utilities (git, curl, wget, htop, brave, inxi) are currently provided exclusively by `modules/development.nix`. Removing `development.nix` without adding `packages.nix` leaves the stateless build without these tools.

**Mitigation:** `configuration-stateless.nix` imports `./modules/packages.nix`. This module already exists and is otherwise unused — no new file needs to be written.

### 5.3 `nix-gaming.nixosModules.pipewireLowLatency` in `commonModules`

**Risk:** The `pipewireLowLatency` module is always imported (it is part of `commonModules`). Without `modules/audio.nix` it would be a no-op, but `audio.nix` IS retained in the stateless build and activates it via `lowLatency.enable = true`. No conflict.

**Mitigation:** No action required. Verified compatible.

### 5.4 `modules/flatpak.nix` installs gaming-adjacent Flatpak apps (Lutris, ProtonPlus)

**Risk:** `flatpak.nix` is retained in the stateless build. Its bootstrapping service installs `net.lutris.Lutris` and `com.vysp3r.ProtonPlus` alongside general apps. These are gaming-adjacent but are installed as Flatpaks (sandboxed), not system packages.

**Mitigation:** Out of scope for this specification — the requirement excludes the `gaming.nix` *module* specifically, not Flatpak-distributed gaming apps. If stricter control is desired, a future `modules/flatpak-stateless.nix` variant can be created; that is a separate concern.

### 5.5 `hardware-configuration.nix` must not be committed

**Risk:** `commonModules` still references `/etc/nixos/hardware-configuration.nix`. Stateless builds use the same `commonModules`, so this constraint is unchanged and correctly handled.

**Mitigation:** No action required. The stateless builds inherit this behaviour.

### 5.6 `system.stateVersion` must not change

**Risk:** Copying `configuration.nix` to `configuration-stateless.nix` must not alter `system.stateVersion`.

**Mitigation:** `configuration.nix` does not set `system.stateVersion` directly (it is set by `hardware-configuration.nix` on the host). Confirmed safe.

### 5.7 Dry-build requires `/etc/nixos/hardware-configuration.nix` to exist on the build host

**Risk:** `nix flake check` evaluates all outputs. If run on a host where `/etc/nixos/hardware-configuration.nix` does not exist, evaluation of all eight `nixosConfigurations` entries will fail.

**Mitigation:** Run `nix flake check` and `nixos-rebuild dry-build` on the actual NixOS host where `/etc/nixos/hardware-configuration.nix` is present. This is the standard workflow for this project.

---

## 6. Summary of Files

### Created (5 new files)

| File | Description |
|------|-------------|
| `configuration-stateless.nix` | Stateless base config: gnome + audio + gpu + flatpak + network + packages + branding + system |
| `hosts/stateless-amd.nix` | AMD stateless host: configuration-stateless + gpu/amd |
| `hosts/stateless-nvidia.nix` | NVIDIA stateless host: configuration-stateless + gpu/nvidia |
| `hosts/stateless-intel.nix` | Intel stateless host: configuration-stateless + gpu/intel |
| `hosts/stateless-vm.nix` | VM stateless host: configuration-stateless + gpu/vm + Up package |

### Modified (1 existing file)

| File | Change |
|------|--------|
| `flake.nix` | Add 4 new `nixosConfigurations` entries: `vexos-stateless-{amd,nvidia,intel,vm}` |

### Untouched

All existing desktop host files, `configuration.nix`, all existing modules, `home.nix`, `flake.lock`, and `scripts/` remain unchanged.
