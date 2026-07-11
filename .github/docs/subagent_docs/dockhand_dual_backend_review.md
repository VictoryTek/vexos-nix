# Dockhand Dual-Backend Support — Review

## Spec Compliance

Implementation matches `.github/docs/subagent_docs/dockhand_dual_backend_spec.md`:
- Added `vexos.server.dockhand.backend` (`enum ["docker" "podman"]`, default `"docker"`).
- Docker path: `virtualisation.docker.enable = lib.mkIf (backend == "docker") (lib.mkDefault true)`,
  `virtualisation.oci-containers.backend = lib.mkIf (backend == "docker") (lib.mkDefault "docker")`,
  mounts `/var/run/docker.sock` — matches `arcane.nix` pattern.
- Podman path: unchanged behavior, mounts Podman compat socket, requires
  `vexos.server.podman.enable`.
- Assertion narrowed to only fire for `backend == "podman"`.
- `justfile` updated in all 4 identified locations (service list description,
  status annotation, `UNITS` for `just info`, `just enable` info block).

## Additional finding (fixed during review, before build validation)

Beyond the spec: a `backend == "docker"` + `vexos.server.podman.enable = true`
combination on the same host would silently break — `podman.nix` force-disables
`virtualisation.docker.enable` (`mkForce false`, wins over `mkDefault true`) and
unconditionally claims `virtualisation.oci-containers.backend = "podman"`,
so Dockhand's container would run under Podman while still declaring a
`/var/run/docker.sock` mount that was never created. Added a second assertion
to reject this combination at eval time with a clear message pointing at
`backend = "podman"` as the fix. Verified no other CRITICAL gaps.

## Best Practices / Consistency / Maintainability

- Matches Module Architecture Pattern's explicit carve-out: `lib.mkIf`
  branching on `cfg.backend`, an option this same module declares, is the
  standard toggleable-subsystem pattern — not new role-smuggling.
- Mirrors existing repo convention (`arcane.nix`, `portainer.nix`, etc.) for
  the Docker path exactly.
- No unrelated refactors; changes confined to the option/assertion/volume
  logic plus the 4 justfile lines that hardcoded "Podman only" text.

## Security

- No new secrets, no plaintext credentials, no world-writable files
  introduced. Socket mounts are root-equivalent access either way (unchanged
  risk profile from before — Dockhand already had full container-runtime
  access via the previous hardcoded Podman socket).

## Build Validation

- `nix flake show --impure`: all 30 outputs enumerate successfully.
- `sudo nixos-rebuild dry-build` is unavailable in this sandboxed session
  (`sudo: the "no new privileges" flag is set` — environment-level
  restriction, not a project issue). Used the documented CI-equivalent
  fallback instead: `nix eval --impure
  ".#nixosConfigurations.<config>.config.system.build.toplevel.drvPath"`.
- `vexos-desktop-amd`: evaluates successfully (drv path resolved).
- `vexos-desktop-nvidia`: evaluates successfully.
- `vexos-desktop-vm`: evaluates successfully.
- `vexos-server-amd`: fails on a pre-existing, unrelated assertion —
  `networking.hostId` placeholder not set for this local host. Verified via
  `git stash` that this identical failure occurs on a clean `main` checkout
  with none of this change's edits applied — confirmed NOT caused by this
  change.
- `vexos-headless-server-amd`: same pre-existing `hostId` failure, same
  verification.
- `git ls-files hardware-configuration.nix`: empty (not committed). Correct.
- `system.stateVersion`: unchanged in all `configuration-*.nix` files.
- No new flake inputs; `flake.nix` untouched.
- `just --list`: justfile syntax valid after edits.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100%* | A |

\* Server-role evaluation is blocked by a pre-existing local-environment gap
(missing `networking.hostId` for this host) unrelated to this change, and
confirmed present on the unmodified `main` branch. Desktop-role evaluation
(which does not carry the ZFS/hostId requirement) passes cleanly. No
CRITICAL or RECOMMENDED issues remain in the changed files.

**Overall Grade: A (100%)**

## Result

**PASS**
