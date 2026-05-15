# Research Spec: ZFS hostId Warning & Vanilla Flake Outputs

**Generated:** 2026-05-15  
**Author:** Research Subagent  
**Spec path:** `.github/docs/subagent_docs/zfs-vanilla-fix_spec.md`

---

## Summary

Two potential issues were investigated:

1. **Issue 1 — ZFS `networking.hostId` warning:** Exists and fires correctly for server and headless-server roles. `configuration-vanilla.nix` does NOT import `zfs-server.nix` — vanilla is clean. The warning uses `warnings = lib.optionals (...)` (NOT `assertions`). No structural fix is needed to the module. The only real action is to ensure host files for server/headless-server roles that have been deployed with ZFS pools set a real `networking.hostId` value.

2. **Issue 2 — `vexos-vanilla-vm` missing from flake outputs:** **Already resolved.** The `vanilla` role is fully present in both `roles` table and `hostList` in `flake.nix`. All four GPU variant host files exist. The justfile `switch` recipe includes vanilla. **No implementation work is needed for Issue 2.**

---

## Issue 1 Findings: ZFS `networking.hostId` Warning

### 1.1 Full content of `modules/zfs-server.nix` (verbatim relevant sections)

```nix
# modules/zfs-server.nix
# ZFS support for server roles — required for proxmox-nixos VM storage.
# …
# Per the Option B module pattern:
#   imported ONLY by configuration-server.nix and configuration-headless-server.nix.
{ config, lib, pkgs, ... }:
{
  # ── Kernel + userland ──
  boot.supportedFilesystems        = [ "zfs" ];
  boot.zfs.forceImportRoot         = false;
  boot.zfs.forceImportAll          = false;

  # ── Kernel pinning for ZFS compatibility ──
  boot.kernelPackages = lib.mkOverride 75 pkgs.linuxPackages;

  boot.zfs.extraPools              = [ ];
  services.zfs.autoScrub.enable    = true;
  services.zfs.autoScrub.interval  = "monthly";
  services.zfs.trim.enable         = true;
  services.zfs.trim.interval       = "weekly";

  # ── Userland tools ──
  environment.systemPackages = with pkgs; [
    zfs gptfdisk util-linux pciutils
  ];

  # ── networking.hostId ──
  networking.hostId = lib.mkDefault "00000000";

  vexos.swap.enable = lib.mkDefault false;

  # Warn (not assert) so fresh installs that haven't yet created any ZFS pools
  # can still complete their first build.
  warnings = lib.optionals (config.networking.hostId == "00000000") [
    ''
      ZFS: networking.hostId is still set to the placeholder "00000000".
      This is fine for a fresh install, but you MUST set a real value before
      creating any ZFS pools (just create-zfs-pool / zpool create).
      Add to /etc/nixos/hardware-configuration.nix (or a local override):
        networking.hostId = "deadbeef";   # replace with real value
      Generate: head -c 8 /etc/machine-id
    ''
  ];
}
```

### 1.2 Key finding: `warnings` not `assertions`

The module uses **`warnings`** (build succeeds with a printed message), NOT **`assertions`** (which would fail the build). This is intentional and correct.

### 1.3 Which `configuration-*.nix` files import `zfs-server.nix`

| Config file | Imports `./modules/zfs-server.nix` |
|---|---|
| `configuration-server.nix` | **YES** (line: `./modules/zfs-server.nix`) |
| `configuration-headless-server.nix` | **YES** (line: `./modules/zfs-server.nix`) |
| `configuration-desktop.nix` | No |
| `configuration-htpc.nix` | No |
| `configuration-stateless.nix` | No |
| `configuration-vanilla.nix` | **No** |

Verbatim from `configuration-server.nix`:
```nix
imports = [
  ./modules/gnome.nix
  ./modules/gnome-server.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/branding.nix
  ./modules/branding-display.nix
  ./modules/flatpak.nix
  ./modules/network.nix
  ./modules/network-desktop.nix
  ./modules/packages-common.nix
  ./modules/packages-desktop.nix
  ./modules/system.nix
  ./modules/system-nosleep.nix
  ./modules/security.nix
  ./modules/security-server.nix
  ./modules/server
  ./modules/zfs-server.nix         # ← ZFS imported here
  ./modules/nix.nix
  ./modules/nix-server.nix
  ./modules/locale.nix
  ./modules/users.nix
  ./modules/asus-opt.nix
];
```

Verbatim from `configuration-headless-server.nix`:
```nix
imports = [
  ./modules/gpu.nix
  ./modules/branding.nix
  ./modules/network.nix
  ./modules/packages-common.nix
  ./modules/system.nix
  ./modules/system-nosleep.nix
  ./modules/security.nix
  ./modules/security-server.nix
  ./modules/server
  ./modules/zfs-server.nix         # ← ZFS imported here
  ./modules/nix.nix
  ./modules/nix-server.nix
  ./modules/locale.nix
  ./modules/users.nix
  ./modules/asus-opt.nix
];
```

### 1.4 Does `configuration-vanilla.nix` import `zfs-server.nix`?

**No.** Full import list of `configuration-vanilla.nix`:

```nix
imports = [
  ./modules/locale.nix
  ./modules/users.nix
  ./modules/nix.nix
  ./modules/asus-opt.nix
];
```

`zfs-server.nix` is not present. The vanilla role has no ZFS configuration whatsoever.

### 1.5 Root cause of the warning and when it fires

The warning fires when **all** of these are true simultaneously:

1. The host's active configuration imports `zfs-server.nix` (i.e., it's a server or headless-server role), AND
2. `config.networking.hostId` evaluates to exactly `"00000000"` (the `lib.mkDefault` placeholder), meaning no host file, hardware-configuration.nix, or local override has set a real value.

**The warning does NOT fire for:**
- desktop, htpc, stateless, or vanilla roles (they never import `zfs-server.nix`)
- server/headless-server hosts where the host file or `hardware-configuration.nix` sets a real `networking.hostId`

**The warning DOES fire for:**
- Any `vexos-server-*` or `vexos-headless-server-*` build where `networking.hostId` is still the placeholder `"00000000"` (typical on a fresh deploy that hasn't yet run `just create-zfs-pool`)

### 1.6 Should the warning be gated behind `config.services.zfs.enabled`?

NixOS has no single `services.zfs.enable` toggle. The ZFS NixOS module activates when `"zfs"` appears in `boot.supportedFilesystems`, which `zfs-server.nix` unconditionally sets. Therefore any gate on `boot.supportedFilesystems` would always be `true` for any host importing this module — making it equivalent to no gate.

**Recommended action:** No change to the warning logic is required. The current design is correct:
- The warning exists as a non-blocking reminder to set `networking.hostId` before creating pools.
- It is already correctly scoped to server roles by being in a server-only module.
- The placeholder `lib.mkDefault "00000000"` with a `warnings` guard is the documented NixOS pattern for this scenario.
- Each `hosts/server-*.nix` and `hosts/headless-server-*.nix` file that is deployed to a real machine with ZFS pools MUST set `networking.hostId = "XXXXXXXX"` to suppress the warning. This should be done in `hardware-configuration.nix` or the host file.

---

## Issue 2 Findings: `vexos-vanilla-vm` in Flake Outputs

### 2.1 Current flake.nix `roles` table (verbatim)

```nix
roles = {
  desktop = {
    homeFile     = ./home-desktop.nix;
    baseModules  = [ unstableOverlayModule upModule customPkgsOverlayModule ];
    extraModules = [];
  };
  htpc = {
    homeFile     = ./home-htpc.nix;
    baseModules  = [ unstableOverlayModule upModule customPkgsOverlayModule ];
    extraModules = [];
  };
  stateless = {
    homeFile     = ./home-stateless.nix;
    baseModules  = [ unstableOverlayModule upModule customPkgsOverlayModule ];
    extraModules = [ impermanence.nixosModules.impermanence ];
  };
  server = {
    homeFile     = ./home-server.nix;
    baseModules  = [ unstableOverlayModule upModule proxmoxOverlayModule customPkgsOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
    extraModules = serverServicesModule;
  };
  headless-server = {
    homeFile     = ./home-headless-server.nix;
    baseModules  = [ unstableOverlayModule proxmoxOverlayModule customPkgsOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
    extraModules = serverServicesModule;
  };
  vanilla = {
    homeFile     = ./home-vanilla.nix;
    baseModules  = [];
    extraModules = [];
  };
};
```

**Finding: `vanilla` is present in the `roles` table.**

### 2.2 Vanilla entries in `hostList` (verbatim)

```nix
# Vanilla (stock NixOS baseline — no NVIDIA legacy variants, no proprietary GPU drivers)
{ name = "vexos-vanilla-amd";    role = "vanilla"; gpu = "amd"; }
{ name = "vexos-vanilla-nvidia"; role = "vanilla"; gpu = "nvidia"; }
{ name = "vexos-vanilla-intel";  role = "vanilla"; gpu = "intel"; }
{ name = "vexos-vanilla-vm";     role = "vanilla"; gpu = "vm"; }
```

**Finding: All four GPU variants, including `vexos-vanilla-vm`, are present in `hostList`.** The comment in `flake.nix` states: `# 34 outputs total: 30 historical + 4 vanilla role`.

### 2.3 Vanilla host files (all four exist)

| File | Exists | Notes |
|---|---|---|
| `hosts/vanilla-amd.nix` | Yes | Imports `../configuration-vanilla.nix`; sets distroName |
| `hosts/vanilla-nvidia.nix` | Yes | Imports `../configuration-vanilla.nix`; sets distroName |
| `hosts/vanilla-intel.nix` | Yes | Imports `../configuration-vanilla.nix`; sets distroName |
| `hosts/vanilla-vm.nix` | Yes | Imports `../configuration-vanilla.nix`; adds QEMU/SPICE/VBox guest additions |

### 2.4 `configuration-vanilla.nix` (full content)

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
    ./modules/asus-opt.nix
  ];

  # ---------- Bootloader ----------
  boot.loader.systemd-boot.enable      = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # ---------- Networking ----------
  networking.hostName = lib.mkDefault "vexos";
  networking.networkmanager.enable = true;

  # ---------- State version ----------
  system.stateVersion = "25.11";
}
```

### 2.5 `home-vanilla.nix` (full content)

```nix
# home-vanilla.nix
# Home Manager configuration for user "nimda" — Vanilla role.
# Absolute minimum: bash shell and git for managing the flake repo.
{ config, pkgs, lib, inputs, osConfig, ... }:
{
  imports = [ ./home/bash-common.nix ];

  home.username      = osConfig.vexos.user.name;
  home.homeDirectory = "/home/${osConfig.vexos.user.name}";

  home.packages = with pkgs; [
    git
    just
  ];

  home.file."justfile".source = ./justfile;

  home.stateVersion = "24.05";
}
```

### 2.6 Justfile vanilla support

The `switch` recipe in `justfile` already includes vanilla at choice `6`:

```bash
echo "  1) desktop"
echo "  2) stateless"
echo "  3) htpc"
echo "  4) server"
echo "  5) headless-server"
echo "  6) vanilla"

# ...
case "${INPUT,,}" in
    1|desktop)         ROLE="desktop"         ;;
    2|stateless)       ROLE="stateless"       ;;
    3|htpc)            ROLE="htpc"            ;;
    4|server)          ROLE="server"          ;;
    5|headless-server) ROLE="headless-server" ;;
    6|vanilla)         ROLE="vanilla"         ;;
```

**Note:** The `update` recipe does NOT include vanilla in its fallback interactive prompt (only shows 1-5). This is a minor gap in the justfile — the `update` recipe's role selection would not offer vanilla as an option if `/etc/nixos/vexos-variant` is absent. However, `update` typically reads the variant from `/etc/nixos/vexos-variant`, so this is a low-priority cosmetic gap.

### 2.7 `mkBaseModule` vanilla exclusion (verbatim)

In `flake.nix`, `mkBaseModule` correctly excludes the `up` GUI app for vanilla:

```nix
environment.systemPackages =
  lib.optional (role != "headless-server" && role != "vanilla") up.packages.x86_64-linux.default;
```

### 2.8 Conclusion for Issue 2

**`vexos-vanilla-vm` is NOT missing from flake outputs.** It is fully present:
- In `roles` table ✓
- In `hostList` (all 4 GPU variants) ✓
- Host files exist for all 4 GPU variants ✓
- `configuration-vanilla.nix` exists ✓
- `home-vanilla.nix` exists ✓
- `justfile switch` recipe includes vanilla ✓
- `nixosModules.vanillaBase` export exists ✓

The only gap is the `update` recipe's fallback prompt (1-5 only, missing vanilla as option 6). This is cosmetic and low-priority.

---

## Recommended Implementation Actions

### Issue 1: No module changes required

The ZFS warning mechanism is correct and intentionally scoped. The only actionable improvement:

- Each deployed `hosts/server-*.nix` or `hosts/headless-server-*.nix` that has real ZFS pools should set:
  ```nix
  networking.hostId = "XXXXXXXX";  # generate: head -c 8 /etc/machine-id
  ```
  This suppresses the warning on that specific host.

No changes to `modules/zfs-server.nix` are needed.

### Issue 2: Minor justfile gap only

The `update` recipe's fallback interactive role prompt lists options 1-5 (desktop/stateless/htpc/server/headless-server) but is missing option 6 (vanilla). If vanilla needs to be supported in `just update` fallback mode, add:

```bash
# In the update recipe fallback prompt, add:
echo "  6) vanilla"
# ...
6|vanilla)  ROLE="vanilla"  ;;
```

This is a cosmetic fix and low priority. The `just switch` recipe already has vanilla at option 6.

---

## Files Read During Research

- `modules/zfs-server.nix` — full content
- `configuration-server.nix` — full content
- `configuration-headless-server.nix` — full content
- `configuration-vanilla.nix` — full content
- `flake.nix` — full content (roles table, hostList, mkBaseModule, nixosModules)
- `justfile` — full content (switch recipe, update recipe)
- `hosts/vanilla-amd.nix` — full content
- `hosts/vanilla-nvidia.nix` — full content
- `hosts/vanilla-intel.nix` — full content
- `hosts/vanilla-vm.nix` — full content
- `home-vanilla.nix` — full content
