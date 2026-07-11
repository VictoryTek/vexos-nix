# Portainer & Arcane Dual-Backend Support + Arcane justfile Wiring — Review

## Spec Compliance

Implementation matches
`.github/docs/subagent_docs/portainer_arcane_dual_backend_spec.md`:

- `modules/server/portainer.nix`: added `backend` option (enum, default
  `"docker"`), two assertions (podman-required / docker-conflicts-with-podman),
  conditional `virtualisation.docker.enable` / `oci-containers.backend`,
  conditional socket mount. Comment block updated.
- `modules/server/arcane.nix`: identical set of changes. Also changed
  `oci-containers.backend = "docker"` (previously a forceful, non-`mkDefault`
  assignment) to `lib.mkIf (cfg.backend == "docker") (lib.mkDefault "docker")`
  — necessary for the new docker/podman-conflict assertion to be meaningful,
  and brings Arcane in line with the `mkDefault` convention already used by
  Portainer, Dockhand, and the rest of the Docker-backed service modules.
- `justfile`: Portainer's three existing references (status annotation, `just
  status` UNITS, `just enable` info block) reworded to reflect the
  configurable backend instead of a hard Docker requirement.
- `justfile`: Arcane fully wired in — `_server_service_names`, `_svc` entry,
  `just info` status line, `just status` UNITS, `_check` entry, and a new
  `just enable arcane` info block mirroring the existing `arcane.nix` comment
  content (appUrl/environmentFile prerequisites, secret generation steps).
- `template/server-services.nix`: reworded two inline comments
  ("requires docker" → dropped, "Docker management UI" → "Docker/Podman
  management UI") to match.

## Best Practices / Consistency / Maintainability

- Same Module Architecture Pattern carve-out as the prior Dockhand change:
  `lib.mkIf` branching on `cfg.backend`, an option each module declares
  itself — not new role-smuggling.
- No unrelated refactors. Arcane's existing `appUrl`/`environmentFile`
  assertions, secret-file requirements, and PUID/PGID environment left
  untouched.
- justfile insertions placed alphabetically/consistently with existing
  entries (arcane before attic in `_svc`, `_check`, and the enable-info case
  statement; adguard/arcane/arr ordering in `_server_service_names`).

## Security

- No new secrets, no plaintext credentials introduced. Arcane's existing
  `environmentFile`-based secret handling (ENCRYPTION_KEY/JWT_SECRET) is
  unchanged — only the container socket/runtime selection changed.
- Socket mounts carry the same root-equivalent access as before regardless
  of backend (Docker or Podman compat socket) — no change in risk profile.

## Functional Verification (beyond static build checks)

Used `nixosConfigurations.<cfg>.extendModules` to directly exercise the new
assertions and confirm correct behavior:

1. `arcane.backend = "podman"` + `portainer.backend = "docker"` (default) +
   `podman.enable = true` → **correctly fails** with only the Portainer
   docker/podman-conflict assertion (Arcane's podman config is valid and
   raises no error).
2. Same host, `portainer.backend = "podman"` → **both services build
   successfully** (`system.build.toplevel.drvPath` resolves).
3. All three UIs (arcane, portainer, dockhand) enabled with default
   `backend = "docker"`, no Podman enabled → **builds successfully**.

This confirms the "support both, require only the one selected" behavior
the user asked for works as intended, not just that it evaluates.

## Build Validation

- `nix flake show --impure`: all 30 outputs enumerate successfully.
- `sudo nixos-rebuild dry-build` unavailable in this sandboxed session (same
  environment constraint as the prior Dockhand change) — used the documented
  CI-equivalent fallback (`nix eval --impure
  .../system.build.toplevel.drvPath`).
- `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm`: all
  evaluate successfully.
- `vexos-server-amd`: base config fails on the same pre-existing, unrelated
  `networking.hostId` placeholder assertion documented in the prior Dockhand
  review (confirmed then via `git stash` to exist on unmodified `main`).
  Worked around for functional testing by injecting `networking.hostId` via
  `extendModules` (see Functional Verification above), which isolates the
  new logic from that unrelated gap and confirms correctness directly.
- `git ls-files hardware-configuration.nix`: empty (not committed).
- `system.stateVersion`: unchanged (`git diff --stat` on all
  `configuration-*.nix` files is empty).
- `flake.nix`: untouched, no new inputs.
- `just --list`: justfile syntax valid after all edits.

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

\* Server-role static evaluation is blocked by a pre-existing, unrelated
local-environment gap (missing `networking.hostId`) confirmed present on
unmodified `main`. Direct functional testing via `extendModules` (isolating
that gap) confirms the new logic in both modules works correctly, including
the specific conflict scenario the user asked to guard against. Desktop-role
evaluation (unaffected by the ZFS/hostId requirement) passes cleanly. No
CRITICAL or RECOMMENDED issues remain in the changed files.

**Overall Grade: A (100%)**

## Result

**PASS**
