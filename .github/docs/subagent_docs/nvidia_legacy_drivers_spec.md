# Specification: NVIDIA Legacy Driver Support — Phase 2 (Flake Outputs)
**Feature Name:** `nvidia_legacy_drivers`
**Spec File:** `.github/docs/subagent_docs/nvidia_legacy_drivers_spec.md`
**Date:** 2026-04-14
**Status:** Ready for Implementation
**Supersedes:** Previous revision dated 2026-04-02 (Phase 1 — module option)

---

## 0. Phase 1 Recap (Already Implemented)

The April 2 spec and its implementation added `vexos.gpu.nvidiaDriverVariant` to
`modules/gpu/nvidia.nix`. That module is technically complete and was reviewed at A+ (99%).
It already:

- Declares `options.vexos.gpu.nvidiaDriverVariant` as an enum defaulting to `"latest"`.
- Maps the variant to the correct `hardware.nvidia.package`.
- Sets `hardware.nvidia.open = false` for all legacy variants (proprietary modules).
- Conditionally includes `nvidia-vaapi-driver` only for the `"latest"` variant.

**Phase 1 is complete. No changes to `modules/gpu/nvidia.nix` are required.**

---

## 1. Current State Analysis

### 1.1 Module: `modules/gpu/nvidia.nix` (Phase 1 — DONE)

The module is correctly implemented. Support for the following variants exists:

| Variant value   | Driver package                    | `open` | `nvidia-vaapi-driver` |
|-----------------|-----------------------------------|--------|-----------------------|
| `"latest"`      | `nvidiaPackages.stable` (570.x+)  | true   | included              |
| `"legacy_535"`  | `nvidiaPackages.legacy_535`       | false  | excluded              |
| `"legacy_470"`  | `nvidiaPackages.legacy_470`       | false  | excluded              |
| `"legacy_390"`  | `nvidiaPackages.legacy_390`       | false  | excluded              |

### 1.2 Host files — no variant is set

All NVIDIA host files (`hosts/desktop-nvidia.nix`, `hosts/htpc-nvidia.nix`,
`hosts/stateless-nvidia.nix`, `hosts/server-nvidia.nix`) import
`modules/gpu/nvidia.nix` but **do not set `vexos.gpu.nvidiaDriverVariant`**.
The option defaults to `"latest"` in every case.

### 1.3 Flake outputs — only one NVIDIA desktop output exists

`flake.nix` defines:
```nix
nixosConfigurations.vexos-desktop-nvidia = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/desktop-nvidia.nix ];
  specialArgs = { inherit inputs; };
};
```

No outputs for `vexos-desktop-nvidia-legacy470`, `vexos-desktop-nvidia-legacy390`,
or other legacy variants exist. The same gap exists for the `htpc` and `stateless`
roles.

### 1.4 Template: `template/etc-nixos-flake.nix`

The template documents only `vexos-desktop-nvidia` as the NVIDIA rebuild target.
No legacy targets are mentioned. Users with legacy GPUs have no discoverable path
to the correct flake output.

---

## 2. Problem Definition

### 2.1 Symptoms

When a user with a Kepler GPU (GeForce 600/700 series, e.g. GTX 670) runs:
```
sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia
```
the build succeeds, but the resulting system fails to display graphics or boots to
a black screen. The NVIDIA 570.x+ production driver does **not** support Kepler or
Fermi architectures. The kernel module fails to initialize the GPU.

### 2.2 Root Cause

The `vexos.gpu.nvidiaDriverVariant` option exists but is never set in any host
file, so it always defaults to `"latest"`. No separate flake outputs expose the
legacy variants. Users with legacy GPUs have no discoverable, zero-edit path to a
working configuration.

### 2.3 NVIDIA GPU Architecture → Required Driver

| GPU Family | Example Cards                  | Required driver          |
|------------|--------------------------------|--------------------------|
| Ada / Hopper / Ampere / Turing / GTX 16xx | RTX 20/30/40xx, GTX 1650/1660 | `"latest"` |
| Volta       | Titan V                        | `"latest"` (still supported) |
| Pascal      | GTX 1050–1080 Ti, Titan XP     | `"latest"` (still supported) |
| Maxwell 2nd | GTX 950–980 Ti                 | `"latest"` (still supported) |
| Maxwell 1st | GTX 750, GTX 750 Ti            | `"latest"` (still supported) |
| Kepler      | GTX 600/700 series             | **MUST use `"legacy_470"`** |
| Fermi       | GTX 400/500 series             | **MUST use `"legacy_390"`** |
| Tesla       | GeForce 8000–580               | `legacy_340` — **broken on kernel ≥ 6.7; not supported** |

**Important:** Maxwell, Pascal, and Volta GPUs work correctly with `"latest"`.
The `"legacy_535"` variant is an *optional LTS alternative* for those
architectures — it is not architecturally required.

---

## 3. Research Findings

### Source 1 — NixOS Wiki: NVIDIA
https://nixos.wiki/wiki/Nvidia

Confirmed available driver packages in NixOS nixos-25.05 / nixos-25.11:
```nix
config.boot.kernelPackages.nvidiaPackages.stable       # 570.x production
config.boot.kernelPackages.nvidiaPackages.legacy_535   # 535.x LTS
config.boot.kernelPackages.nvidiaPackages.legacy_470   # Kepler (470.x)
config.boot.kernelPackages.nvidiaPackages.legacy_390   # Fermi (390.x)
config.boot.kernelPackages.nvidiaPackages.legacy_340   # Tesla (broken ≥ kernel 6.7)
```

The wiki lists `legacy_580` as an available option. Research below clarifies
this refers to a **data-center driver** (dc_580), not a consumer GPU legacy branch.

### Source 2 — nixpkgs hardware/video/nvidia.nix (nixos-25.05)
https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/hardware/video/nvidia.nix

Upstream `hardware.nvidia.package` option default:
```nix
default = config.boot.kernelPackages.nvidiaPackages."${if cfg.datacenter.enable then "dc" else "stable"}";
example = "config.boot.kernelPackages.nvidiaPackages.legacy_470";
```
Confirms `legacy_470` is the documented example for legacy package selection.

NixOS assertion for drivers ≥ 560: `hardware.nvidia.open` must be explicitly
set to `true` or `false`. The vexos module already satisfies this.

### Source 3 — nixpkgs nvidia-x11/default.nix (nixos-25.05)
https://github.com/NixOS/nixpkgs/blob/nixos-25.05/pkgs/os-specific/linux/nvidia-x11/default.nix

- Production driver: **570.195.03**
- `legacy_535`: **535.274.02**
- `legacy_470`: maintained with kernel 6.12 patches

### Source 4 — nixpkgs nvidia-x11/default.nix (nixos-unstable, April 2026)
https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/os-specific/linux/nvidia-x11/default.nix

- Production driver: **595.58.03** (confirms driver version progression)
- `legacy_470`: **470.256.02** — actively maintained with patches for kernels up to **6.15**
- `dc_580` (580.126.09) and `dc_590` (590.48.01) are **datacenter** drivers, not consumer
  legacy branches. There is **no consumer `legacy_580` package**.
- Kepler support through `legacy_470` is confirmed to remain in nixos-unstable.

**For nixos-25.11** (the channel used by this flake): the production driver was
likely in the 575–585.x range. `legacy_535` should still be available, but the
implementation subagent must verify before depending on it.

### Source 5 — NVIDIA Official Legacy GPU List
https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/

Confirms Kepler GPUs (GeForce 600/700) were dropped from production drivers in
the 525.x cycle and require `legacy_470`. Fermi dropped earlier and requires
`legacy_390`.

### Source 6 — NixOS community flake patterns (GitHub)

Multiple NixOS community flakes use inline module overrides to expose separate
`nixosConfigurations` outputs for different hardware variants without duplicating
host config files:

```nix
nixosConfigurations.vexos-desktop-nvidia-legacy470 = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [
    ./hosts/desktop-nvidia.nix
    { vexos.gpu.nvidiaDriverVariant = "legacy_470"; }
  ];
  specialArgs = { inherit inputs; };
};
```

This is the standard pattern and avoids any host file duplication.

---

## 4. Proposed Solution Architecture

### 4.1 Design Decision: Additional Flake Outputs

**Chosen:** Add separate `nixosConfigurations` outputs for each legacy variant
using an inline single-attribute module override in `flake.nix`.

**Rejected alternatives:**
- **NixOS specialisations:** Users would need to select a non-default boot entry
  every rebuild. The base system would still use the latest driver, failing on
  legacy hardware.
- **Per-host local override in `/etc/nixos/flake.nix`:** Too complex; requires
  understanding the NixOS module system; no discoverable UX.

### 4.2 New Flake Outputs

| Flake output                        | Variant         | Target hardware                          |
|-------------------------------------|-----------------|------------------------------------------|
| `vexos-desktop-nvidia`              | `"latest"`      | Turing (RTX 20xx / GTX 16xx) and newer  |
| `vexos-desktop-nvidia-legacy535`    | `"legacy_535"`  | Maxwell/Pascal/Volta — optional LTS      |
| `vexos-desktop-nvidia-legacy470`    | `"legacy_470"`  | Kepler — GTX 600/700 (**required**)      |
| `vexos-desktop-nvidia-legacy390`    | `"legacy_390"`  | Fermi — GTX 400/500 (**required**)       |
| `vexos-htpc-nvidia-legacy470`       | `"legacy_470"`  | HTPC Kepler                              |
| `vexos-htpc-nvidia-legacy390`       | `"legacy_390"`  | HTPC Fermi                               |
| `vexos-stateless-nvidia-legacy470`  | `"legacy_470"`  | Stateless Kepler                         |
| `vexos-stateless-nvidia-legacy390`  | `"legacy_390"`  | Stateless Fermi                          |

Server role (`vexos-server-nvidia-*`) is **out of scope**: server builds use
headless datacenter drivers, not consumer legacy GPU drivers; the server host
already defaults to `"latest"` which covers any practical headless CUDA/compute
use case within the supported driver range.

### 4.3 Documentation Fix in `modules/gpu/nvidia.nix`

The current option description for `"legacy_535"` incorrectly implies Maxwell,
Pascal, and Volta GPUs **require** the 535.x branch. This must be corrected.

**Current (incorrect):**
```
"legacy_535" — 535.x LTS branch; proprietary modules required.
               Use for Maxwell (GTX 750/Ti), Pascal (GTX 1050–1080 Ti), and Volta (Titan V).
```

**Corrected:**
```
"legacy_535" — 535.x LTS branch; proprietary modules; open = false.
               Optional stable alternative for Maxwell (GTX 750+), Pascal (GTX 1050–1080 Ti),
               and Volta (Titan V) who prefer a proven LTS driver over current production.
               These GPUs work equally well with "latest"; this variant is NOT required.
```

Also update the file header comment to match:
```nix
#   "latest"     — Stable (570.x+) branch; open kernel modules; supports Maxwell (GTX 750+)
#                  through Ada/Hopper. Correct choice for GTX 750+, RTX 20/30/40xx and newer.
#   "legacy_535" — 535.x LTS branch; proprietary modules; open = false.
#                  Optional LTS alternative for Maxwell/Pascal/Volta. NOT architecturally required.
#   "legacy_470" — 470.x branch; proprietary modules. REQUIRED for Kepler: GTX 600/700 series.
#   "legacy_390" — 390.x branch; proprietary modules. REQUIRED for Fermi: GTX 400/500 series.
```

---

## 5. Implementation Steps

### Step 1 — Update `modules/gpu/nvidia.nix` (documentation only)

Correct the `"legacy_535"` description in the option block and the file header.
The module logic itself is unchanged — do NOT modify the Nix expressions.

### Step 2 — Update `flake.nix` (primary change)

**Insert after the existing `vexos-desktop-nvidia` block:**

```nix
# ── NVIDIA Legacy LTS build (Maxwell/Pascal/Volta — optional 535.x LTS) ─────
# sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia-legacy535
nixosConfigurations.vexos-desktop-nvidia-legacy535 = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [
    ./hosts/desktop-nvidia.nix
    { vexos.gpu.nvidiaDriverVariant = "legacy_535"; }
  ];
  specialArgs = { inherit inputs; };
};

# ── NVIDIA Legacy Kepler build (GTX 600/700 series — requires 470.x) ─────────
# sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia-legacy470
nixosConfigurations.vexos-desktop-nvidia-legacy470 = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [
    ./hosts/desktop-nvidia.nix
    { vexos.gpu.nvidiaDriverVariant = "legacy_470"; }
  ];
  specialArgs = { inherit inputs; };
};

# ── NVIDIA Legacy Fermi build (GTX 400/500 series — requires 390.x) ──────────
# sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia-legacy390
nixosConfigurations.vexos-desktop-nvidia-legacy390 = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [
    ./hosts/desktop-nvidia.nix
    { vexos.gpu.nvidiaDriverVariant = "legacy_390"; }
  ];
  specialArgs = { inherit inputs; };
};
```

**Insert after the existing `vexos-stateless-nvidia` block:**

```nix
# ── Stateless NVIDIA Legacy Kepler build ─────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-stateless-nvidia-legacy470
nixosConfigurations.vexos-stateless-nvidia-legacy470 = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [
    ./hosts/stateless-nvidia.nix
    impermanence.nixosModules.impermanence
    { vexos.gpu.nvidiaDriverVariant = "legacy_470"; }
  ];
  specialArgs = { inherit inputs; };
};

# ── Stateless NVIDIA Legacy Fermi build ──────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-stateless-nvidia-legacy390
nixosConfigurations.vexos-stateless-nvidia-legacy390 = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [
    ./hosts/stateless-nvidia.nix
    impermanence.nixosModules.impermanence
    { vexos.gpu.nvidiaDriverVariant = "legacy_390"; }
  ];
  specialArgs = { inherit inputs; };
};
```

**Insert after the existing `vexos-htpc-nvidia` block:**

```nix
# ── HTPC NVIDIA Legacy Kepler build ──────────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-htpc-nvidia-legacy470
nixosConfigurations.vexos-htpc-nvidia-legacy470 = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = minimalModules ++ [
    ./hosts/htpc-nvidia.nix
    { vexos.gpu.nvidiaDriverVariant = "legacy_470"; }
  ];
  specialArgs = { inherit inputs; };
};

# ── HTPC NVIDIA Legacy Fermi build ───────────────────────────────────────────
# sudo nixos-rebuild switch --flake .#vexos-htpc-nvidia-legacy390
nixosConfigurations.vexos-htpc-nvidia-legacy390 = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = minimalModules ++ [
    ./hosts/htpc-nvidia.nix
    { vexos.gpu.nvidiaDriverVariant = "legacy_390"; }
  ];
  specialArgs = { inherit inputs; };
};
```

> **Note on `legacy_535` availability:** Before adding the
> `vexos-desktop-nvidia-legacy535` (and any htpc/stateless `legacy_535`)
> outputs, the implementation subagent MUST verify that
> `config.boot.kernelPackages.nvidiaPackages.legacy_535` exists in nixos-25.11.
> - If available: add the output and the HTPC/stateless equivalents.
> - If removed: omit the `legacy_535` outputs and remove `"legacy_535"` from
>   the `lib.types.enum` in `modules/gpu/nvidia.nix` to prevent option
>   evaluation errors.

### Step 3 — Update `template/etc-nixos-flake.nix`

In the "Desktop role" section of the header comment, add documentation for the
legacy NVIDIA rebuild commands:

```
#      NVIDIA GPU (desktop role):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia              (RTX 20xx / GTX 16xx and newer)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy535    (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy470    (Kepler — GTX 600/700)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy390    (Fermi  — GTX 400/500)
```

Replace the existing single-line `#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia`
with the expanded block above.

---

## 6. Files to be Modified

| File                            | Change type    | Description                                              |
|---------------------------------|----------------|----------------------------------------------------------|
| `modules/gpu/nvidia.nix`        | Documentation  | Correct `"legacy_535"` description; update header comment |
| `flake.nix`                     | Feature        | Add 6–8 new `nixosConfigurations` outputs for legacy variants |
| `template/etc-nixos-flake.nix`  | Documentation  | Document new legacy rebuild commands                     |

No host files need modification. No new files need to be created.

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `legacy_535` removed from nixos-25.11 | Medium | Implementation subagent verifies first; if absent, omits those outputs and removes enum value |
| `legacy_340` not included | None | Confirmed `broken = kernel.kernelAtLeast "6.7"` in nixpkgs; out of scope |
| Adding 6–8 outputs slows `nix flake check` | Low | All outputs share the same module tree and closure; incremental evaluation is fast |
| `hardware.nvidia.open = false` + `legacy_470` fails on newer kernels | Low | nixpkgs carries kernel patches for `legacy_470` up to 6.15 (verified in nixos-unstable); modesetting still enabled |
| VA-API missing for Kepler/Fermi builds | None | Already excluded via `lib.mkIf useOpen`; `libva-vdpau-driver` in `modules/gpu.nix` provides VDPAU fallback |
| Template references undocumented targets | None (mitigated) | Template updated in Step 3 |

---

## 8. Validation Checklist

After implementation, the reviewer must verify:

- [ ] `nix flake check` passes (all new outputs evaluate without error)
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` passes (no regression on default output)
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia-legacy470` passes
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia-legacy390` passes
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia-legacy535` passes (only if `legacy_535` available)
- [ ] The `"legacy_535"` option description no longer implies Maxwell/Pascal/Volta require it
- [ ] `hardware-configuration.nix` is NOT committed to the repo
- [ ] `system.stateVersion` is unchanged

---

## Summary

### What the current `modules/gpu/nvidia.nix` contains (Phase 1 — complete)

The module correctly implements `vexos.gpu.nvidiaDriverVariant` with four
variants (`"latest"`, `"legacy_535"`, `"legacy_470"`, `"legacy_390"`), proper
`open` module selection, and conditional `nvidia-vaapi-driver` inclusion.
The module logic is correct and requires no changes.

### The remaining problem (Phase 2 — this spec)

No dedicated flake outputs exist for legacy NVIDIA driver variants. The sole
`vexos-desktop-nvidia` output always uses the production driver (570.x+), which
does not support Kepler (GTX 600/700) or Fermi (GTX 400/500) GPUs. Users with
legacy hardware get a system that builds successfully but fails to initialize
the GPU at boot.

### The fix

Add named `nixosConfigurations` outputs in `flake.nix` for each legacy variant
(`legacy470`, `legacy390`, optionally `legacy535`) for the desktop, stateless,
and HTPC roles. Each output reuses the existing host file with a single inline
module that overrides `vexos.gpu.nvidiaDriverVariant`. No host files need to
change. Update the template to document the new rebuild commands.

**Exact spec file path:** `/home/nimda/Projects/vexos-nix/.github/docs/subagent_docs/nvidia_legacy_drivers_spec.md`
