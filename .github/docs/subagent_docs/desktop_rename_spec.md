# Desktop Rename Specification

**Feature:** Rename flake output variants from `vexos-{gpu}` to `vexos-desktop-{gpu}`  
**Date:** 2026-04-06  
**Status:** Draft  

---

## 1. Current State Analysis

The vexos-nix flake currently defines four `nixosConfigurations` outputs:

| Current Name    | Host File          | Hostname Used                       |
|-----------------|--------------------|-------------------------------------|
| `vexos-amd`     | `hosts/amd.nix`    | `"vexos"` (from `configuration.nix` mkDefault) |
| `vexos-nvidia`  | `hosts/nvidia.nix`  | `"vexos"` (from `configuration.nix` mkDefault) |
| `vexos-intel`   | `hosts/intel.nix`   | `"vexos"` (from `configuration.nix` mkDefault) |
| `vexos-vm`      | `hosts/vm.nix`      | `"vexos-vm"` (explicit override)    |

### Where variant names appear (exhaustive)

#### Source files requiring modification:

| File | Lines | Context |
|------|-------|---------|
| `flake.nix` | 78–79 | `nixosConfigurations.vexos-amd` attribute + comment |
| `flake.nix` | 86–87 | `nixosConfigurations.vexos-nvidia` attribute + comment |
| `flake.nix` | 94–95 | `nixosConfigurations.vexos-vm` attribute + comment |
| `flake.nix` | 102–103 | `nixosConfigurations.vexos-intel` attribute + comment |
| `hosts/amd.nix` | 2–3 | Comment: `vexos — AMD GPU system build` + rebuild command |
| `hosts/nvidia.nix` | 2–3 | Comment: `vexos — NVIDIA GPU system build` + rebuild command |
| `hosts/vm.nix` | 2–3 | Comment: `vexos — Virtual machine guest build` + rebuild command |
| `hosts/vm.nix` | 24 | `networking.hostName = "vexos-vm";` |
| `hosts/intel.nix` | 2–3 | Comment: `vexos — Intel GPU system build` + rebuild command |
| `configuration.nix` | 25 | `networking.hostName = lib.mkDefault "vexos";` — default hostname for all non-VM variants |
| `scripts/preflight.sh` | 63 | `for TARGET in vexos-amd vexos-nvidia vexos-vm vexos-intel;` (nixos-rebuild loop) |
| `scripts/preflight.sh` | 75 | `for TARGET in vexos-amd vexos-nvidia vexos-vm vexos-intel;` (nix build --dry-run fallback loop) |
| `template/etc-nixos-flake.nix` | 12–15 | Comments: rebuild commands for all four variants |
| `template/etc-nixos-flake.nix` | 32 | Comment: first-build example `#vexos-amd` |
| `template/etc-nixos-flake.nix` | 101–104 | `nixosConfigurations` attribute set: `vexos-amd`, `vexos-nvidia`, `vexos-intel`, `vexos-vm` + `mkVariant` string args |
| `README.md` | 32–35 | First-build commands |
| `README.md` | 46 | Example content of `vexos-variant` file (`vexos-amd`) |
| `README.md` | 52–55 | Variants table |
| `README.md` | 75 | Migration example (`#vexos-vm`) |
| `README.md` | 81 | Notes rebuild command (`#vexos-vm`) |
| `.github/copilot-instructions.md` | 69–71 | Build commands |
| `.github/copilot-instructions.md` | 75–77 | Test (dry-build) commands |
| `.github/copilot-instructions.md` | 88 | "The flake defines three outputs: `vexos-amd`, `vexos-nvidia`, `vexos-vm`" |
| `.github/copilot-instructions.md` | 93 | "All rebuild commands must target one of `.#vexos-amd`, `.#vexos-nvidia`, or `.#vexos-vm`" |
| `.github/copilot-instructions.md` | 439–441 | Review validation dry-build commands |
| `.github/copilot-instructions.md` | 574–576 | Preflight dry-build commands |

#### Documentation-only files (subagent docs — NOT modified):

Previous subagent review/spec documents in `.github/docs/subagent_docs/` reference old names but are historical records and **must NOT be modified**.

---

## 2. Problem Definition

The current naming scheme (`vexos-{gpu}`) is flat and does not accommodate future system roles. The project plans to add HTPC and server configurations, which need a consistent naming scheme: `vexos-{role}-{gpu}`.

Renaming the existing desktop variants to `vexos-desktop-{gpu}` now establishes the `vexos-{role}-{gpu}` convention before any downstream tooling (like `vexos-updater` or user machines) relies on the flat names at scale.

---

## 3. Proposed Solution

Rename all four flake output variants:

| Old Name        | New Name                |
|-----------------|-------------------------|
| `vexos-amd`     | `vexos-desktop-amd`     |
| `vexos-nvidia`  | `vexos-desktop-nvidia`  |
| `vexos-intel`   | `vexos-desktop-intel`   |
| `vexos-vm`      | `vexos-desktop-vm`      |

Additionally:

- **Default hostname** in `configuration.nix`: `"vexos"` → `"vexos-desktop"` (a sensible default for all desktop variants)
- **VM hostname** in `hosts/vm.nix`: `"vexos-vm"` → `"vexos-desktop-vm"`

The `vexos-variant` file mechanism in `template/etc-nixos-flake.nix` does not need structural changes — the `mkVariant` function already writes whatever string is passed. The strings passed to it change.

No new dependencies are introduced. This is a pure internal rename.

---

## 4. File-by-File Implementation Steps

### 4.1 `flake.nix`

**Line 78–79** — AMD configuration attribute + comment:
```
# Before:
    # sudo nixos-rebuild switch --flake .#vexos-amd
    nixosConfigurations.vexos-amd = nixpkgs.lib.nixosSystem {

# After:
    # sudo nixos-rebuild switch --flake .#vexos-desktop-amd
    nixosConfigurations.vexos-desktop-amd = nixpkgs.lib.nixosSystem {
```

**Line 85 (comment) + line 86–87** — NVIDIA:
```
# Before:
    # ── NVIDIA GPU build ─────────────────────────────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-nvidia
    nixosConfigurations.vexos-nvidia = nixpkgs.lib.nixosSystem {

# After:
    # ── NVIDIA GPU build ─────────────────────────────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia
    nixosConfigurations.vexos-desktop-nvidia = nixpkgs.lib.nixosSystem {
```

**Line 93 (comment) + line 94–95** — VM:
```
# Before:
    # ── VM guest build (QEMU/KVM + VirtualBox) ───────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-vm
    nixosConfigurations.vexos-vm = nixpkgs.lib.nixosSystem {

# After:
    # ── VM guest build (QEMU/KVM + VirtualBox) ───────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-desktop-vm
    nixosConfigurations.vexos-desktop-vm = nixpkgs.lib.nixosSystem {
```

**Line 101 (comment) + line 102–103** — Intel:
```
# Before:
    # ── Intel GPU build ──────────────────────────────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-intel
    nixosConfigurations.vexos-intel = nixpkgs.lib.nixosSystem {

# After:
    # ── Intel GPU build ──────────────────────────────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-desktop-intel
    nixosConfigurations.vexos-desktop-intel = nixpkgs.lib.nixosSystem {
```

### 4.2 `hosts/amd.nix`

**Lines 2–3** — Comment header:
```
# Before:
# hosts/amd.nix
# vexos — AMD GPU system build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-amd

# After:
# hosts/amd.nix
# vexos — AMD GPU desktop build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-amd
```

### 4.3 `hosts/nvidia.nix`

**Lines 2–3** — Comment header:
```
# Before:
# hosts/nvidia.nix
# vexos — NVIDIA GPU system build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-nvidia

# After:
# hosts/nvidia.nix
# vexos — NVIDIA GPU desktop build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia
```

### 4.4 `hosts/vm.nix`

**Lines 2–3** — Comment header:
```
# Before:
# vexos — Virtual machine guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vm

# After:
# vexos — Virtual machine guest desktop build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-vm
```

**Line 24** — Hostname:
```
# Before:
  networking.hostName = "vexos-vm";

# After:
  networking.hostName = "vexos-desktop-vm";
```

### 4.5 `hosts/intel.nix`

**Lines 2–3** — Comment header:
```
# Before:
# hosts/intel.nix
# vexos — Intel GPU system build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-intel

# After:
# hosts/intel.nix
# vexos — Intel GPU desktop build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-intel
```

### 4.6 `configuration.nix`

**Line 25** — Default hostname:
```
# Before:
  networking.hostName = lib.mkDefault "vexos";

# After:
  networking.hostName = lib.mkDefault "vexos-desktop";
```

### 4.7 `scripts/preflight.sh`

**Line 63** — nixos-rebuild dry-build loop:
```
# Before:
  for TARGET in vexos-amd vexos-nvidia vexos-vm vexos-intel; do

# After:
  for TARGET in vexos-desktop-amd vexos-desktop-nvidia vexos-desktop-vm vexos-desktop-intel; do
```

**Line 75** — nix build --dry-run fallback loop:
```
# Before:
  for TARGET in vexos-amd vexos-nvidia vexos-vm vexos-intel; do

# After:
  for TARGET in vexos-desktop-amd vexos-desktop-nvidia vexos-desktop-vm vexos-desktop-intel; do
```

### 4.8 `template/etc-nixos-flake.nix`

**Lines 12–15** — Comment block (first-build instructions):
```
# Before:
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm

# After:
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-vm
```

**Line 32** — Comment (first-build example):
```
# Before:
#     sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd

# After:
#     sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-amd
```

**Lines 101–104** — nixosConfigurations attribute set:
```
# Before:
      vexos-amd    = mkVariant "vexos-amd"    vexos-nix.nixosModules.gpuAmd;
      vexos-nvidia = mkVariant "vexos-nvidia" vexos-nix.nixosModules.gpuNvidia;
      vexos-intel  = mkVariant "vexos-intel"  vexos-nix.nixosModules.gpuIntel;
      vexos-vm     = mkVariant "vexos-vm"     vexos-nix.nixosModules.gpuVm;

# After:
      vexos-desktop-amd    = mkVariant "vexos-desktop-amd"    vexos-nix.nixosModules.gpuAmd;
      vexos-desktop-nvidia = mkVariant "vexos-desktop-nvidia" vexos-nix.nixosModules.gpuNvidia;
      vexos-desktop-intel  = mkVariant "vexos-desktop-intel"  vexos-nix.nixosModules.gpuIntel;
      vexos-desktop-vm     = mkVariant "vexos-desktop-vm"     vexos-nix.nixosModules.gpuVm;
```

### 4.9 `README.md`

**Lines 32–35** — First-build commands:
```
# Before:
sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd     # AMD GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-nvidia  # NVIDIA GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-intel   # Intel GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm      # VM (QEMU / VirtualBox)

# After:
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-amd     # AMD GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia  # NVIDIA GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-intel   # Intel GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-vm      # VM (QEMU / VirtualBox)
```

**Line 46** — Example `vexos-variant` content:
```
# Before:
(a one-word file, e.g. `vexos-amd`)

# After:
(a one-word file, e.g. `vexos-desktop-amd`)
```

**Lines 52–55** — Variants table:
```
# Before:
| `vexos-amd` | AMD GPU (RADV, ROCm, LACT) |
| `vexos-nvidia` | NVIDIA GPU (proprietary, open kernel modules) |
| `vexos-intel` | Intel iGPU or Arc dGPU |
| `vexos-vm` | QEMU/KVM or VirtualBox guest |

# After:
| `vexos-desktop-amd` | AMD GPU (RADV, ROCm, LACT) |
| `vexos-desktop-nvidia` | NVIDIA GPU (proprietary, open kernel modules) |
| `vexos-desktop-intel` | Intel iGPU or Arc dGPU |
| `vexos-desktop-vm` | QEMU/KVM or VirtualBox guest |
```

**Line 75** — Migration example:
```
# Before:
(e.g. `#vexos-vm`)

# After:
(e.g. `#vexos-desktop-vm`)
```

**Line 81** — Notes command:
```
# Before:
sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm

# After:
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-vm
```

### 4.10 `.github/copilot-instructions.md`

**Lines 69–71** — Build commands:
```
# Before:
- `sudo nixos-rebuild switch --flake .#vexos-amd` (AMD GPU)  
- `sudo nixos-rebuild switch --flake .#vexos-nvidia` (NVIDIA GPU)  
- `sudo nixos-rebuild switch --flake .#vexos-vm` (VM guest)  

# After:
- `sudo nixos-rebuild switch --flake .#vexos-desktop-amd` (AMD GPU)  
- `sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia` (NVIDIA GPU)  
- `sudo nixos-rebuild switch --flake .#vexos-desktop-vm` (VM guest)  
```

**Lines 75–77** — Test (dry-build) commands:
```
# Before:
- `sudo nixos-rebuild dry-build --flake .#vexos-amd`  
- `sudo nixos-rebuild dry-build --flake .#vexos-nvidia`  
- `sudo nixos-rebuild dry-build --flake .#vexos-vm`  

# After:
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`  
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`  
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`  
```

**Line 88** — Flake outputs description:
```
# Before:
  - The flake defines three outputs: `vexos-amd`, `vexos-nvidia`, `vexos-vm`  

# After:
  - The flake defines four outputs: `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-intel`, `vexos-desktop-vm`  
```

**Line 93** — Rebuild target constraint:
```
# Before:
  - All rebuild commands must target one of `.#vexos-amd`, `.#vexos-nvidia`, or `.#vexos-vm`  

# After:
  - All rebuild commands must target one of `.#vexos-desktop-amd`, `.#vexos-desktop-nvidia`, `.#vexos-desktop-intel`, or `.#vexos-desktop-vm`  
```

**Lines 439–441** — Review validation dry-build:
```
# Before:
- Run `sudo nixos-rebuild dry-build --flake .#vexos-amd` to verify the AMD system closure builds
- Run `sudo nixos-rebuild dry-build --flake .#vexos-nvidia` to verify the NVIDIA system closure builds
- Run `sudo nixos-rebuild dry-build --flake .#vexos-vm` to verify the VM system closure builds

# After:
- Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` to verify the AMD system closure builds
- Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` to verify the NVIDIA system closure builds
- Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` to verify the VM system closure builds
```

**Lines 574–576** — Preflight dry-build commands:
```
# Before:
     - `sudo nixos-rebuild dry-build --flake .#vexos-amd`
     - `sudo nixos-rebuild dry-build --flake .#vexos-nvidia`
     - `sudo nixos-rebuild dry-build --flake .#vexos-vm`

# After:
     - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
     - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
     - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
```

---

## 5. Files NOT Modified

| File/Path | Reason |
|-----------|--------|
| `hardware-configuration.nix` | Not in repo; generated per-host at `/etc/nixos/` |
| `configuration.nix` `system.stateVersion` | Must NEVER be changed after initial install |
| `modules/branding.nix` | No variant name references |
| `modules/system.nix` | No variant name references |
| `modules/gpu.nix` | No variant name references |
| `modules/gpu/{amd,nvidia,intel,vm}.nix` | No variant name references |
| `home.nix` | No variant name references |
| `.github/docs/subagent_docs/*.md` (existing) | Historical records — not updated |
| `flake.nix` `nixosModules` block | Module names (`gpuAmd`, `gpuNvidia`, etc.) are not variant names — they remain unchanged |

---

## 6. Dependencies

None. This is a pure internal rename with no new external dependencies.

---

## 7. Risks and Mitigations

### 7.1 Existing deployed machines with old variant names

**Risk:** Machines currently deployed with `/etc/nixos/flake.nix` referencing `vexos-amd` (etc.) will break on `nix flake update` because the old attribute names no longer exist.

**Mitigation:**
- Users must update their local `/etc/nixos/flake.nix` to use the new names (`vexos-desktop-amd` etc.) at the same time they update.
- The `README.md` should mention this in the "Existing installs" migration section.
- The `/etc/nixos/vexos-variant` file on deployed hosts will contain the old name (`vexos-amd`); users must rebuild with the new target once (e.g. `--flake /etc/nixos#vexos-desktop-amd`) to update it.

### 7.2 Hostname change on running systems

**Risk:** Changing `networking.hostName` from `"vexos"` to `"vexos-desktop"` (or `"vexos-vm"` to `"vexos-desktop-vm"`) affects:
- mDNS/Avahi advertisements
- Tailscale device name
- SSH known hosts
- Samba shares
- Any service that keys on hostname

**Mitigation:**
- This is expected and intentional.
- Document in the README that the hostname will change after rebuild.
- Users who prefer the old hostname can override via `networking.hostName` in their local `/etc/nixos/flake.nix`.

### 7.3 `vexos-updater` tool compatibility

**Risk:** The `vexos-updater` app reads `/etc/nixos/vexos-variant` to determine the rebuild target. After renaming, the old file content (`vexos-amd`) won't match any flake output.

**Mitigation:** Users must rebuild once with the explicit new target. The `mkVariant` function writes the new name automatically to `/etc/nixos/vexos-variant`.

### 7.4 Stale copilot-instructions.md references

**Risk:** The `.github/copilot-instructions.md` still references only three outputs (omitting `vexos-intel`). After this rename, all four outputs are listed consistently.

**Mitigation:** The spec includes updating the text to reference all four desktop outputs.

---

## 8. Summary of ALL Files Requiring Modification

1. `flake.nix`
2. `hosts/amd.nix`
3. `hosts/nvidia.nix`
4. `hosts/vm.nix`
5. `hosts/intel.nix`
6. `configuration.nix`
7. `scripts/preflight.sh`
8. `template/etc-nixos-flake.nix`
9. `README.md`
10. `.github/copilot-instructions.md`
