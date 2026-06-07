# Spec: Fix `system` deprecation warning in nixpkgs.lib.nixosSystem

## Current State Analysis

`flake.nix` defines:

```nix
system = "x86_64-linux";  # line 52
```

And passes it as a top-level argument to `nixpkgs.lib.nixosSystem` in `mkHost`:

```nix
nixpkgs.lib.nixosSystem {
  inherit system;           # line 214 — DEPRECATED
  specialArgs = { inherit inputs; };
  modules = [...];
};
```

In NixOS 25.05+ (and the project's current `nixos-25.11` pin), nixpkgs evaluates the `system`
argument via a compatibility shim that emits:

```
evaluation warning: 'system' has been renamed to/replaced by 'stdenv.hostPlatform.system'
```

This warning fires on every `nix` command that evaluates the flake, including
`nix flake show`, `nixos-rebuild`, and module evaluation in editors.

## Problem Definition

The `system` top-level argument to `nixpkgs.lib.nixosSystem` is deprecated.
The shim still works but generates a noisy warning on every evaluation.

Affected location: **`flake.nix` line 214 only.**

The two overlay uses at lines 61 and 307 (`inherit (final.stdenv.hostPlatform) system;`)
are already correct and must not be changed.

## Proposed Solution Architecture

Replace the top-level `system` argument with an inline module that sets
`nixpkgs.hostPlatform`. This is the official recommended migration path per
the nixpkgs changelog and NixOS Wiki.

**Before:**
```nix
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = { inherit inputs; };
  modules = [...];
};
```

**After:**
```nix
nixpkgs.lib.nixosSystem {
  specialArgs = { inherit inputs; };
  modules =
    [ { nixpkgs.hostPlatform = system; } ]
    ++ [...];
};
```

`nixpkgs.hostPlatform` is a NixOS module option (type `types.either types.str types.attrs`).
Passing the string `"x86_64-linux"` is correct; nixpkgs converts it to the full platform
attrset internally.

## Implementation Steps

1. In `mkHost` (flake.nix ~line 213–224), remove the `inherit system;` line.
2. Prepend `{ nixpkgs.hostPlatform = system; }` to the existing `modules` list.
3. Leave the `system = "x86_64-linux";` variable at line 52 — it is still used by:
   - `proxmoxOverlayModule` at line 75 (`inputs.proxmox-nixos.overlays.${system}`)
   - The `upModule` package reference at line 68 (hardcoded string, unaffected)

## Dependencies

No new external dependencies. Internal Nix change only. Context7 not required.

## Build/Test Commands (Phase 3)

- `nix flake show` — validates structure, safe (low RAM)
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`

All RAM-safe (single target per command, no parallel evaluation of all 34 outputs).

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `nixpkgs.hostPlatform` conflicts with an existing module setting | Unlikely — no host file sets it; nixpkgs only warns on duplicate if one is forced via `mkForce` |
| Other use of bare `system` variable is broken | The `system` variable stays at line 52; only its pass-through to `nixosSystem` changes |
| Warning persists after fix | Verify by running `nix flake show 2>&1 \| grep warning` — should return empty |
