# Specification: NVIDIA Legacy Driver Support
**Feature Name:** `nvidia_legacy_drivers`
**Spec File:** `.github/docs/subagent_docs/nvidia_legacy_drivers_spec.md`
**Date:** 2026-04-02
**Status:** Ready for Implementation

---

## 1. Current State Analysis

### File: `modules/gpu/nvidia.nix`

```nix
{ config, pkgs, lib, ... }:
{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    open = true;                          # ← HARDCODED — Turing+ (RTX 20xx / GTX 16xx) only
    modesetting.enable = true;
    powerManagement = {
      enable = false;
      finegrained = false;
    };
    package = config.boot.kernelPackages.nvidiaPackages.stable;  # ← HARDCODED stable only
  };

  hardware.graphics.extraPackages = with pkgs; [
    nvidia-vaapi-driver               # ← Turing+ only; broken on older cards
  ];
}
```

**What is correct:**
- `services.xserver.videoDrivers = [ "nvidia" ]` — correct for all NVIDIA proprietary driver configs.
- `hardware.nvidia.modesetting.enable = true` — correct; required for Wayland on all NVIDIA cards.
- Power management defaults (`false`) — reasonable and safe defaults for a desktop.

**What is missing / wrong:**
1. `hardware.nvidia.open = true` is hardcoded. Open kernel modules require Turing architecture
   (RTX 20xx / GTX 16xx and newer). Setting `open = true` on Maxwell, Pascal, Volta, Kepler, or
   Fermi cards causes a broken build or a non-functional GPU.
2. `nvidiaPackages.stable` is hardcoded. This uses the 570.x driver branch, which does **not**
   support Fermi (GeForce 400/500 series) or Kepler (GeForce 600/700 series) GPUs. Those GPU
   generations require `legacy_390` or `legacy_470` respectively.
3. `nvidia-vaapi-driver` is unconditionally included. This package provides VA-API via NVDEC and
   requires Turing+ hardware. On older GPUs it fails to initialize and pollutes the hardware
   acceleration stack.

**Verdict:** The module covers **only** latest/Turing+ NVIDIA cards. There is **no support** for
legacy cards requiring `legacy_390`, `legacy_470`, or `legacy_535`.

---

## 2. Problem Definition

The `vexos-nvidia` flake output is unusable on any NVIDIA GPU older than Turing (RTX 20xx / GTX
16xx) because:

- `open = true` will select open kernel modules, which do not build or load on pre-Turing silicon.
- `nvidiaPackages.stable` (570.x) does not ship kernel module support for Fermi or Kepler GPUs.
- No user-facing option exists to select an appropriate older driver branch.

A user with, for example, a GTX 1070 (Pascal), a GTX 770 (Kepler), or a GTX 580 (Fermi) who
deploys the `vexos-nvidia` configuration will get a broken system. The module needs a documented,
user-configurable path to the correct driver branch.

---

## 3. Background: NixOS NVIDIA Driver Packages

### 3.1 Available packages in `config.boot.kernelPackages.nvidiaPackages`

Source: `pkgs/os-specific/linux/nvidia-x11/default.nix` in nixpkgs (nixos-25.05 / nixos-25.11)

| Attribute | Version (nixos-25.05) | GPU Architectures | GPU Examples |
|---|---|---|---|
| `stable` / `production` | 570.195.03 | Maxwell and newer (with `open = false`); Turing+ (with `open = true`) | GTX 750+, RTX 20/30/40 series |
| `legacy_535` | 535.274.02 | Maxwell (GM1xx/GM2xx), Pascal (GP1xx), Volta (GV1xx); also Turing+ | GTX 750/Ti, GTX 960–980, GTX 1050–1080 Ti, Titan V, also RTX 20/30/40 |
| `legacy_470` | 470.256.02 | Kepler (GK1xx, GK2xx) | GeForce 600, 700, 800M series |
| `legacy_390` | 390.157 | Fermi (GF1xx) | GeForce 400, 500, some 600 series |
| `legacy_340` | 340.108 | Tesla/early Fermi | *(broken on kernel ≥ 6.7; not supported)* |

> **Reference:** [NixOS Wiki – NVIDIA legacy branches](https://wiki.nixos.org/wiki/NVIDIA#Legacy_branches)
> **Reference:** [nixpkgs default.nix for nvidia-x11 (25.05)](https://github.com/NixOS/nixpkgs/blob/nixos-25.05/pkgs/os-specific/linux/nvidia-x11/default.nix)

### 3.2 `hardware.nvidia.open` compatibility matrix

| Driver variant | `open = true` | `open = false` |
|---|---|---|
| `stable` / `latest` (Turing+ card) | ✔ Required for Wayland best results | ✔ Allowed |
| `stable` (Maxwell/Pascal/Volta card) | ✘ Fails — no open module support | ✔ Required |
| `legacy_535` | ✘ 535 branch uses proprietary modules only | ✔ Required |
| `legacy_470` | ✘ No open modules for Kepler | ✔ Required |
| `legacy_390` | ✘ No open modules for Fermi | ✔ Required |

> Since driver 560, NixOS/nixpkgs requires `hardware.nvidia.open` to be explicitly set.
> For all legacy variants the only correct value is `false`.

### 3.3 `nvidia-vaapi-driver` (NVDEC-based VA-API) compatibility

`nvidia-vaapi-driver` requires NVDEC hardware present in Turing (RTX 20xx) and newer cards.
Maxwell and Pascal cards lack the NVDEC generation compatible with this driver. Fermi and Kepler
have no NVDEC at all. The package must only be included when the driver variant is `"latest"`.

---

## 4. Proposed Solution

### 4.1 Approach

Add a NixOS option `vexos.gpu.nvidiaDriverVariant` to `modules/gpu/nvidia.nix`. This option
selects both the driver package (`hardware.nvidia.package`) and whether open kernel modules are
used (`hardware.nvidia.open`). The `nvidia-vaapi-driver` package is conditionally included only
for the `"latest"` variant.

The default remains `"latest"` — preserving exact current behavior for Turing+ users.

### 4.2 Option definition

```
Option name:  vexos.gpu.nvidiaDriverVariant
Type:         lib.types.enum [ "latest" "legacy_535" "legacy_470" "legacy_390" ]
Default:      "latest"
```

| Value | Driver package | `open` | `nvidia-vaapi-driver` |
|---|---|---|---|
| `"latest"` | `nvidiaPackages.stable` | `true` | included |
| `"legacy_535"` | `nvidiaPackages.legacy_535` | `false` | excluded |
| `"legacy_470"` | `nvidiaPackages.legacy_470` | `false` | excluded |
| `"legacy_390"` | `nvidiaPackages.legacy_390` | `false` | excluded |

### 4.3 Full replacement for `modules/gpu/nvidia.nix`

```nix
# modules/gpu/nvidia.nix
# NVIDIA proprietary drivers with multi-generation support.
# Import this in hosts/nvidia.nix — do NOT use alongside gpu/amd.nix or gpu/vm.nix.
#
# Set vexos.gpu.nvidiaDriverVariant in your host config to match your GPU generation:
#   "latest"     — Turing (RTX 20xx / GTX 16xx) and newer  [default]
#   "legacy_535" — Maxwell / Pascal / Volta (GTX 750–1080 Ti, Titan V)
#   "legacy_470" — Kepler (GeForce 600 / 700 series)
#   "legacy_390" — Fermi  (GeForce 400 / 500 series)
{ config, pkgs, lib, ... }:

let
  variant = config.vexos.gpu.nvidiaDriverVariant;

  driverPackage =
    if variant == "latest"      then config.boot.kernelPackages.nvidiaPackages.stable
    else if variant == "legacy_535" then config.boot.kernelPackages.nvidiaPackages.legacy_535
    else if variant == "legacy_470" then config.boot.kernelPackages.nvidiaPackages.legacy_470
    else if variant == "legacy_390" then config.boot.kernelPackages.nvidiaPackages.legacy_390
    else abort "vexos.gpu.nvidiaDriverVariant: unknown value '${variant}'";

  # Open kernel modules require Turing (RTX 20xx / GTX 16xx) or newer.
  # All legacy variants must use proprietary closed modules.
  useOpen = variant == "latest";

in
{
  options.vexos.gpu.nvidiaDriverVariant = lib.mkOption {
    type = lib.types.enum [ "latest" "legacy_535" "legacy_470" "legacy_390" ];
    default = "latest";
    description = ''
      NVIDIA driver branch to use. Choose based on your GPU generation:

        "latest"     — stable (570.x) branch; open kernel modules for Turing (RTX 20xx / GTX 16xx+).
                       This is the correct choice for all RTX 20/30/40 series and GTX 16xx cards.
        "legacy_535" — 535.x LTS branch; proprietary modules required.
                       Use for Maxwell (GTX 750/Ti), Pascal (GTX 1050–1080 Ti), and Volta (Titan V).
        "legacy_470" — 470.x branch; proprietary modules required.
                       Use for Kepler GPUs: GeForce 600 and 700 series.
        "legacy_390" — 390.x branch; proprietary modules required.
                       Use for Fermi GPUs: GeForce 400 and 500 series.
    '';
  };

  config = {
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      # Open kernel modules: supported only on Turing (RTX 20xx / GTX 16xx) and newer.
      # All legacy variants must use proprietary closed modules (open = false).
      open = useOpen;

      # KMS: required for Wayland and reliable suspend/resume on all variants.
      modesetting.enable = true;

      powerManagement = {
        enable = false;       # set true if suspend/resume causes GPU lockups
        finegrained = false;  # set true for PRIME Turing+ discrete laptops only
      };

      package = driverPackage;
    };

    # nvidia-vaapi-driver provides VA-API via NVDEC.
    # NVDEC support is present only on Turing (RTX 20xx) and newer.
    # Excluded for all legacy variants to avoid broken hardware acceleration.
    hardware.graphics.extraPackages = lib.mkIf useOpen (
      with pkgs; [ nvidia-vaapi-driver ]
    );
  };
}
```

### 4.4 Usage: setting the variant in a host config

**Default (no change required for existing Turing+ setups — `hosts/nvidia.nix` is unchanged):**

```nix
# hosts/nvidia.nix — existing file, no edits required for "latest"
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/nvidia.nix
    ../modules/asus.nix
  ];
  # vexos.gpu.nvidiaDriverVariant defaults to "latest"
}
```

**Example for a Pascal card (GTX 1070) — add one line to `hosts/nvidia.nix`:**

```nix
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/nvidia.nix
    ../modules/asus.nix
  ];
  vexos.gpu.nvidiaDriverVariant = "legacy_535";
}
```

**Example for a Kepler card (GTX 760):**

```nix
  vexos.gpu.nvidiaDriverVariant = "legacy_470";
```

**Example for a Fermi card (GTX 580):**

```nix
  vexos.gpu.nvidiaDriverVariant = "legacy_390";
```

---

## 5. Implementation Steps

### Step 1 — Replace `modules/gpu/nvidia.nix`

Replace the entire content of `modules/gpu/nvidia.nix` with the code in Section 4.3.

No other files require changes for the default (`"latest"`) behavior.

### Step 2 — No changes to `hosts/nvidia.nix` for default behavior

The current `hosts/nvidia.nix` imports `modules/gpu/nvidia.nix` and adds no gpu-variant
setting. Because `vexos.gpu.nvidiaDriverVariant` defaults to `"latest"`, this is a
**non-breaking change** — existing systems continue to work identically.

### Step 3 — Document the option in `README.md` (optional but recommended)

Add a note to the NVIDIA section of the README explaining how to override the driver variant
for legacy GPUs.

---

## 6. NixOS Option Names and Nix Syntax Reference

| Purpose | NixOS option / expression |
|---|---|
| Select proprietary closed modules | `hardware.nvidia.open = false;` |
| Select open kernel modules (Turing+) | `hardware.nvidia.open = true;` |
| Use the stable (latest) driver | `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;` |
| Use legacy 535 driver | `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_535;` |
| Use legacy 470 driver | `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_470;` |
| Use legacy 390 driver | `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_390;` |
| Conditional extraPackages | `hardware.graphics.extraPackages = lib.mkIf <condition> (with pkgs; [ ... ]);` |
| Declare a custom option | `lib.mkOption { type = lib.types.enum [ ... ]; default = "..."; description = "..."; }` |
| Separate options from config | Use `options = { ... };` and `config = { ... };` blocks (required when declaring options) |

> **Note on `options` / `config` split:** When a NixOS module declares both `options` and `config`
> at the top level, those keys must be at the root of the attribute set returned by the module
> function. The current `modules/gpu/nvidia.nix` does not declare options, so its content is
> implicitly all `config`. The replacement module uses the explicit `options`/`config` split.

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `legacy_340` not included | Low | `legacy_340` is broken on kernel ≥ 6.7 (the CachyOS/Bazzite kernels used in this flake are 6.12+). Including it would produce an always-broken option. Not offered. |
| `open = true` on a non-Turing card causes build/boot failure | High | Resolved by the variant→open mapping. The `"latest"` path keeps `open = true`; all others force `open = false`. |
| `nvidia-vaapi-driver` on pre-Turing causes non-functional VA-API stack | Medium | Resolved by the `lib.mkIf useOpen` guard — excluded for all legacy variants. |
| `legacy_535` user on a Maxwell card also works with `stable` + `open = false` | Low | Both are valid. `legacy_535` is provided for users who explicitly need the 535 LTS branch (e.g., driver stability preference or Vulkan extension compatibility). The `stable` path (with `open = false` manually set) is NOT the default for legacy cards; users should set the explicit variant. |
| `options`/`config` split breaks if another module also uses `vexos.gpu` namespace | Medium | No existing module in the repo declares any `vexos.*` options. If a shared options module is introduced later, the `vexos.gpu.nvidiaDriverVariant` option can be migrated there. |
| `nix flake check` fails if `legacy_470` package is not evaluable on the current kernel | Low | nixpkgs carries compatibility patches for `legacy_470` on recent kernels (6.12 patch is present in nixos-25.05). The option is lazy-evaluated — only evaluated when `vexos.gpu.nvidiaDriverVariant = "legacy_470"` is set. Default `"latest"` builds are unaffected. |

---

## 8. Files to Modify

| File | Action |
|---|---|
| `modules/gpu/nvidia.nix` | Full replacement (see Section 4.3) |
| `hosts/nvidia.nix` | No change required for default behavior |
| `README.md` | Optional: document the new option |

---

## 9. Verification Steps

After implementation, run:

```bash
# Validate flake evaluation (must pass for all three outputs)
nix flake check

# Dry-build the AMD output to confirm it is unaffected
sudo nixos-rebuild dry-build --flake .#vexos-amd

# Dry-build the NVIDIA output (exercises the new options path with default "latest")
sudo nixos-rebuild dry-build --flake .#vexos-nvidia

# Dry-build the VM output to confirm it is unaffected
sudo nixos-rebuild dry-build --flake .#vexos-vm
```

To verify the legacy variant evaluates correctly without a physical legacy GPU:

```bash
# Temporarily set vexos.gpu.nvidiaDriverVariant = "legacy_470" in hosts/nvidia.nix,
# then run:
sudo nixos-rebuild dry-build --flake .#vexos-nvidia
# Confirm it selects nvidiaPackages.legacy_470 and open = false.
# Restore the default "latest" afterward.
```

---

## 10. Sources Consulted

1. NixOS Wiki — NVIDIA (Legacy branches section):
   https://wiki.nixos.org/wiki/NVIDIA#Legacy_branches
2. nixpkgs `nvidia-x11/default.nix` (nixos-25.05 branch) — listing all available package
   attributes and driver versions:
   https://github.com/NixOS/nixpkgs/blob/nixos-25.05/pkgs/os-specific/linux/nvidia-x11/default.nix
3. NVIDIA official legacy GPU support list:
   https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/
4. NixOS Wiki — NVIDIA (Beta/production branches section, open module requirements):
   https://wiki.nixos.org/wiki/NVIDIA#Beta_production_branches
5. NixOS `hardware.nvidia` module source (nixpkgs):
   https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/hardware/nvidia.nix
6. NVIDIA developer blog — Open GPU Kernel Modules announcement (Turing+ requirement):
   https://developer.nvidia.com/blog/nvidia-transitions-fully-towards-open-source-gpu-kernel-modules/
