# H-18 — mkHost vs mkBaseModule duplicate baseModules logic

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN ARCH 1.2 · `flake.nix:302-331` (`mkBaseModule`) vs `flake.nix:211-245` (`mkHost`)

## Current State (read in full — `flake.nix:1-423`)

`mkHost` (used for `nixosConfigurations`) takes each role's module set entirely from
`roles.${role}.baseModules` (`flake.nix:139-184`), which is itself built from the shared
`commonBase = [ unstableOverlayModule customPkgsOverlayModule ]` plus per-role additions
(`upModule`, `proxmoxBase`, `sopsBase`, `vexboardBase`) — `vanilla.baseModules = []`.

`mkBaseModule` (used for the `nixosModules.*Base` exports consumed by
`template/etc-nixos-flake.nix` on installed hosts) does **not** reuse `baseModules` at
all. It re-derives the same information three separate ways, each duplicated and each a
chance to drift from the `roles` table:

1. `nixpkgs.overlays = [ (unstable overlay, re-inlined) (import ./pkgs) ]` —
   **unconditional**, not gated by role at all. This is the actual bug: `vanilla`'s
   `baseModules` is `[]` (deliberately no unstable/custom-pkgs overlays — vanilla is "no
   custom packages, no overlays" per its own doc comment), but `mkBaseModule`'s inline
   overlay block runs for every role including vanilla, so `nixosModules.vanillaBase`
   silently gets both overlays that `vexos-vanilla-*` (built via `mkHost`) never has.
2. `environment.systemPackages = lib.optional (role != "headless-server" && role !=
   "vanilla") up.packages...` — a hand-written string-comparison standing in for "does
   this role's `baseModules` include `upModule`". Correct today only because it happens
   to match the current `roles` table by coincidence; a future edit to `roles` (adding a
   role, or removing `upModule` from an existing one) would silently desync this line.
3. `lib.optionals (role == "server" || role == "headless-server") [ proxmoxOverlayModule
   inputs.proxmox-nixos.nixosModules.proxmox-ve sops-nix.nixosModules.sops ]` and a
   second `lib.optionals` block for vexboard — same re-derivation pattern as #2, this
   time duplicating `proxmoxBase` + `sopsBase` + `vexboardBase` membership by role name
   instead of reading `roles.${role}.baseModules`.

## Problem Definition

Three independent copies of "which modules does role X get" that must be kept in sync by
hand. #1 has already drifted (the vanilla overlay bug). #2 and #3 haven't drifted yet but
are exactly the same class of risk the `roles` table's own doc comment
(`flake.nix:134-138`) says it exists to prevent.

## Proposed Solution

Replace `mkBaseModule`'s `imports` list and delete the three duplicated blocks, reading
`roles.${role}.baseModules` directly instead:

```nix
mkBaseModule = role: configFile: { config, ... }: {
  imports =
    [ home-manager.nixosModules.home-manager configFile ]
    ++ roles.${role}.baseModules
    ++ roles.${role}.extraModules;
  home-manager = { ... unchanged ... };
};
```

This removes the re-inlined overlay block, the `environment.systemPackages` predicate,
and both `lib.optionals (role == ...)` blocks in one change — all three were re-deriving
subsets of exactly what `roles.${role}.baseModules` already is. `vanilla.baseModules =
[]` now applies identically in both `mkHost` and `mkBaseModule`, fixing the overlay leak.

Import order changes slightly: `baseModules` (overlays/upModule/proxmox/sops/vexboard)
now come after `configFile` and before `extraModules`, rather than being scattered before
and after `extraModules` as today. NixOS's module system merges declaratively regardless
of `imports` list order (no evaluation-order dependency for plain option definitions —
the existing comment about `proxmoxOverlayModule` needing to be imported directly rather
than through `modules/server/proxmox.nix` is about avoiding a `_module.args`
self-reference inside that file, not about list position), so this reordering carries no
behavioral risk.

## Implementation Steps

1. `flake.nix` — replace `mkBaseModule`'s body as above. No other function
   (`mkHost`, `roles`, `commonBase`, etc.) changes.

## Configuration Changes

None — `hostList`/`nixosConfigurations` (built via `mkHost`) are entirely unaffected;
only `nixosModules.*Base` (built via `mkBaseModule`) changes, and only to *remove* the
vanilla overlay leak (a behavior fix, not a new capability).

## Risks and Mitigations

- **Order sensitivity**: addressed above — NixOS module merging is declarative, not
  import-order-sensitive, for the kinds of definitions present here (no competing
  `mkOverride`/`mkForce` priorities between `baseModules` and `extraModules` that would
  make order matter).
- **Vanilla behavior change**: intentional and is the bug fix — `nixosModules.vanillaBase`
  will no longer carry the unstable/custom-pkgs overlays, matching both `vexos-vanilla-*`
  (`mkHost`) and vanilla's own documented "no custom GPU, no overlays" positioning
  (`flake.nix:362-364`).
