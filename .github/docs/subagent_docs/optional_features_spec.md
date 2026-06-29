# Optional Feature Toggles — Phase 1 Spec

**Feature name:** `optional_features`
**Date:** 2026-06-28

---

## 1. Current State Analysis

### 1.1 Affected modules

All six modules below are unconditionally imported by `configuration-desktop.nix`.
They activate on every desktop build regardless of the machine's purpose.

| Module | Description | Lines |
|--------|-------------|-------|
| `modules/gaming.nix` | Steam, Proton-GE, GameMode, Gamescope, Wine, controllers, AppArmor | 141 |
| `modules/gpu-gaming.nix` | 32-bit GL/VA-API libs, vulkan-tools, Mesa shader cache 4 GB | 27 |
| `modules/system-gaming.nix` | Kernel params, vm.max_map_count, THP madvise, SCX LAVD scheduler | 52 |
| `modules/development.nix` | Docker, VSCodium, Python/uv/ruff, Node/pnpm/bun, Go, Claude Code, Nix LSP | 62 |
| `modules/3d-print.nix` | Blender + OrcaSlicer via `vexos.flatpak.extraApps` | 12 |
| `modules/virtualization.nix` | libvirtd/KVM, QEMU-KVM, swtpm, user group `libvirtd` | 39 |

### 1.2 Gaming bundle

`gpu-gaming.nix` and `system-gaming.nix` are tightly coupled to `gaming.nix`.
They supply the GPU-side libraries and kernel tuning that Steam/Proton require.
All three must activate together or not at all. They share a single toggle:
`vexos.features.gaming.enable`.

### 1.3 Existing precedent — server-services.nix

The server role implements an identical pattern:

- Each service module defines `options.vexos.server.<name>.enable` and wraps its
  entire `config` block in `lib.mkIf cfg.enable { ... }`.
- All service modules are always imported by `configuration-server.nix`; they are
  no-ops until the option is set.
- `/etc/nixos/server-services.nix` is a host-local file (not in the repo) that sets
  `vexos.server.<name>.enable = true` for the services wanted on that machine.
- `flake.nix` loads it conditionally:
  ```nix
  serverServicesModule =
    let path = /etc/nixos/server-services.nix;
    in if builtins.pathExists path then [ path ] else [];
  ```
- `just enable <service>` / `just disable <service>` edits the file and offers to rebuild.
- A template at `template/server-services.nix` is copied on first use.

This spec mirrors that pattern exactly for desktop optional features.

---

## 2. Problem Definition

Every desktop install ships with gaming mode, Docker, KVM, and 3D printing tools
unconditionally. A machine set up as a development workstation gets gaming kernel
params it will never use. A gaming rig gets Docker and KVM it does not need.
There is no mechanism to opt out without editing the source.

---

## 3. Proposed Solution Architecture

### 3.1 Overview

1. Convert each optional module to define its own `options.vexos.features.<name>.enable`
   and guard its entire `config` block with `lib.mkIf cfg.enable`.
2. Keep all optional modules in `configuration-desktop.nix`'s import list — they
   remain always imported so their option declarations are in scope, but they are
   no-ops until enabled. No line is removed from `configuration-desktop.nix`.
3. Create `template/features.nix` — the template for the host-local toggle file.
4. Add `featuresModule` to `flake.nix` — conditionally loads `/etc/nixos/features.nix`
   — and wire it into the `desktop` role's `extraModules`.
5. Add justfile recipes: `enable-feature`, `disable-feature`, `features`.

### 3.2 Option namespace

```
vexos.features.gaming.enable         # gaming.nix (also activates gpu-gaming + system-gaming)
vexos.features.development.enable    # development.nix
vexos.features.print3d.enable        # 3d-print.nix  (print3d, not 3d-print — Nix names cannot start with a digit)
vexos.features.virtualization.enable # virtualization.nix
```

### 3.3 Gaming bundle wiring

`gaming.nix` declares the option. `gpu-gaming.nix` and `system-gaming.nix` consume
it without re-declaring it. All three are imported by `configuration-desktop.nix`
so the option is always in scope. Example pattern in `gpu-gaming.nix`:

```nix
{ config, lib, pkgs, ... }:
{
  config = lib.mkIf config.vexos.features.gaming.enable {
    # ... existing content unchanged ...
  };
}
```

This is safe because NixOS evaluates all imported modules as a merged set before
resolving option values. The option declared in `gaming.nix` is visible to any
sibling module in the same import closure.

### 3.4 Module Architecture compliance

The CLAUDE.md "no new lib.mkIf guards in shared modules" rule targets conditional
blocks inside a module that gate partial content by role or flag — the pattern that
creates ambiguous, hard-to-read modules. A top-level `config = lib.mkIf cfg.enable
{ ... }` is different: it wraps the module's entire output under its own declared
option, which is standard NixOS practice (used by every module in
`modules/server/`). This is not tech-debt conditional logic; it is the canonical
way to write an opt-in NixOS module.

---

## 4. Implementation Steps

### Step 1 — `modules/gaming.nix`

Add `lib` to the function arguments. Add an `options` block declaring
`options.vexos.features.gaming.enable = lib.mkEnableOption "gaming stack"`.
Rename the existing top-level attrset to `config = lib.mkIf cfg.enable { ... }`,
where `cfg = config.vexos.features.gaming`.

Verify: `config.vexos.user.name` reference inside the existing content is still
valid — it is, because `config` is the full merged config of the whole system, not
scoped to this module.

### Step 2 — `modules/gpu-gaming.nix`

Change function header from `{ pkgs, ... }:` to `{ config, lib, pkgs, ... }:`.
Wrap the existing flat attrset in `config = lib.mkIf config.vexos.features.gaming.enable { ... }`.
No option declaration needed (defined in `gaming.nix`).

### Step 3 — `modules/system-gaming.nix`

Change function header from `{ ... }:` to `{ config, lib, ... }:`.
Wrap the existing flat attrset in `config = lib.mkIf config.vexos.features.gaming.enable { ... }`.
No option declaration needed (defined in `gaming.nix`).

### Step 4 — `modules/development.nix`

Change header from `{ config, pkgs, ... }:` to `{ config, lib, pkgs, ... }:`.
Add `options.vexos.features.development.enable = lib.mkEnableOption "development tools"`.
Wrap existing content: `config = lib.mkIf cfg.enable { ... }`.

### Step 5 — `modules/3d-print.nix`

Change header from `{ ... }:` to `{ config, lib, ... }:`.
Add `options.vexos.features.print3d.enable = lib.mkEnableOption "3D printing tools"`.
Wrap existing content: `config = lib.mkIf cfg.enable { ... }`.

Dependency note: `vexos.flatpak.extraApps` is declared in `modules/flatpak.nix`
which remains always-imported. The `extraApps` assignment inside the `config` block
will evaluate to an empty list when `print3d.enable` is false, producing no Flatpak
entries. No changes needed to `flatpak.nix`.

### Step 6 — `modules/virtualization.nix`

Change header from `{ pkgs, config, ... }:` to `{ config, lib, pkgs, ... }:`.
Add `options.vexos.features.virtualization.enable = lib.mkEnableOption "virtualization stack"`.
Wrap existing content: `config = lib.mkIf cfg.enable { ... }`.

### Step 7 — `template/features.nix`

Create in the same style as `template/server-services.nix`: a commented-out
template that `just enable-feature` copies to `/etc/nixos/features.nix` on first use.

```nix
# /etc/nixos/features.nix
# Optional feature toggles for this VexOS host.
# Managed by `just enable-feature <feature>` / `just disable-feature <feature>`.
# After editing, run `just rebuild` to apply.
#
# Available features (desktop role):
#   gaming        — Steam, Proton-GE, GameMode, Gamescope, Wine, controllers,
#                   32-bit GPU libs, SCX LAVD scheduler, gaming kernel params
#   development   — Docker, VSCodium, Python, Node, Go, Claude Code, Nix LSP
#   print3d       — Blender and OrcaSlicer (via Flatpak)
#   virtualization — libvirtd/KVM, QEMU-KVM, GNOME Boxes / virt-manager support
{
  # vexos.features.gaming.enable        = false;
  # vexos.features.development.enable   = false;
  # vexos.features.print3d.enable       = false;
  # vexos.features.virtualization.enable = false;
}
```

### Step 8 — `flake.nix`

Add `featuresModule` alongside `serverServicesModule`:

```nix
featuresModule =
  let path = /etc/nixos/features.nix;
  in if builtins.pathExists path then [ path ] else [];
```

Add `featuresModule` to the `desktop` role's `extraModules` in the `roles` table:

```nix
desktop = {
  homeFile     = ./home-desktop.nix;
  baseModules  = commonBase ++ [ upModule ];
  extraModules = featuresModule;
};
```

No other roles are changed. The optional feature modules are desktop-only currently.

### Step 9 — `justfile`

Add three new recipes. They are `[private]` (hidden from default listing) and
exposed in the default recipe's help block for the desktop role condition.

**`features`** — lists enabled/disabled status, mirrors `just services`:
```bash
features: _require-desktop-role
  # reads /etc/nixos/features.nix and prints ✓/✗ for each feature
```

**`enable-feature feature`** — copies template on first use, sets option to true,
offers rebuild. Named `enable-feature` (not `enable`) to avoid conflicting with the
existing server `enable` recipe.

**`disable-feature feature`** — sets option to false or removes the line.

**`_require-desktop-role`** — private guard, similar to `_require-server-role`:
```bash
variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
if [[ "$variant" != *desktop* && "$variant" != *htpc* ]]; then
  echo "error: feature recipes are only available on desktop/htpc roles."
  exit 1
fi
```

Update the `default` recipe's help block to show feature recipes when the variant
contains `desktop`.

---

## 5. Dependencies

No new external dependencies. All patterns already exist in the codebase.
Context7 NixOS manual confirms the `options` + `config = lib.mkIf cfg.enable`
pattern is the canonical NixOS way to write opt-in modules.

---

## 6. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Existing desktop installs lose gaming/dev/etc on next rebuild | Medium | Commit message must note this; users run `just enable-feature gaming` before or after rebuild |
| `gpu-gaming.nix` / `system-gaming.nix` reference option declared in sibling | Low | Works by design — NixOS merges all imported modules before resolving; option is always in scope since all three are imported by `configuration-desktop.nix` |
| `3d-print.nix` depends on `vexos.flatpak.extraApps` from `flatpak.nix` | Low | `flatpak.nix` stays always-imported; the `extraApps` assignment is inside the guarded `config` block so it produces no entries when disabled |
| `development.nix` enables Docker — removal affects existing workstations | Medium | Same as first risk; one-time `just enable-feature development` required |
| `just enable-feature` / `just disable-feature` name collision with server `enable` | None | Using distinct recipe names (`enable-feature`, `disable-feature`) avoids collision |

---

## 7. Files Modified / Created

**Modified:**
- `modules/gaming.nix`
- `modules/gpu-gaming.nix`
- `modules/system-gaming.nix`
- `modules/development.nix`
- `modules/3d-print.nix`
- `modules/virtualization.nix`
- `flake.nix`
- `justfile`

**Created:**
- `template/features.nix`

**Not modified:**
- `configuration-desktop.nix` — import list is unchanged; modules default to disabled via option
- All other `configuration-*.nix` files — optional features are desktop-scoped
