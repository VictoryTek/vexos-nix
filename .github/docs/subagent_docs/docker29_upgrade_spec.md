# docker29_upgrade_spec.md

## Current State
`virtualisation.docker` in both `modules/development.nix` and `modules/server/docker.nix`
uses the nixpkgs default Docker package, which in nixpkgs ≥ 2026-06-03 resolves to
`docker_28`. That package has been marked **insecure** by nixpkgs maintainers because
docker 28 has been unmaintained since November 2025.

## Problem
`vexos-update` fails at `nixos-rebuild switch` with:

```
error: Package 'docker-28.5.2' is marked as insecure, refusing to evaluate.
Known issues: docker_28 has been unmaintained since November 2025,
              use docker_29 or newer instead
```

## Proposed Solution
Pin `virtualisation.docker.package = pkgs.docker_29;` in both files that
configure the Docker virtualisation module. This is the explicit, upstream-prescribed
remediation and upgrades the runtime to Docker 29, which is actively maintained.

## Files to Modify
- `modules/development.nix` — desktop role Docker enablement
- `modules/server/docker.nix` — server role Docker enablement

## Implementation Steps
1. Add `package = pkgs.docker_29;` to the `virtualisation.docker` attrset in
   `modules/development.nix`.
2. Add `package = pkgs.docker_29;` to the `virtualisation.docker` attrset in
   `modules/server/docker.nix`.

## Build/Test Commands (RAM-safe)
- `nix flake show`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`

## Risks
None — docker_29 is a drop-in replacement for docker_28 at the socket/CLI level.
Container data and volumes are unaffected by the package pin change.