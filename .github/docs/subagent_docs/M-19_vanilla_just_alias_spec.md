# M-19 — `just` alias broken on the vanilla role

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-19 (BUGS M18) · `home/bash-common.nix`, `configuration-vanilla.nix`

## Current State

`home/bash-common.nix` (imported unconditionally by `home-vanilla.nix`) sets:
```nix
just = "just --justfile /etc/nixos/justfile --working-directory /etc/nixos";
```

`/etc/nixos/justfile` and the `just` binary itself are both provided by
`modules/packages-common.nix` (`environment.etc."nixos/justfile".source = ../justfile;`
+ `pkgs.just` in `environment.systemPackages`) — confirmed by reading that file in
full. `configuration-vanilla.nix` never imports `modules/packages-common.nix`
(confirmed by reading its full import list), and no other module in vanilla's import
chain provides `pkgs.just` either. So on vanilla: the `just` binary isn't installed at
all, and even if it were, the alias would point at a file that's never deployed.

## Problem Definition

The MASTER_PLAN's two suggested fixes trade off differently:
- Importing `packages-common.nix` wholesale would also add `btop`, `inxi`, `pciutils`,
  `git`, `curl`, `wget` — plain CLI utilities, but a real deviation from vanilla's own
  stated design intent ("Intentionally minimal — mirrors what a default
  nixos-generate-config + GNOME desktop selection produces... Does NOT include...
  custom packages"). A stock NixOS+GNOME install doesn't ship any of these by default.
- Making the alias conditional keeps vanilla exactly as minimal as it already declares
  itself to be, and directly targets the actual defect (an alias referencing something
  that was never deployed) rather than pulling in unrelated tooling to paper over it.

Given vanilla's own header comment is explicit about staying minimal, the conditional
alias is the fix that respects the file's stated intent rather than fighting it.

## Proposed Solution

`home/bash-common.nix` already has `osConfig` in scope (used elsewhere in the same file
for `programs.git.settings.user.name`) — use it to check whether the system config
actually deployed the justfile (`osConfig.environment.etc ? "nixos/justfile"`) and only
set the `just` alias when true. This is a build-time check, not a runtime shell
existence test, so it's exact and doesn't add any runtime fallback logic.

## Implementation Steps

1. `home/bash-common.nix` — split `shellAliases` so the `just` entry is merged in
   conditionally via `lib.optionalAttrs (osConfig.environment.etc ? "nixos/justfile")`.

## Configuration Changes

None.

## Risks and Mitigations

- **`osConfig.environment.etc` attribute check** — verified this is the correct way to
  detect the deployed file: `environment.etc."nixos/justfile"` is exactly the option
  `packages-common.nix` sets, so checking for that key's presence in the merged
  `environment.etc` attrset directly reflects whether the file will actually exist on
  the target system.
- **No behavior change for every other role** — all of desktop/server/htpc/
  headless-server/stateless already import `packages-common.nix`, so the alias
  continues to apply there exactly as before; only vanilla's behavior changes (from
  "broken alias" to "no alias, since `just` isn't installed there anyway").
