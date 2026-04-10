# Specification: home-manager extraSpecialArgs Gap in nixosModules

## Summary

`home.nix` declares `inputs` as a required formal argument. The `homeManagerModule`
used by direct `nixosConfigurations.*` builds already passes
`extraSpecialArgs = { inherit inputs; }` correctly. However, the two standalone
`nixosModules` exports (`nixosModules.base` and `nixosModules.privacyBase`) do NOT
include `extraSpecialArgs`, so any host that consumes those modules via the
`/etc/nixos/flake.nix` template will fail to evaluate `home.nix` with a Nix
attribute-missing error.

---

## Current State

### home.nix — formal parameter declaration

**File:** `home.nix`, line 5

```nix
{ config, pkgs, lib, inputs, ... }:
```

`inputs` is an **explicitly named** formal argument. In Nix, named formal
arguments (even with the `...` catch-all present) must be supplied by the
caller. If the attribute-set passed by home-manager does not include `inputs`,
evaluation aborts with:

```
error: function 'anonymous lambda' called without required argument 'inputs'
```

### home.nix — active use of `inputs`

`inputs` is currently referenced only inside a comment:

```nix
# TODO: add the 'up' flake input (e.g. inputs.up.url = "github:...") and uncomment:
# inputs.up.packages.${pkgs.stdenv.hostPlatform.system}.default
```

The formal declaration must remain in place because:
1. Removing it would require editing `home.nix` (a separate, unrelated change).
2. The TODO indicates `inputs` will be used in the near future, making this fix
   a prerequisite for that work.
3. Nix evaluates formal args strictly regardless of whether the body references them.

### flake.nix — homeManagerModule (direct builds) — CORRECT

**File:** `flake.nix`, lines ~57–69 (the `homeManagerModule` let-binding)

```nix
homeManagerModule = {
  imports = [ home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs    = true;
    useUserPackages  = true;
    extraSpecialArgs = { inherit inputs; };   # ← already present
    users.nimda      = import ./home.nix;
    backupFileExtension = "backup";
  };
};
```

All `nixosConfigurations.*` outputs include this module via `commonModules`.
They are **not affected** by this gap.

### flake.nix — nixosModules.base — MISSING extraSpecialArgs

**File:** `flake.nix`, inside `nixosModules.base`

```nix
base = { ... }: {
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    ./configuration.nix
  ];
  home-manager = {
    useGlobalPkgs   = true;
    useUserPackages = true;
    # extraSpecialArgs is ABSENT — inputs will not be in scope for home.nix
    users.nimda     = import ./home.nix;
  };
  ...
};
```

### flake.nix — nixosModules.privacyBase — MISSING extraSpecialArgs

**File:** `flake.nix`, inside `nixosModules.privacyBase`

```nix
privacyBase = { ... }: {
  _module.args.inputs = inputs;   # makes inputs available to NixOS modules only
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    ./configuration-privacy.nix
  ];
  home-manager = {
    useGlobalPkgs   = true;
    useUserPackages = true;
    # extraSpecialArgs is ABSENT — _module.args does NOT propagate into
    # home-manager's own module evaluation context
    users.nimda     = import ./home.nix;
  };
  ...
};
```

**Note on `_module.args.inputs`:** Setting `_module.args.inputs = inputs` only
injects `inputs` into the NixOS module evaluation context (i.e., NixOS modules
that declare `inputs` as a formal arg). Home-manager runs an entirely separate
module evaluation context and does not inherit `_module.args` from NixOS. The
`home-manager.extraSpecialArgs` option is the only supported mechanism for
passing extra arguments into home-manager modules.

---

## Root Cause

The `homeManagerModule` let-binding (used by `nixosConfigurations.*`) was
updated to include `extraSpecialArgs` but the same fix was not applied to the
`nixosModules.base` and `nixosModules.privacyBase` exports, which are
structurally distinct blocks that each configure home-manager independently.

---

## Proposed Fix

### Location

**File:** `flake.nix` only. No other file requires modification.

### Change 1 — nixosModules.base

Add `extraSpecialArgs = { inherit inputs; };` to the `home-manager` attribute
set inside `nixosModules.base`:

```nix
# BEFORE
home-manager = {
  useGlobalPkgs   = true;
  useUserPackages = true;
  users.nimda     = import ./home.nix;
};

# AFTER
home-manager = {
  useGlobalPkgs    = true;
  useUserPackages  = true;
  extraSpecialArgs = { inherit inputs; };
  users.nimda      = import ./home.nix;
};
```

### Change 2 — nixosModules.privacyBase

Apply the identical addition inside `nixosModules.privacyBase`:

```nix
# BEFORE
home-manager = {
  useGlobalPkgs   = true;
  useUserPackages = true;
  users.nimda     = import ./home.nix;
};

# AFTER
home-manager = {
  useGlobalPkgs    = true;
  useUserPackages  = true;
  extraSpecialArgs = { inherit inputs; };
  users.nimda      = import ./home.nix;
};
```

---

## Files to Modify

| File | Change |
|------|--------|
| `flake.nix` | Add `extraSpecialArgs = { inherit inputs; };` to `nixosModules.base` home-manager block |
| `flake.nix` | Add `extraSpecialArgs = { inherit inputs; };` to `nixosModules.privacyBase` home-manager block |

**No other files need to be modified.** `home.nix`, `home/photogimp.nix`,
`configuration.nix`, and `configuration-privacy.nix` are all correct as-is.

---

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `inputs` passed to home.nix but not needed yet (wasted arg) | Low — no functional harm | None needed; formal arg is already declared |
| Other home modules (e.g. `home/photogimp.nix`) declaring `inputs` without receiving it | None — `photogimp.nix` uses `{ config, lib, pkgs, ... }:` only | No change needed |
| Future home modules added without `inputs` formal arg accidentally relying on it via closure | Low | Convention: only modules that explicitly declare `inputs` will use it |
| Breaking the `nixosConfigurations.*` direct builds | None — `homeManagerModule` is separate and already correct | Not touched by this fix |

---

## Verification Steps

After applying the fix:

1. **Flake structure check:**
   ```bash
   nix flake check
   ```
   Must exit 0 with no evaluation errors.

2. **Dry-build against all three primary variants:**
   ```bash
   sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
   sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
   sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
   ```

3. **Confirm `hardware-configuration.nix` is not tracked:**
   ```bash
   git ls-files | grep hardware-configuration
   # Expected: no output
   ```

4. **Confirm `system.stateVersion` is unchanged** in `configuration.nix`.

5. **Manual spot-check:** Confirm `nixosModules.base` and `nixosModules.privacyBase`
   in `flake.nix` both contain `extraSpecialArgs = { inherit inputs; };` after the edit.

---

## Implementation Notes

- The attribute alignment style in the existing code uses 2-space padding after
  `useGlobalPkgs` and `useUserPackages`. The new line should align `extraSpecialArgs`
  consistently with those attributes (using one extra space to right-align the `=`
  with `useUserPackages`), matching the style already used in `homeManagerModule`.
- The fix is purely additive — no existing lines are removed or reordered.
- `backupFileExtension = "backup"` is present in `homeManagerModule` but intentionally
  absent from `nixosModules.base` and `nixosModules.privacyBase`. Do NOT add it here;
  that is a separate concern out of scope for this fix.
