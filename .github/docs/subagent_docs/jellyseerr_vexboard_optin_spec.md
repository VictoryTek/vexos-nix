# Spec: jellyseerr removal + vexboard opt-in

## Current State Analysis

- `justfile` lists `jellyseerr` in `_server_service_names`, `available-services`, `service-info`,
  `status`, `services`, and the `service-info` case block. No `modules/server/jellyseerr.nix`
  exists — `seerr.nix` replaced it.
- `configuration-server.nix` sets `vexos.server.vexboard.enable = lib.mkDefault true`, making
  vexboard build on every server variant regardless of user intent.
- `justfile` `enable` recipe contained no mechanism to auto-enable vexboard alongside other services.
- `template/server-services.nix` documented vexboard as "enabled by default".
- `modules/server/vexboard.nix` header comment referenced the now-removed `mkDefault true`.

## Problem Definition

1. `jellyseerr` is deprecated and superseded by `seerr`. It still appears in the available-services
   list, service-info URL map, status map, services display row, and the case block — creating
   confusion for users.
2. Vexboard is supposed to be opt-in (enabled by `just enable <service>`), but `mkDefault true`
   in `configuration-server.nix` caused it to build unconditionally on all server variants,
   including VMs where no services are enabled.

## Proposed Solution

### 1. Remove jellyseerr from all justfile references
- `_server_service_names` variable
- `available-services` `_svc` listing
- `service-info` URL printf map
- `status` UNITS/URLS map
- `services` `_check` row
- `service-info` case block

### 2. Make vexboard opt-in
- Remove `vexos.server.vexboard.enable = lib.mkDefault true` from `configuration-server.nix`.
- Add auto-enable logic to the `enable` recipe: when any service except vexboard is enabled,
  check whether vexboard is already explicitly enabled (uncommented `= true`) in
  `server-services.nix`; if not, write `vexos.server.vexboard.enable = true;` into the file.
- Fix the "already enabled" grep to require no `#` before the option name, so commented-out
  lines in the template do not false-positive.
- Remove the explicit `# vexos.server.vexboard.enable = true;` commented line from the template;
  replace with a plain prose comment so there is nothing for the grep to match.
- Update stale descriptions in justfile and module header comment.

## Implementation Steps

1. `configuration-server.nix` — delete the `mkDefault true` block.
2. `justfile` — remove all 6 jellyseerr references.
3. `justfile` — insert auto-enable vexboard block in the `enable` recipe.
4. `justfile` — fix the vexboard "already enabled" grep to use `^\s*vexos\.server\.vexboard\.enable\s*=\s*true` (no `#` allowed before the key).
5. `template/server-services.nix` — replace the commented `= true` vexboard line with prose.
6. `modules/server/vexboard.nix` — update header comment.

## Files Modified

- `configuration-server.nix`
- `justfile`
- `template/server-services.nix`
- `modules/server/vexboard.nix`

## Build/Test Commands (RAM-safe)

- `nix flake show`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-vm`

## Risks and Mitigations

- Risk: auto-enable grep false-positive on commented lines → mitigated by anchoring the pattern
  to require no `#` before the option name and removing the `= true` commented line from template.
- Risk: jellyseerr removal breaks existing `server-services.nix` files that have
  `vexos.server.jellyseerr.enable = true` — mitigated by the fact that no `jellyseerr.nix` module
  exists, so the option was never defined; existing files with that line already fail evaluation.
