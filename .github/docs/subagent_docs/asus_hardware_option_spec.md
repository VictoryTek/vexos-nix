# ASUS Hardware Option Specification
**Feature:** `vexos.hardware.asus.enable` — universal opt-in ASUS ROG/TUF hardware support  
**Status:** Draft  
**Date:** 2026-05-15  

---

## 1. Current State Analysis

### 1.1 What `modules/asus.nix` Contains

```nix
{ config, pkgs, lib, ... }:
{
  services.asusd = {
    enable = true;
    enableUserService = true;
  };
  services.supergfxd.enable = true;
  environment.systemPackages = with pkgs; [
    asusctl
  ];
}
```

**Effect of each setting:**

| Setting | Purpose |
|---|---|
| `services.asusd.enable = true` | Starts the ASUS ROG daemon: fan curves, battery charge limit, power/thermal profiles, Aura keyboard backlight, GPU MUX switching, Anime Matrix LED |
| `services.asusd.enableUserService = true` | Starts `asusd-user`: per-user Aura LED profile control |
| `services.supergfxd.enable = true` | GPU switching daemon (integrated / hybrid / VFIO / dedicated). The `supergfxd` NixOS module also auto-adds `pkgs.supergfxctl` to `environment.systemPackages`. |
| `environment.systemPackages = [ asusctl ]` | Adds the `asusctl` CLI + `rog-control-center` GUI |

**Safety on non-ASUS hardware:**  
`asus.nix` itself is commented with: *"Safe on non-ASUS hardware: asusd and supergfxd exit gracefully when ASUS platform drivers are absent. No kernel module additions required."*  
This means the services are benign on non-ASUS systems — they start, find no ASUS hardware, and stay idle. However, they still consume minor system resources (two systemd units), so it is better to gate them behind a hardware flag anyway.

**VM constraint:**  
`asus.nix` itself is also commented with: *"DO NOT import in hosts/vm.nix — not applicable in VM guests."*

---

### 1.2 Which Host Files Currently Import `asus.nix` (Exact Lines)

| Host File | Line | Import Path | Notes |
|---|---|---|---|
| `hosts/desktop-amd.nix` | 9 | `../modules/asus.nix` | Physical AMD desktop — correct |
| `hosts/desktop-nvidia.nix` | 9 | `../modules/asus.nix` | Physical NVIDIA desktop — correct |
| `hosts/desktop-intel.nix` | 9 | `../modules/asus.nix` | Physical Intel desktop — ASUS Intel laptops exist; currently opted in |
| `hosts/desktop-vm.nix` | 20 | `../modules/asus.nix` | **BUG** — VM guest; `asus.nix` itself says do NOT import here |

**Hosts with NO ASUS import (gap to fill for ASUS hardware users):**

- `hosts/server-amd.nix`, `hosts/server-nvidia.nix`, `hosts/server-intel.nix`, `hosts/server-vm.nix`
- `hosts/htpc-amd.nix`, `hosts/htpc-nvidia.nix`, `hosts/htpc-intel.nix`, `hosts/htpc-vm.nix`
- `hosts/headless-server-amd.nix`, `hosts/headless-server-nvidia.nix`, `hosts/headless-server-intel.nix`, `hosts/headless-server-vm.nix`
- `hosts/stateless-amd.nix`, `hosts/stateless-nvidia.nix`, `hosts/stateless-intel.nix`, `hosts/stateless-vm.nix`
- All `hosts/vanilla-*.nix`

---

### 1.3 What Each `configuration-*.nix` Currently Imports (ASUS-relevant summary)

| File | Current ASUS content |
|---|---|
| `configuration-desktop.nix` | Nothing — relies on host files importing `asus.nix` directly |
| `configuration-server.nix` | Nothing |
| `configuration-htpc.nix` | Nothing |
| `configuration-headless-server.nix` | Nothing |
| `configuration-stateless.nix` | Nothing |
| `configuration-vanilla.nix` | Nothing (minimal baseline — only `locale`, `users`, `nix`) |

None of the role configuration files currently import `asus.nix` or declare any `vexos.hardware.asus` option.

---

## 2. Problem Definition

ASUS hardware support (`asusd`, `supergfxd`, `asusctl`) is currently hard-wired into three desktop host files via direct `imports`. This makes ASUS support a desktop-only feature in practice:

- A user running the **server** role on an ASUS ROG machine loses: fan curve control, battery charge limits, power profiles, and GPU switching.
- A user running the **htpc** role on an ASUS TUF machine has the same loss.
- A user running the **headless-server** or **stateless** role loses identical functionality.
- `hosts/desktop-vm.nix` **incorrectly** imports `asus.nix` — this is a pre-existing bug.

ASUS support is fundamentally **hardware-dependent**, not **role-dependent**. The fix is to expose it through a NixOS option that any role can enable via the host file.

---

## 3. Proposed Solution Architecture

### 3.1 New File: `modules/asus-opt.nix`

Declares the `vexos.hardware.asus.enable` option and contains all configuration from `asus.nix` inlined under `lib.mkIf`. The `lib.mkIf` guard here is a **hardware-flag gate**, not a role gate — this is acceptable under the project's Option B architecture rule (the guard lives in a dedicated hardware module, not in a shared role configuration file).

**Exact content of `modules/asus-opt.nix`:**

```nix
# modules/asus-opt.nix
# Opt-in ASUS ROG/TUF hardware support available to all roles.
#
# Set `vexos.hardware.asus.enable = true` in the relevant hosts/*.nix file
# for any machine built on ASUS ROG / TUF hardware.
#
# This module is imported by every configuration-*.nix so the option is
# always declared regardless of role.  Only host files for physical ASUS
# machines should set the option.
#
# Architecture note: the lib.mkIf guard below is a hardware-enable-flag gate,
# NOT a role gate.  This is valid under the project's Option B architecture —
# a dedicated hardware module may gate its own content on a hardware flag.
# Do NOT replicate this pattern in role configuration files.
#
# VM guests: do NOT set vexos.hardware.asus.enable = true on vm variants.
# asusd and supergfxd have no ASUS platform devices to manage in a VM.
{ config, lib, pkgs, ... }:
{
  options.vexos.hardware.asus = {
    enable = lib.mkEnableOption "ASUS ROG/TUF hardware support (asusd, supergfxctl, fan curves)";
  };

  config = lib.mkIf config.vexos.hardware.asus.enable {
    # asusd: ASUS ROG daemon — fan curves, battery charge limit, power/thermal profiles,
    # keyboard backlight (Aura), GPU MUX switching, Anime Matrix LED.
    # Enabling this also enables services.supergfxd via lib.mkDefault (see nixpkgs source).
    services.asusd = {
      enable = true;
      enableUserService = true;  # asusd-user: per-user Aura LED profile control
    };

    # supergfxd: GPU switching daemon (integrated / hybrid / VFIO / dedicated modes).
    # Explicitly set to ensure it's always enabled regardless of asusd's mkDefault.
    # The supergfxd module auto-installs pkgs.supergfxctl into environment.systemPackages.
    services.supergfxd.enable = true;

    # asusctl CLI tool + rog-control-center GUI (bundled in the same package).
    # supergfxctl is already added to systemPackages by the supergfxd NixOS module.
    environment.systemPackages = with pkgs; [
      asusctl  # CLI: asusctl; GUI: rog-control-center (both included in this package)
    ];
  };
}
```

**Why `lib.mkIf` in `config` (not `imports`) is correct here:**  
NixOS evaluates `imports` unconditionally before option values are resolved. Placing a conditional inside `config = lib.mkIf ...` is the standard pattern for option-gated configuration. Since `imports = []` (fixed/empty in this module), there is no evaluation-order issue. The content of `asus.nix` is simple — no sub-imports, no further file references — so inlining it directly is safe.

---

### 3.2 Disposition of `modules/asus.nix`

**Decision: DELETE `modules/asus.nix`.**

After migration, no file in the repository will import `modules/asus.nix` directly. It becomes dead code. Deleting it:

- Prevents accidental re-import by future authors
- Removes ambiguity about which file is authoritative
- Keeps the module directory clean

The full content of `asus.nix` is preserved verbatim inside `asus-opt.nix` under `lib.mkIf`, so there is zero information loss.

---

### 3.3 Changes to `configuration-*.nix` Files (Add `asus-opt.nix` Import)

Every role configuration file must import `asus-opt.nix` so the `vexos.hardware.asus.enable` option is declared and available for any host file of that role to set.

| File | Change |
|---|---|
| `configuration-desktop.nix` | Add `./modules/asus-opt.nix` to imports |
| `configuration-server.nix` | Add `./modules/asus-opt.nix` to imports |
| `configuration-htpc.nix` | Add `./modules/asus-opt.nix` to imports |
| `configuration-headless-server.nix` | Add `./modules/asus-opt.nix` to imports |
| `configuration-stateless.nix` | Add `./modules/asus-opt.nix` to imports |
| `configuration-vanilla.nix` | Add `./modules/asus-opt.nix` to imports |

Placement in the import list: Add after `./modules/users.nix` (last existing entry in each file) or at the logical end of the hardware/system section. Alphabetical proximity to other hardware modules (`gpu.nix`, etc.) is ideal but consistency within each file takes precedence.

**Suggested placement by file:**

- `configuration-desktop.nix`: After `./modules/razer.nix` (currently the last import)
- `configuration-server.nix`: After `./modules/users.nix`
- `configuration-htpc.nix`: After `./modules/users.nix`
- `configuration-headless-server.nix`: After `./modules/users.nix`
- `configuration-stateless.nix`: After `./modules/users.nix`
- `configuration-vanilla.nix`: After `./modules/users.nix`

---

### 3.4 Changes to `hosts/*.nix` Files — Add `vexos.hardware.asus.enable = true`

These hosts represent physical ASUS AMD or NVIDIA machines. Add `vexos.hardware.asus.enable = true` to each:

| Host File | Role | GPU | Action |
|---|---|---|---|
| `hosts/desktop-amd.nix` | desktop | AMD | Add option **AND** remove direct `asus.nix` import |
| `hosts/desktop-nvidia.nix` | desktop | NVIDIA | Add option **AND** remove direct `asus.nix` import |
| `hosts/server-amd.nix` | server | AMD | Add option only (no prior import) |
| `hosts/server-nvidia.nix` | server | NVIDIA | Add option only (no prior import) |
| `hosts/htpc-amd.nix` | htpc | AMD | Add option only (no prior import) |
| `hosts/htpc-nvidia.nix` | htpc | NVIDIA | Add option only (no prior import) |
| `hosts/headless-server-amd.nix` | headless-server | AMD | Add option only (no prior import) |
| `hosts/headless-server-nvidia.nix` | headless-server | NVIDIA | Add option only (no prior import) |
| `hosts/stateless-amd.nix` | stateless | AMD | Add option only (no prior import) |
| `hosts/stateless-nvidia.nix` | stateless | NVIDIA | Add option only (no prior import) |

**Example host file after change (using `hosts/desktop-amd.nix` as template):**

```nix
# hosts/amd.nix
# vexos — AMD GPU desktop build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-amd
{ lib, ... }:
{
  imports = [
    ../configuration-desktop.nix
    ../modules/gpu/amd.nix
    # ../modules/asus.nix  <-- removed; use vexos.hardware.asus.enable instead
  ];

  system.nixos.distroName = "VexOS Desktop AMD";
  vexos.hardware.asus.enable = true;
}
```

**Example for a role that previously had no ASUS import (using `hosts/server-amd.nix`):**

```nix
# hosts/server-amd.nix
# vexos — Server AMD GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-amd
{ lib, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/amd.nix
  ];

  system.nixos.distroName = "VexOS Server AMD";
  vexos.hardware.asus.enable = true;

  # REQUIRED: replace with the real value from the target host.
  # Generate: head -c 8 /etc/machine-id
  networking.hostId = "a0000001";
}
```

---

### 3.5 Changes to `hosts/*.nix` Files — Remove Direct `asus.nix` Import Only

These hosts currently import `asus.nix` directly but should NOT receive `vexos.hardware.asus.enable = true` after migration:

| Host File | Reason | Action |
|---|---|---|
| `hosts/desktop-vm.nix` | VM guest — no physical ASUS hardware | Remove `../modules/asus.nix` import; **do NOT add option** |
| `hosts/desktop-intel.nix` | See §3.6 below | Remove `../modules/asus.nix` import; **do NOT add option** |

---

### 3.6 Design Decision: `desktop-intel.nix` and ASUS Support

**Current state:** `hosts/desktop-intel.nix` currently imports `asus.nix` directly. This implies the project has considered Intel-CPU ASUS laptops (e.g. ASUS ROG Strix with Intel Core) as a supported target.

**Spec guidance:** The spec task states AMD and NVIDIA hosts should receive `vexos.hardware.asus.enable = true`, and explicitly says "NOT intel (not ASUS typically)."

**Consequence of following spec guidance:** After migration, Intel ASUS laptop users using `desktop-intel` will lose ASUS hardware support (no fan curves, no Aura, no supergfxd). They would need to manually set `vexos.hardware.asus.enable = true` in their host file.

**Recommendation:** Follow the spec guidance (remove the direct import, do not set the option by default). Add a comment to `hosts/desktop-intel.nix` noting that ASUS Intel laptop users should set `vexos.hardware.asus.enable = true` locally. This keeps the option available while making the default correct for the majority (Intel Macs, Intel NUCs, non-ASUS Intel machines).

**Comment to add to `hosts/desktop-intel.nix` after removing the import:**

```nix
# ASUS Intel laptop users (e.g. ROG Strix with Intel CPU): set the following
# in your local /etc/nixos/hardware-configuration.nix or a host-override file:
#   vexos.hardware.asus.enable = true;
```

---

## 4. Implementation Steps (Ordered)

1. **Create** `modules/asus-opt.nix` with the content from §3.1.

2. **Add** `./modules/asus-opt.nix` import to each `configuration-*.nix` as described in §3.3.

3. **Modify** `hosts/desktop-amd.nix`:
   - Remove line: `../modules/asus.nix`
   - Add: `vexos.hardware.asus.enable = true;`

4. **Modify** `hosts/desktop-nvidia.nix`:
   - Remove line: `../modules/asus.nix`
   - Add: `vexos.hardware.asus.enable = true;`

5. **Modify** `hosts/desktop-intel.nix`:
   - Remove line: `../modules/asus.nix`
   - Add guidance comment (§3.6)
   - Do NOT add the option

6. **Modify** `hosts/desktop-vm.nix`:
   - Remove line: `../modules/asus.nix`
   - Do NOT add the option

7. **Modify** `hosts/server-amd.nix`, `hosts/server-nvidia.nix`:
   - Add: `vexos.hardware.asus.enable = true;`

8. **Modify** `hosts/htpc-amd.nix`, `hosts/htpc-nvidia.nix`:
   - Add: `vexos.hardware.asus.enable = true;`

9. **Modify** `hosts/headless-server-amd.nix`, `hosts/headless-server-nvidia.nix`:
   - Add: `vexos.hardware.asus.enable = true;`

10. **Modify** `hosts/stateless-amd.nix`, `hosts/stateless-nvidia.nix`:
    - Add: `vexos.hardware.asus.enable = true;`

11. **Delete** `modules/asus.nix`.

---

## 5. Complete File Change Matrix

### Files to CREATE
| File | Action |
|---|---|
| `modules/asus-opt.nix` | New file — option declaration + inlined config |

### Files to MODIFY (configuration-*.nix — add import)
| File | Change |
|---|---|
| `configuration-desktop.nix` | Add `./modules/asus-opt.nix` import |
| `configuration-server.nix` | Add `./modules/asus-opt.nix` import |
| `configuration-htpc.nix` | Add `./modules/asus-opt.nix` import |
| `configuration-headless-server.nix` | Add `./modules/asus-opt.nix` import |
| `configuration-stateless.nix` | Add `./modules/asus-opt.nix` import |
| `configuration-vanilla.nix` | Add `./modules/asus-opt.nix` import |

### Files to MODIFY (hosts — remove import AND add option)
| File | Change |
|---|---|
| `hosts/desktop-amd.nix` | Remove `../modules/asus.nix`; add `vexos.hardware.asus.enable = true` |
| `hosts/desktop-nvidia.nix` | Remove `../modules/asus.nix`; add `vexos.hardware.asus.enable = true` |

### Files to MODIFY (hosts — add option only, no prior import existed)
| File | Change |
|---|---|
| `hosts/server-amd.nix` | Add `vexos.hardware.asus.enable = true` |
| `hosts/server-nvidia.nix` | Add `vexos.hardware.asus.enable = true` |
| `hosts/htpc-amd.nix` | Add `vexos.hardware.asus.enable = true` |
| `hosts/htpc-nvidia.nix` | Add `vexos.hardware.asus.enable = true` |
| `hosts/headless-server-amd.nix` | Add `vexos.hardware.asus.enable = true` |
| `hosts/headless-server-nvidia.nix` | Add `vexos.hardware.asus.enable = true` |
| `hosts/stateless-amd.nix` | Add `vexos.hardware.asus.enable = true` |
| `hosts/stateless-nvidia.nix` | Add `vexos.hardware.asus.enable = true` |

### Files to MODIFY (hosts — remove import only, no option)
| File | Change | Reason |
|---|---|---|
| `hosts/desktop-intel.nix` | Remove `../modules/asus.nix`; add guidance comment | Not ASUS hardware by default |
| `hosts/desktop-vm.nix` | Remove `../modules/asus.nix` | Bug fix — VM guests never have ASUS hardware |

### Files to DELETE
| File | Reason |
|---|---|
| `modules/asus.nix` | Dead code after migration; content preserved in `asus-opt.nix` |

### Files NOT changed
All other `hosts/*.nix` files (intel, vm variants for server/htpc/headless/stateless/vanilla) — these either have no physical ASUS hardware or are VM guests.

---

## 6. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `desktop-intel.nix` users on ASUS Intel hardware lose ASUS support after migration | Medium | Add a comment to `hosts/desktop-intel.nix` directing them to set `vexos.hardware.asus.enable = true`. Option is available to all roles via the `asus-opt.nix` import. |
| `lib.mkIf` in `config` block is unfamiliar pattern to some NixOS users | Low | Inline comment in `asus-opt.nix` explains this is the standard NixOS pattern for option-gated configuration. |
| `asus.nix` deleted — any external template or `/etc/nixos` file that imports it by path will break | Low | No tracked file in this repo imports `asus.nix` after migration. External users of the old direct import path are not supported (this is a personal config repo). |
| `asusd` and `supergfxd` services still run on physical AMD/NVIDIA non-ASUS machines if `vexos.hardware.asus.enable = true` is set by mistake | Low | Services exit gracefully on non-ASUS hardware per upstream documentation. No system damage results. |
| `headless-server` role has no display — `rog-control-center` GUI is installed but non-functional | Low | Acceptable — `asusctl` CLI is the primary interface for headless use cases (fan curves, power profiles via SSH). |
| `nix flake check` may fail during evaluation if the option is not declared before host files reference it | Low | Resolved by importing `asus-opt.nix` from every `configuration-*.nix` before any host file can set `vexos.hardware.asus.enable = true`. |

---

## 7. Validation Checklist for Review Phase

- [ ] `nix flake check` passes with no evaluation errors
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` succeeds and closure includes `asusd`, `supergfxd`, `asusctl`
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` succeeds and closure includes ASUS packages
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` succeeds and closure does NOT include `asusd` or `asusctl`
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` succeeds and closure includes ASUS packages
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd` succeeds and closure includes ASUS packages
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` succeeds and closure includes ASUS packages
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` succeeds and closure includes ASUS packages
- [ ] `modules/asus.nix` no longer exists in the repository
- [ ] No remaining reference to `../modules/asus.nix` in any `hosts/*.nix` file
- [ ] `hardware-configuration.nix` is NOT committed
- [ ] `system.stateVersion` is unchanged in all `configuration-*.nix` files
