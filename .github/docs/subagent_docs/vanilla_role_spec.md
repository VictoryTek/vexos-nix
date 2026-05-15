# Vanilla Role Specification

**Feature:** `vanilla` role — stock/default NixOS configuration for system restore  
**Date:** 2026-05-15  
**Status:** Draft

---

## 1. Current State Analysis

### How Roles Work in vexos-nix

The project defines NixOS system configurations via a layered architecture:

1. **Role configuration** (`configuration-<role>.nix`) — expresses the role entirely through its import list. Each imported module applies unconditionally (no `lib.mkIf` guards).
2. **Home Manager configuration** (`home-<role>.nix`) — user-level packages, shell config, desktop entries. Sets `home.username`, `home.homeDirectory`, user packages, and `home.stateVersion`.
3. **Host files** (`hosts/<role>-<gpu>.nix`) — import the role configuration + GPU-specific module. Set `system.nixos.distroName`.
4. **`flake.nix` roles table** — maps each role to `{ homeFile, baseModules, extraModules }`. Consumed by `mkHost` (builds nixosConfigurations) and `mkBaseModule` (builds nixosModules exports).
5. **`flake.nix` hostList** — declarative list of `{ name, role, gpu, nvidiaVariant? }` tuples. `mkHost` constructs each system from this list.

### Existing Roles (5)

| Role | Purpose | Imports Count | Has GUI |
|------|---------|---------------|---------|
| `desktop` | Full workstation: gaming, dev, GNOME, Flatpak | 26 modules | Yes |
| `htpc` | Media centre: GNOME, audio, Flatpak, no gaming/dev | ~20 modules | Yes |
| `stateless` | Ephemeral tmpfs root: GNOME, Flatpak, impermanence | ~20 modules | Yes |
| `server` | GUI server: GNOME, Proxmox, Cockpit, ZFS | ~20 modules | Yes |
| `headless-server` | SSH-only server: no GUI, Proxmox, Cockpit, ZFS | 14 modules | No |

### GPU Variant Structure

Each role generates host files for 4 GPU "base" types: `amd`, `nvidia`, `intel`, `vm`. NVIDIA legacy variants (`legacy_535`, `legacy_470`) reuse the `nvidia` host file and pass `nvidiaVariant` to set `vexos.gpu.nvidiaDriverVariant`. This means:

- **4 host files** per role (amd, nvidia, intel, vm)
- **6 hostList entries** per role (amd, nvidia, nvidia-legacy535, nvidia-legacy470, intel, vm)
- NVIDIA legacy variants require the `vexos.gpu.nvidiaDriverVariant` option, which is defined in `modules/gpu/nvidia.nix`

### Module Categories

Modules imported by existing roles fall into these categories:

| Category | Modules | Vanilla? |
|----------|---------|----------|
| **Essential** | `locale.nix`, `users.nix`, `nix.nix` | **Yes** |
| **System/Boot** | `system.nix` (kernel, bootloader, ZRAM, sysctl, swap, btrfs) | **No** — too opinionated |
| **Networking** | `network.nix` (NM, Avahi, firewall, dhcpcd override, fallback profiles) | **No** — too opinionated |
| **Security** | `security.nix` (AppArmor) | **No** — not stock NixOS |
| **GPU** | `gpu.nix`, `gpu/*.nix` | **No** — vanilla uses kernel defaults |
| **Desktop** | `gnome*.nix`, `audio.nix`, `branding*.nix`, `flatpak*.nix` | **No** |
| **Extras** | `gaming.nix`, `development.nix`, `virtualization.nix`, etc. | **No** |
| **Packages** | `packages-common.nix`, `packages-desktop.nix` | **No** |

---

## 2. Problem Definition

There is currently no way to rebuild a vexos-nix machine back to a "stock NixOS" baseline. All five existing roles carry significant opinions (custom kernels, performance tuning, AppArmor, ZRAM, sysctl tweaks, Avahi, custom packages, etc.).

A **vanilla** role is needed for:

1. **System restore** — rebuild to a known-good, minimal NixOS state when diagnosing issues.
2. **Baseline comparison** — compare vanilla behaviour against opinionated roles to isolate which module introduced a regression.
3. **Fresh start** — provide a minimal bootable system that a user can incrementally customize.
4. **Upstream compatibility** — stay as close to `nixos-generate-config` defaults as possible, automatically benefiting from upstream NixOS improvements.

---

## 3. Proposed Solution Architecture

### Design Principles

- **Minimal imports** — only modules that provide essential, non-opinionated configuration.
- **Stock NixOS defaults** — don't override kernel, scheduler, sysctl, swap, ZRAM, firewall, etc. Let NixOS defaults apply.
- **No GPU modules** — stock NixOS handles GPU via kernel defaults (nouveau for NVIDIA, amdgpu auto-loaded for AMD, i915 for Intel). Proprietary drivers are an opinion.
- **No NVIDIA legacy variants** — without proprietary NVIDIA driver modules, the `vexos.gpu.nvidiaDriverVariant` option doesn't exist. Legacy variants are meaningless for stock NixOS.
- **VM exception** — the VM host file includes minimal guest additions inline (QEMU guest agent, SPICE, VirtualBox) since these are infrastructure for the VM to be usable, not an opinion.
- **No branding** — no Plymouth theme, no custom distroName (beyond the host file), no pixmaps.
- **Flake support preserved** — `nix.nix` is imported to enable flakes and binary caches (required since the configuration itself is a flake).

### Files to Create

| File | Purpose |
|------|---------|
| `configuration-vanilla.nix` | Role configuration — minimal imports, inline bootloader + networking |
| `home-vanilla.nix` | Home Manager config — bash, git, justfile |
| `hosts/vanilla-amd.nix` | AMD host file |
| `hosts/vanilla-nvidia.nix` | NVIDIA host file (nouveau) |
| `hosts/vanilla-intel.nix` | Intel host file |
| `hosts/vanilla-vm.nix` | VM host file (with guest additions) |

### Files to Modify

| File | Change |
|------|--------|
| `flake.nix` | Add `vanilla` to `roles` table, add 4 entries to `hostList`, add `vanillaBase` to `nixosModules` |

### Total New hostList Entries: 4

Unlike other roles which have 6 entries (including nvidia-legacy535 and nvidia-legacy470), the vanilla role has only **4 entries** because:
- No proprietary NVIDIA drivers → no `vexos.gpu.nvidiaDriverVariant` option → legacy variants would cause an evaluation error.
- All NVIDIA hardware uses the kernel's built-in nouveau driver in vanilla mode.

---

## 4. Implementation Steps

### 4.1 `configuration-vanilla.nix`

```nix
# configuration-vanilla.nix
# Vanilla role: stock NixOS baseline for system restore.
# Intentionally minimal — mirrors what nixos-generate-config produces.
# Does NOT include: custom kernel, performance tuning, ZRAM, AppArmor,
# desktop environment, audio, gaming, Flatpak, branding, or custom packages.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/locale.nix
    ./modules/users.nix
    ./modules/nix.nix
  ];

  # ---------- Bootloader ----------
  # systemd-boot with EFI — same as nixos-generate-config defaults.
  # lib.mkDefault allows hardware-configuration.nix to override for BIOS/GRUB.
  boot.loader.systemd-boot.enable      = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # ---------- Networking ----------
  networking.hostName = lib.mkDefault "vexos";
  networking.networkmanager.enable = true;

  # ---------- State version ----------
  # Do NOT change after initial install.
  system.stateVersion = "25.11";
}
```

**Rationale for each import:**
- `locale.nix` — timezone and locale (2 lines, uses `mkDefault`, non-opinionated)
- `users.nix` — creates the `nimda` user with `wheel` + `networkmanager` groups (essential for login)
- `nix.nix` — enables flakes, binary caches, store optimisation, GC thresholds (required since this config is itself a flake; also sets `allowUnfree = true` which is needed project-wide)

**What is NOT imported and why:**
- `system.nix` — sets latest kernel, Kyber scheduler, ZRAM, BBR sysctl, swap file, btrfs scrub, performance governor, inotify limits. All are opinions beyond stock NixOS.
- `network.nix` — sets Avahi/mDNS, firewall rules, dhcpcd force-off, wired fallback profiles, systemd-resolved. Stock NixOS only needs `networking.networkmanager.enable = true`.
- `security.nix` — enables AppArmor. Not present in stock NixOS.
- `packages-common.nix` — installs btop, inxi, just, git, curl, wget. Stock NixOS doesn't bundle these.
- `branding.nix` — Plymouth themes, pixmaps, distroName. Not stock.
- `gpu.nix` — VA-API/VDPAU packages, Vulkan tools, ffmpeg. Not stock.

### 4.2 `home-vanilla.nix`

```nix
# home-vanilla.nix
# Home Manager configuration for user "nimda" — Vanilla role.
# Absolute minimum: bash shell and git for managing the flake repo.
{ config, pkgs, lib, inputs, ... }:
{
  imports = [ ./home/bash-common.nix ];

  home.username      = "nimda";
  home.homeDirectory = "/home/nimda";

  # Minimal packages — git is required to manage the flake repository.
  home.packages = with pkgs; [
    git
  ];

  # Deploy the justfile for 'just' commands from home dir.
  home.file."justfile".source = ./justfile;

  home.stateVersion = "24.05";
}
```

**Rationale:**
- `bash-common.nix` — basic shell aliases (`ll`, `..`, tailscale/service shortcuts). Shared by all roles.
- `git` — essential for managing the flake repository itself.
- `justfile` — the project's command runner; enables `just rebuild` etc. from the home directory.
- `home.stateVersion = "24.05"` — matches all other home files in the project.

### 4.3 Host Files

#### `hosts/vanilla-amd.nix`

```nix
# hosts/vanilla-amd.nix
# vexos — Vanilla AMD build (stock NixOS baseline).
# GPU uses kernel amdgpu driver (auto-loaded). No custom GPU configuration.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vanilla-amd
{ lib, ... }:
{
  imports = [
    ../configuration-vanilla.nix
  ];

  system.nixos.distroName = "VexOS Vanilla AMD";
}
```

#### `hosts/vanilla-nvidia.nix`

```nix
# hosts/vanilla-nvidia.nix
# vexos — Vanilla NVIDIA build (stock NixOS baseline).
# GPU uses kernel nouveau driver (open-source). No proprietary NVIDIA drivers.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vanilla-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-vanilla.nix
  ];

  system.nixos.distroName = "VexOS Vanilla NVIDIA";
}
```

#### `hosts/vanilla-intel.nix`

```nix
# hosts/vanilla-intel.nix
# vexos — Vanilla Intel build (stock NixOS baseline).
# GPU uses kernel i915 driver (auto-loaded). No custom GPU configuration.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vanilla-intel
{ lib, ... }:
{
  imports = [
    ../configuration-vanilla.nix
  ];

  system.nixos.distroName = "VexOS Vanilla Intel";
}
```

#### `hosts/vanilla-vm.nix`

```nix
# hosts/vanilla-vm.nix
# vexos — Vanilla VM guest build (stock NixOS baseline).
# Includes minimal guest additions for VM usability (QEMU, SPICE, VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vanilla-vm
{ lib, pkgs, ... }:
{
  imports = [
    ../configuration-vanilla.nix
  ];

  # ── VM guest additions ─────────────────────────────────────────────────────
  # These are infrastructure for the VM to be functional, not an opinion.
  # Without them: no clipboard sync, no display resize, no graceful shutdown.

  # QEMU/KVM guest agent — graceful shutdown, memory ballooning, clock sync
  services.qemuGuest.enable = true;

  # SPICE vdagent — clipboard sync and automatic display resize
  services.spice-vdagentd.enable = true;

  # VirtualBox guest additions — shared folders, clipboard, auto-resize
  virtualisation.virtualbox.guest.enable = true;
  virtualisation.virtualbox.guest.dragAndDrop = true;

  system.nixos.distroName = "VexOS Vanilla VM";
}
```

**Note:** Unlike other roles' VM host files, vanilla-vm does NOT:
- Pin a specific kernel version (uses NixOS default)
- Set `vexos.btrfs.enable = false` (option doesn't exist without `system.nix`)
- Set `vexos.swap.enable = false` (option doesn't exist without `system.nix`)
- Override `services.scx.enable` (not configured)
- Override `powerManagement.cpuFreqGovernor` (uses NixOS default)

### 4.4 `flake.nix` Modifications

#### Add to `roles` table (after the `headless-server` entry):

```nix
      vanilla = {
        homeFile     = ./home-vanilla.nix;
        baseModules  = [];
        extraModules = [];
      };
```

**Rationale for empty `baseModules`:**
- No `unstableOverlayModule` — vanilla doesn't reference `pkgs.unstable.*`
- No `upModule` — vanilla has no GUI (no desktop environment installed)
- No `customPkgsOverlayModule` — vanilla doesn't reference `pkgs.vexos.*`
- No `proxmoxOverlayModule` — vanilla is not a server role

#### Add to `hostList` (after the HTPC block):

```nix
      # Vanilla (stock NixOS baseline — no NVIDIA legacy variants, no proprietary GPU drivers)
      { name = "vexos-vanilla-amd";    role = "vanilla"; gpu = "amd"; }
      { name = "vexos-vanilla-nvidia"; role = "vanilla"; gpu = "nvidia"; }
      { name = "vexos-vanilla-intel";  role = "vanilla"; gpu = "intel"; }
      { name = "vexos-vanilla-vm";     role = "vanilla"; gpu = "vm"; }
```

#### Add to `nixosModules` (after `statelessBase`):

```nix
      # Vanilla stack: stock NixOS baseline. No desktop, no custom GPU,
      # no performance tuning. Suitable for system restore or fresh start.
      vanillaBase = mkBaseModule "vanilla" ./configuration-vanilla.nix;
```

**Note on `mkBaseModule` behaviour for vanilla:**
- `mkBaseModule` unconditionally applies the `unstable` and `customPkgs` overlays. These are harmless for vanilla (they make `pkgs.unstable.*` and `pkgs.vexos.*` available but don't install anything).
- `mkBaseModule` adds the `up` GUI app to `environment.systemPackages` for all non-headless-server roles. For vanilla (no desktop environment), the package will be installed but not visible in any app launcher. This is a minor cosmetic issue.
- **Recommendation:** Update the Up exclusion condition in `mkBaseModule` from `role != "headless-server"` to `!(role == "headless-server" || role == "vanilla")`. This is optional but cleaner.

#### Updated mkBaseModule Up condition (optional):

```nix
      environment.systemPackages =
        lib.optional (role != "headless-server" && role != "vanilla") up.packages.x86_64-linux.default;
```

### 4.5 Total Output Count Update

Current: 30 nixosConfigurations outputs  
After: **34** nixosConfigurations outputs (+4 vanilla)

---

## 5. Complete File List

### Files to Create (6)

1. `configuration-vanilla.nix` — role configuration
2. `home-vanilla.nix` — home-manager configuration
3. `hosts/vanilla-amd.nix` — AMD host file
4. `hosts/vanilla-nvidia.nix` — NVIDIA host file
5. `hosts/vanilla-intel.nix` — Intel host file
6. `hosts/vanilla-vm.nix` — VM host file

### Files to Modify (1)

1. `flake.nix` — add `vanilla` role, 4 hostList entries, `vanillaBase` nixosModule, optionally update Up exclusion

---

## 6. Module Import Comparison

| Module | Desktop | Headless Server | **Vanilla** |
|--------|---------|-----------------|-------------|
| `locale.nix` | ✅ | ✅ | ✅ |
| `users.nix` | ✅ | ✅ | ✅ |
| `nix.nix` | ✅ | ✅ | ✅ |
| `system.nix` | ✅ | ✅ | ❌ |
| `network.nix` | ✅ | ✅ | ❌ |
| `security.nix` | ✅ | ✅ | ❌ |
| `packages-common.nix` | ✅ | ✅ | ❌ |
| `branding.nix` | ✅ | ✅ | ❌ |
| `gpu.nix` | ✅ | ✅ | ❌ |
| `gnome.nix` | ✅ | ❌ | ❌ |
| `audio.nix` | ✅ | ❌ | ❌ |
| `flatpak.nix` | ✅ | ❌ | ❌ |
| `gaming.nix` | ✅ | ❌ | ❌ |
| `development.nix` | ✅ | ❌ | ❌ |
| `virtualization.nix` | ✅ | ❌ | ❌ |

**Vanilla imports 3 modules** — the absolute minimum for a bootable, flake-managed system.

---

## 7. What Vanilla Gets From NixOS Defaults (by NOT importing modules)

By not importing `system.nix`, `network.nix`, `security.nix`, etc., vanilla inherits upstream NixOS defaults:

| Feature | Vanilla (NixOS default) | Desktop (system.nix) |
|---------|------------------------|---------------------|
| Kernel | NixOS default (LTS) | `linuxPackages_latest` |
| I/O scheduler | kernel default (mq-deadline) | Kyber |
| ZRAM | disabled | enabled (lz4, 50%) |
| Swap | none (unless hardware-config sets one) | 8 GiB swap file |
| TCP congestion | cubic (kernel default) | BBR |
| CPU governor | NixOS default (ondemand) | schedutil |
| Swappiness | 60 (kernel default) | 10 |
| inotify watches | 65536 (kernel default) | 524288 |
| AppArmor | disabled | enabled |
| Avahi/mDNS | disabled | enabled |
| Firewall | NixOS default (enabled, no extra rules) | custom rules |
| Plymouth | disabled | enabled (themed) |
| Btrfs scrub | disabled | auto-monthly |

This is the desired behaviour: vanilla stays current with upstream defaults automatically.

---

## 8. Risks and Mitigations

### Risk 1: No Network After Rebuild
**Risk:** Switching from a full role to vanilla removes `network.nix`'s dhcpcd force-off and wired fallback profile. If the machine relied on those, network may break.  
**Mitigation:** Vanilla sets `networking.networkmanager.enable = true` which is sufficient for DHCP on most networks. For static IP setups, the user should configure NetworkManager manually or via `nmcli` before rebuilding.

### Risk 2: NVIDIA GPU May Be Unusable
**Risk:** Vanilla uses the kernel's nouveau driver instead of NVIDIA proprietary. Nouveau has limited support for newer GPUs (RTX 30xx+ may not display at all).  
**Mitigation:** This is intentional — vanilla is stock NixOS. Users with NVIDIA GPUs who need display output should rebuild to a full role. Document this in the host file comments. For system restore, SSH access is sufficient even without display.

### Risk 3: No NVIDIA Legacy Variants
**Risk:** Users may expect `vexos-vanilla-nvidia-legacy535` to exist.  
**Mitigation:** Document that vanilla has no proprietary GPU drivers, so legacy variants are not applicable. Only 4 vanilla outputs exist.

### Risk 4: `vexos.btrfs.enable` / `vexos.swap.enable` Options Missing
**Risk:** `modules/gpu/vm.nix` in other roles sets `vexos.btrfs.enable = false` and `vexos.swap.enable = false`. These options are defined in `system.nix`. Since vanilla doesn't import `system.nix`, these options don't exist. The vanilla VM host file must NOT reference them.  
**Mitigation:** The vanilla VM host file (`hosts/vanilla-vm.nix`) is written from scratch with only VM guest additions. It does not import `modules/gpu/vm.nix`.

### Risk 5: `mkBaseModule` Adds Up GUI App
**Risk:** `mkBaseModule` adds the `up` GUI app to vanilla's systemPackages even though vanilla has no desktop environment.  
**Mitigation:** The package is installed but harmless (no launcher to surface it). Optionally, update the Up exclusion condition to also exclude vanilla. This is a minor cosmetic issue.

### Risk 6: Empty `baseModules` Means No Overlays in Direct Builds
**Risk:** With `baseModules = []`, the direct `mkHost` builds for vanilla won't have the `unstable` overlay. If any imported module accidentally references `pkgs.unstable.*`, the build fails.  
**Mitigation:** The 3 modules vanilla imports (`locale.nix`, `users.nix`, `nix.nix`) do not reference `pkgs.unstable`. This has been verified. The `mkBaseModule`-generated `vanillaBase` nixosModule does get the overlay (mkBaseModule applies it unconditionally), so the /etc/nixos/flake.nix pathway is safe.

### Risk 7: `nix.nix` Sets `allowUnfree = true`
**Risk:** Stock NixOS does not allow unfree packages by default. `nix.nix` sets `nixpkgs.config.allowUnfree = true`.  
**Mitigation:** This is intentional and necessary. The vanilla role may be deployed on hardware that previously used proprietary drivers (NVIDIA), and `allowUnfree` prevents evaluation errors during transition. It also maintains consistency with all other roles. The setting does not install any unfree packages — it only permits them.

---

## 9. Validation Checklist

After implementation, verify:

- [ ] `nix flake check` passes
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-vanilla-amd` succeeds
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-vanilla-nvidia` succeeds
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-vanilla-intel` succeeds
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-vanilla-vm` succeeds
- [ ] No `vexos-vanilla-nvidia-legacy*` entries exist in hostList
- [ ] `configuration-vanilla.nix` imports exactly 3 modules
- [ ] `home-vanilla.nix` sets `home.stateVersion = "24.05"`
- [ ] `system.stateVersion` in `configuration-vanilla.nix` is `"25.11"`
- [ ] No `lib.mkIf` guards in any new file
- [ ] `hardware-configuration.nix` is NOT tracked in git
- [ ] Total nixosConfigurations count is 34 (30 existing + 4 vanilla)
