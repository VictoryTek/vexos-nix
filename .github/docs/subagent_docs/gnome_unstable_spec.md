# Specification: GNOME from nixpkgs-unstable alongside stable NixOS 25.05

**Feature name:** `gnome_unstable`
**Spec path:** `.github/docs/subagent_docs/gnome_unstable_spec.md`
**Date:** 2026-03-24

---

## 1. Current State Analysis

### 1.1 Flake inputs (`flake.nix`)

| Input | URL | `nixpkgs.follows` |
|---|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-25.05` | n/a (root) |
| `nix-gaming` | `github:fufexan/nix-gaming` | `nixpkgs` ✓ |
| `home-manager` | `github:nix-community/home-manager/release-25.05` | `nixpkgs` ✓ |
| `nix-cachyos-kernel` | `github:xddxdd/nix-cachyos-kernel/release` | **intentionally absent** (see kernel note) |

There is currently **no `nixpkgs-unstable` input**. All packages across all three
output configurations (`vexos-amd`, `vexos-nvidia`, `vexos-vm`) are sourced
exclusively from the `nixos-25.05` nixpkgs revision.

### 1.2 Outputs structure

```
nixosConfigurations.vexos-amd    ← commonModules ++ [ ./hosts/amd.nix ]
nixosConfigurations.vexos-nvidia ← commonModules ++ [ ./hosts/nvidia.nix ]
nixosConfigurations.vexos-vm     ← commonModules ++ [ ./hosts/vm.nix ]
nixosModules.base                ← consumed by template/etc-nixos-flake.nix on the live host
```

`specialArgs = { inherit inputs; }` is already passed to all three
`nixpkgs.lib.nixosSystem` calls, giving every module access to the full inputs
attrset.

### 1.3 Overlay architecture already in use

`flake.nix` already defines `cachyosOverlayModule` as an inline NixOS module
that sets `nixpkgs.overlays = [ nix-cachyos-kernel.overlays.default ]` and
includes it in `commonModules`. This pattern is the correct, idiomatic place
to introduce a second overlay for unstable packages.

### 1.4 `modules/desktop.nix` — current GNOME configuration

The GNOME desktop module currently:

- Enables `services.xserver.desktopManager.gnome` and GDM Wayland.
- Configures `xdg.portal` with `xdg-desktop-portal-gnome`.
- Sets `environment.gnome.excludePackages` to prune bloat.
- Installs four application-level packages from stable `pkgs`:
  - `gnome-tweaks`
  - `gnome-extension-manager`
  - `dconf-editor`
  - `gnomeExtensions.appindicator`
- Configures fonts, printing, and Bluetooth.

None of the module arguments declare or consume an `unstable` parameter today.

### 1.5 Host files

`hosts/amd.nix`, `hosts/nvidia.nix`, and `hosts/vm.nix` are thin files that
import `../configuration.nix` plus a GPU module. They add no packages
themselves and do not need modification for this feature.

---

## 2. Problem Definition

The `nixos-25.05` stable branch receives only conservative backports. GNOME and
its ecosystem (extensions, tweaks tooling, gsconnect, etc.) release frequently.
Users on the stable channel are often months behind on:

- Bug-fix releases in `gnome-tweaks` and `gnome-extension-manager`
- New GNOME Shell extension API compatibility
- Minor UX improvements in `dconf-editor` and `gnomeExtensions.*`

The goal is to **selectively source GNOME application packages from
`nixpkgs-unstable`** while keeping the entire rest of the system — including
the kernel, drivers, gaming stack, networking, and PipeWire — on the stable
`nixos-25.05` channel.

---

## 3. Prior Art and Sources Researched

The following six authoritative sources were consulted:

1. **NixOS Wiki — Flakes** (`https://nixos.wiki/wiki/Flakes`)
   Section _"Importing packages from multiple channels"_ documents the canonical
   pattern: add `nixpkgs-unstable` as a separate flake input and introduce it
   via `nixpkgs.overlays` as `pkgs.unstable`.

2. **NixOS Wiki — Overlays** (`https://nixos.wiki/wiki/Overlays`)
   Documents `nixpkgs.overlays` in NixOS configuration, `final`/`prev`
   conventions, and the `gnome.overrideScope` pattern for replacing GNOME-scope
   packages.

3. **NixOS Wiki — GNOME** (`https://nixos.wiki/wiki/GNOME`)
   Documents `environment.gnome.excludePackages`, extension management, and the
   community overlay pattern for `mutter` (dynamic triple buffering), which
   demonstrates that GNOME-scoped overrides are understood and supported.

4. **NixOS Manual — GNOME Desktop** (`https://nixos.org/manual/nixos/stable/#sec-gnome`)
   Official documentation for `services.desktopManager.gnome`,
   `environment.gnome.excludePackages`, `services.xserver.displayManager.gdm`,
   and GNOME module options.

5. **NixOS Manual — Modularity / Replace Modules**
   (`https://nixos.org/manual/nixos/stable/#sec-replace-modules`)
   Shows the `disabledModules` technique for replacing a whole NixOS module from
   unstable, which is relevant for understanding when module-level replacement
   (heavier) is needed vs. package-level overlay (lighter, preferred here).

6. **NixOS Wiki — FAQ / Pinning Nixpkgs** (via Context7: `wiki_nixos_wiki`)
   Documents the `packageOverrides` (non-flake) and overlay (flake) approaches
   for mixing stable and unstable channels, including the pattern:
   ```nix
   unstable = import nixpkgs-unstable { inherit (final) config; ... };
   ```

7. **NixOS Manual — Writing NixOS Modules / specialArgs**
   Confirms that `specialArgs` propagates through all module imports and is the
   standard way to pass extra values (like `inputs`) to modules, but also
   confirms that `nixpkgs.overlays` is the preferred mechanism for adding
   packages from a second channel without proliferating extra function arguments.

---

## 4. Approach Analysis

### 4.1 Option A — `nixpkgs.overlays` with `pkgs.unstable` namespace (RECOMMENDED)

Add `nixpkgs-unstable` as a flake input, define an inline NixOS module that
sets:

```nix
nixpkgs.overlays = [
  (final: prev: {
    unstable = import nixpkgs-unstable {
      inherit (final) config;
      inherit (final.stdenv.hostPlatform) system;
    };
  })
];
```

Include this module in `commonModules`. In `modules/desktop.nix`, reference
GNOME packages as `pkgs.unstable.gnome-tweaks`, etc.

**Pros:**
- Follows the exact canonical pattern documented in the NixOS Wiki "Importing
  packages from multiple channels" section.
- Zero changes to module function signatures — any module that already takes
  `pkgs` can access `pkgs.unstable.X` without declaring a new argument.
- The overlay closes over `nixpkgs-unstable` from the flake outputs scope, so
  `nixosModules.base` (consumed by the thin host template) automatically gains
  the capability without the consumer needing to understand or re-supply the
  unstable input.
- Consistent with the existing `cachyosOverlayModule` pattern already in the
  repo.

**Cons:**
- Evaluates the full unstable nixpkgs tree on first import (cold eval ~5–15 s
  longer; subsequent evals are cached by Nix).
- `pkgs.unstable` becomes a global attribute — any module could accidentally
  use it; this is low risk for a personal config.

### 4.2 Option B — `specialArgs` with an `unstable` argument

Pass a pre-instantiated `unstablePkgs` value through `specialArgs`:

```nix
specialArgs = { inherit inputs; unstable = import inputs.nixpkgs-unstable { ... }; };
```

Then declare `{ ..., unstable, ... }:` in `modules/desktop.nix`.

**Pros:** Explicit — only modules that declare the argument can use it.

**Cons:**
- Requires modifying `modules/desktop.nix` function signature.
- `nixosModules.base` (the exported module for `template/etc-nixos-flake.nix`)
  would need the consumer's flake to also pass `unstable` — this breaks the
  current zero-friction design of `nixosModules.base`.
- `import inputs.nixpkgs-unstable { ... }` called outside the module system
  cannot propagate `config.nixpkgs.config` (allowUnfree etc.) without
  additional boilerplate.

### 4.3 Option C — `disabledModules` + full module replacement

Replace the NixOS GNOME module entirely with the unstable version. Overkill and
high-risk; only appropriate when NixOS module API changes are needed.

**Rejected** — far too broad, breaks `nix flake check` if module API differs.

### 4.4 Decision

**Option A** (`nixpkgs.overlays` / `pkgs.unstable` namespace) is chosen.

It is the idiomatic flake pattern, requires the smallest diff, maintains
backward compatibility for `nixosModules.base` consumers, and matches the
existing overlay architecture already established in the repo.

---

## 5. Proposed Solution Architecture

```
flake.nix
  inputs:
    nixpkgs          → github:NixOS/nixpkgs/nixos-25.05   (unchanged)
    nixpkgs-unstable → github:NixOS/nixpkgs/nixos-unstable (NEW, no .follows)
    ...
  outputs: { self, nixpkgs, nixpkgs-unstable, nix-gaming, nix-cachyos-kernel, ... }
    let
      unstableOverlayModule = {            ← NEW inline NixOS module
        nixpkgs.overlays = [
          (final: prev: {
            unstable = import nixpkgs-unstable {
              inherit (final) config;
              inherit (final.stdenv.hostPlatform) system;
            };
          })
        ];
      };
      commonModules = [
        /etc/nixos/hardware-configuration.nix
        nix-gaming.nixosModules.pipewireLowLatency
        cachyosOverlayModule
        unstableOverlayModule                ← NEW: added to shared modules
      ];
    nixosModules.base = { ... }: {
      imports = [ nix-gaming.nixosModules.pipewireLowLatency ./configuration.nix ];
      nixpkgs.overlays = [
        nix-cachyos-kernel.overlays.default
        (final: prev: {                      ← NEW: same overlay inline
          unstable = import nixpkgs-unstable {
            inherit (final) config;
            inherit (final.stdenv.hostPlatform) system;
          };
        })
      ];
    };

modules/desktop.nix                        ← MODIFIED
  environment.systemPackages = with pkgs; [
    unstable.gnome-tweaks           ← was: gnome-tweaks
    unstable.gnome-extension-manager  ← was: gnome-extension-manager
    unstable.dconf-editor           ← was: dconf-editor
    unstable.gnomeExtensions.appindicator  ← was: gnomeExtensions.appindicator
  ];
```

The GNOME service configuration (`services.xserver.desktopManager`,
`services.displayManager.gdm`, `xdg.portal`) remains bound to stable `pkgs`
through the normal NixOS module system. Only the application-level tools in
`environment.systemPackages` are sourced from unstable.

---

## 6. Implementation Steps

### Step 1 — `flake.nix`: Add `nixpkgs-unstable` input

In the `inputs` block, after the `nixpkgs` entry, add:

```nix
# nixpkgs-unstable: used to supply latest GNOME application packages in
# modules/desktop.nix via the pkgs.unstable overlay.
# Do NOT add inputs.nixpkgs-unstable.follows = "nixpkgs" — that would
# pin unstable to the stable revision, defeating its purpose.
nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
```

### Step 2 — `flake.nix`: Destructure `nixpkgs-unstable` in outputs

Change the `outputs` function signature from:

```nix
outputs = { self, nixpkgs, nix-gaming, nix-cachyos-kernel, ... }@inputs:
```

to:

```nix
outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, nix-cachyos-kernel, ... }@inputs:
```

### Step 3 — `flake.nix`: Define `unstableOverlayModule`

In the `let` block (alongside `cachyosOverlayModule`), add:

```nix
# Inline NixOS module: exposes pkgs.unstable.* sourced from nixpkgs-unstable.
# Used in modules/desktop.nix to pin GNOME application tools to latest.
unstableOverlayModule = {
  nixpkgs.overlays = [
    (final: prev: {
      unstable = import nixpkgs-unstable {
        inherit (final) config;
        inherit (final.stdenv.hostPlatform) system;
      };
    })
  ];
};
```

### Step 4 — `flake.nix`: Add `unstableOverlayModule` to `commonModules`

```nix
commonModules = [
  /etc/nixos/hardware-configuration.nix
  nix-gaming.nixosModules.pipewireLowLatency
  cachyosOverlayModule
  unstableOverlayModule   # ← add this line
];
```

### Step 5 — `flake.nix`: Extend `nixosModules.base` overlay list

The `nixosModules.base` module is consumed by `template/etc-nixos-flake.nix`
on the live host. It must also apply the unstable overlay so that
`configuration.nix` → `modules/desktop.nix` resolves `pkgs.unstable.*`
correctly when the template wrapper is used.

Change `nixosModules.base` from:

```nix
nixpkgs.overlays = [ nix-cachyos-kernel.overlays.default ];
```

to:

```nix
nixpkgs.overlays = [
  nix-cachyos-kernel.overlays.default
  (final: prev: {
    unstable = import nixpkgs-unstable {
      inherit (final) config;
      inherit (final.stdenv.hostPlatform) system;
    };
  })
];
```

Because `nixpkgs-unstable` is captured in the `outputs` closure, this works
transparently — the template consumer does not need to declare or supply
`nixpkgs-unstable` itself.

### Step 6 — `modules/desktop.nix`: Switch GNOME app packages to unstable

Replace the four packages in `environment.systemPackages` that benefit from
frequent upstream updates:

```nix
environment.systemPackages = with pkgs; [
  unstable.gnome-tweaks              # latest tweaks release
  unstable.gnome-extension-manager   # latest extension manager
  unstable.dconf-editor              # latest dconf editor
  unstable.gnomeExtensions.appindicator  # latest appindicator ext
];
```

Everything else in `modules/desktop.nix` (services, XDG portal, fonts,
printing, Bluetooth) remains unchanged and continues to use stable `pkgs`.

---

## 7. Files to Be Modified

| File | Change |
|---|---|
| `flake.nix` | Add `nixpkgs-unstable` input; destructure in outputs; define `unstableOverlayModule`; add to `commonModules`; extend `nixosModules.base` overlays list |
| `modules/desktop.nix` | Switch 4 packages to `pkgs.unstable.*` |

No other files require changes. `configuration.nix`, host files, and all other
modules are untouched.

---

## 8. Package Scope Decision — What to Pull from Unstable

### Tier 1 — Application tools (THIS SPEC, low risk)

These packages are standalone GUI tools with few system-level runtime
dependencies. Version mismatches between stable and unstable GLib/GTK are rare
at this layer and quickly catchable by end-users.

| Package | Reason |
|---|---|
| `gnome-tweaks` | Frequently updated; exposes new GNOME preferences as the DE evolves |
| `gnome-extension-manager` | Extension API evolves with each GNOME Shell release |
| `dconf-editor` | Minor but frequent UI improvements |
| `gnomeExtensions.appindicator` | Tracks GNOME Shell API releases |

### Tier 2 — GNOME core (NOT in this spec, document as upgrade path)

Replacing `mutter`, `gnome-shell`, or `gnome-control-center` from unstable
requires the `gnome.overrideScope` pattern documented in the NixOS Overlays
wiki:

```nix
# Example — NOT implemented in this spec, provided for reference:
nixpkgs.overlays = [
  (final: prev: {
    gnome = prev.gnome.overrideScope (gfinal: gprev: {
      mutter       = gprev.mutter.override { ... };      # or from unstable
      gnome-shell  = final.unstable.gnome-shell;
    });
  })
];
```

This approach carries significant risk of runtime incompatibilities between
unstable GNOME core libraries and the stable system's GLib, GTK4, libadwaita,
and systemd. Keep Tier 2 out of scope for this spec; revisit if stable 25.05
cannot be upgraded in time to track a required GNOME Shell extension API change.

---

## 9. `nixpkgs.follows` Policy for `nixpkgs-unstable`

**Do NOT add `inputs.nixpkgs-unstable.follows = "nixpkgs"`.**

Rationale:
- Adding `follows = "nixpkgs"` would cause `nixpkgs-unstable` to resolve to the
  same commit as the stable `nixos-25.05` channel, making the "unstable" input
  identical to stable and defeating the feature entirely.
- Per the project's own flake comment on `nix-cachyos-kernel`, some inputs have
  intentional independence from the root nixpkgs pin for functional reasons.
  `nixpkgs-unstable` is another such case — its independence is the feature.
- The standard community pattern (NixOS Wiki, multiple sample configs) confirms
  this: `nixpkgs-unstable` is always an independent input with its own lock
  entry.

`nix flake lock` will create a separate `nixpkgs-unstable` entry in
`flake.lock`. To update only the unstable channel without touching stable:

```sh
nix flake update nixpkgs-unstable
```

---

## 10. Risks and Mitigations

| Risk | Likelihood | Severity | Mitigation |
|---|---|---|---|
| **Evaluation-time increase** (second nixpkgs eval tree) | High (always occurs) | Low (5–15 s on cold eval, cached on repeat) | Accept; this is the standard cost of the pattern |
| **Build cache miss** for unstable packages | Medium (unstable updates frequently) | Low (build time cost only; cache.nixos.org covers most unstable builds) | Accept; unstable builds are cache-backed by Hydra |
| **Runtime library conflict** (e.g., unstable app needs newer GTK than stable provides) | Low for Tier 1 app tools | Medium (app might crash) | Scope spec to Tier 1 only; monitor after each `nix flake update nixpkgs-unstable` |
| **`xdg.portal` version mismatch** | Very low (portal kept on stable) | Medium (screen sharing breakage) | `xdg-desktop-portal-gnome` is NOT moved to unstable in this spec; it stays on stable alongside the portal service |
| **`gnome-extension-manager` UI regression** | Low | Low | Per-update validation; rollback with `nixos-rebuild switch --rollback` |
| **`nix flake check` failure after adding unstable input** | Low | High | Covered by the review phase dry-build validation |
| **`nixosModules.base` consumer breakage** | Very low (overlay closes over outer scope) | High if it occurs | The unstable overlay closure captures `nixpkgs-unstable` from the outputs scope — the consumer (`template/etc-nixos-flake.nix`) does not need to supply it separately |
| **`system.stateVersion` accidentally changed** | N/A | Critical | This spec makes NO changes to `system.stateVersion` |

---

## 11. Validation Criteria

The implementation is complete when all of the following pass:

1. `nix flake check` exits 0.
2. `sudo nixos-rebuild dry-build --flake .#vexos-amd` succeeds.
3. `sudo nixos-rebuild dry-build --flake .#vexos-nvidia` succeeds.
4. `sudo nixos-rebuild dry-build --flake .#vexos-vm` succeeds.
5. `git ls-files | grep hardware-configuration.nix` returns empty (no hardware
   config in repo).
6. `grep system.stateVersion configuration.nix` confirms the value is unchanged.
7. `nix eval .#nixosConfigurations.vexos-amd.config.environment.systemPackages \
   --apply 'ps: builtins.map (p: p.pname or p.name) ps' \
   | grep -q gnome-tweaks` confirms the package resolves.

---

## 12. Update Workflow (Post-Implementation)

To refresh only GNOME packages to the latest unstable:

```sh
# From repo root:
nix flake update nixpkgs-unstable
# Then rebuild:
sudo nixos-rebuild switch --flake .#vexos-amd   # or nvidia/vm
```

To update everything (stable + unstable + other inputs):

```sh
nix flake update
sudo nixos-rebuild switch --flake .#vexos-amd
```

---

## 13. Summary of Findings

- The vexos-nix flake already uses an overlay-module pattern
  (`cachyosOverlayModule`) that is the perfect structural template for adding
  the unstable overlay.
- The correct and idiomatic NixOS flake approach is to add `nixpkgs-unstable`
  as an independent (no `follows`) flake input and expose it via
  `nixpkgs.overlays` as `pkgs.unstable`.
- Only four GNOME application tools in `modules/desktop.nix` should migrate to
  `pkgs.unstable.*`; all GNOME services, portals, and system-level components
  remain on stable to avoid library incompatibility risk.
- Two files require modification: `flake.nix` and `modules/desktop.nix`.
- `nixosModules.base` (consumed by the live-host template) must also receive
  the unstable overlay inline to remain functional; this is done via a closure
  over `nixpkgs-unstable` in the flake's `outputs` scope — no changes are
  required in `template/etc-nixos-flake.nix`.
- `system.stateVersion` is not touched. `hardware-configuration.nix` is not
  touched. Preflight checks remain valid.
