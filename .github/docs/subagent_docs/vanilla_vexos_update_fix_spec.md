# vanilla_vexos_update_fix — Spec

## Current State Analysis

CI failure (GitHub Actions, all 5 `vexos-vanilla-*` eval jobs):

```
error: attribute 'vexos' missing
at modules/nix.nix:117:7:
    116|     environment.systemPackages = [
    117|       pkgs.vexos.vexos-update
```

Commit `3a98c19` ("refactor(nix): move vexos-update out of modules/nix.nix
into pkgs/") moved the inline `pkgs.writeShellScriptBin "vexos-update" ''...''`
out of `modules/nix.nix` into `pkgs/vexos-update/default.nix`, registered as
`pkgs.vexos.vexos-update` via the `customPkgsOverlayModule` overlay
(`pkgs/default.nix`), and changed `modules/nix.nix` to reference it through
that overlay attribute.

`modules/nix.nix` is a **universal base module** (per its own header: "Applies
to all roles") imported by every role's `configuration-*.nix`, including
`configuration-vanilla.nix`.

However, `customPkgsOverlayModule` (which defines `pkgs.vexos.*`) is only
included in `commonBase`, and `commonBase` is only used by
desktop/htpc/stateless/server/headless-server roles. The `vanilla` role's
`roles.vanilla.baseModules` in `flake.nix` is deliberately `[]` — vanilla is
documented as "stock NixOS baseline... Does NOT include... custom packages."

Before the refactor this was fine: `pkgs.writeShellScriptBin` is plain
`nixpkgs`, no overlay needed. After the refactor, `modules/nix.nix` — a
module every role including vanilla depends on for correct Nix daemon config
— gained a hard, undocumented dependency on an overlay that vanilla
intentionally omits. This is a regression, not a vanilla-specific gap:
vanilla still needs `vexos-update` (it's the update script for `just update`
and the Up GUI, used on every role), it just doesn't have `pkgs.vexos.*`
available.

## Problem Definition

`modules/nix.nix:117` references `pkgs.vexos.vexos-update`, which is
undefined unless `customPkgsOverlayModule` is applied. Vanilla's
`baseModules = []` never applies it, so all 5 `vexos-vanilla-*` outputs fail
to evaluate.

## Proposed Solution

Make `modules/nix.nix` self-contained: reference the `vexos-update` package
directly via `pkgs.callPackage ../pkgs/vexos-update { }` instead of going
through the `pkgs.vexos` overlay namespace. `pkgs/vexos-update/default.nix`
only takes `{ writeShellApplication }` as an argument — a plain nixpkgs
attribute available on every `pkgs` instance regardless of overlays — so
`callPackage` works identically with or without `customPkgsOverlayModule`.

This does not reintroduce the overlay registration removed from
`pkgs/default.nix` (other consumers — `just update` invoking
`nix build .#... ` or similar — are unaffected since `pkgs.vexos.vexos-update`
stays registered there for any code that wants it via the overlay; only
`modules/nix.nix`'s reference changes). No change to `pkgs/default.nix` or
`pkgs/vexos-update/default.nix` is required.

### Implementation Steps

1. In `modules/nix.nix`, change:
   ```nix
   environment.systemPackages = [
     pkgs.vexos.vexos-update
   ];
   ```
   to:
   ```nix
   environment.systemPackages = [
     (pkgs.callPackage ../pkgs/vexos-update { })
   ];
   ```
2. Update the adjacent comment (currently says "Implementation lives in
   pkgs/vexos-update/ ... rather than embedded here") to note the package is
   called directly (not via the `pkgs.vexos` overlay) so `modules/nix.nix`
   stays overlay-independent for vanilla.

No other files require changes — this is a one-line reference fix confined
to the universal module that broke.

## Dependencies

None new. No Context7 lookup required (internal-only change, no external
library).

## Risks and Mitigations

- **Risk:** Two separate `vexos-update` derivations exist in the Nix store
  (one via `pkgs.callPackage` direct, one via the overlay) if the overlay
  path is exercised elsewhere. **Mitigation:** They are structurally
  identical derivations (same `callPackage ./vexos-update { }` call with the
  same fixed inputs), so Nix content-addresses them to the same store path —
  no duplication, no behavior drift.
- **Risk:** Future edits to `pkgs/vexos-update/default.nix` requiring overlay
  inputs would need this call site revisited. **Mitigation:** the file only
  takes `{ writeShellApplication }`, a base nixpkgs attribute; not expected
  to change.

## Validation Plan

- `nix flake show --impure` (structure check)
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
- `nix eval --impure ".#nixosConfigurations.vexos-vanilla-amd.config.system.build.toplevel.drvPath"`
  (mirrors the failing CI job; not run locally by default per FORBIDDEN
  COMMANDS/resource constraints — full vanilla matrix is CI's job, but a
  single-variant eval is safe to spot-check)
- `bash scripts/preflight.sh`
