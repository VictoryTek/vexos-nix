# Portainer & Arcane Dual-Backend Support + Arcane justfile Wiring — Spec

## Current State Analysis

Following on from `dockhand_dual_backend_spec.md` (already implemented), two
more container-management-UI modules are hardcoded to a single backend:

**`modules/server/portainer.nix`**
- Unconditionally sets `virtualisation.docker.enable = lib.mkDefault true;`
  and `virtualisation.oci-containers.backend = lib.mkDefault "docker";`.
- Mounts `/var/run/docker.sock:/var/run/docker.sock:ro` — hardcoded.
- No Podman path, despite `justfile` already describing it as managing
  "Docker/Podman stacks" (`_svc portainer "Web UI for managing Docker/Podman
  stacks"`, justfile:1300) — a pre-existing doc/code mismatch this change
  resolves.

**`modules/server/arcane.nix`**
- Unconditionally sets `virtualisation.docker.enable = lib.mkDefault true;`
  and `virtualisation.oci-containers.backend = "docker";` (non-default, unlike
  portainer's `mkDefault`).
- Mounts `/var/run/docker.sock:/var/run/docker.sock` — hardcoded.
- Both Arcane and Portainer are plain Docker-API-socket consumers (same
  category as Dockhand), and Podman's `dockerCompat = true`
  (`modules/server/podman.nix`) exposes exactly that API via
  `/run/podman/podman.sock` — so both can run against either backend using
  the same mechanism already implemented for Dockhand.
- **Separate pre-existing gap:** Arcane is imported in
  `modules/server/default.nix` and referenced in `modules/server/proxy.nix`
  and `template/server-services.nix`, but is completely absent from
  `justfile` — no `_server_service_names` entry, no `_svc` line, no
  `just status`/`just info` case, no `_check` entry, no `just enable` info
  block. It is currently only reachable by hand-editing
  `/etc/nixos/server-services.nix`. User confirmed this should be fixed as
  part of this task.

## Problem Definition

Same as Dockhand: users who choose Docker as their runtime should not be
forced into Podman (or vice versa) to run these two container-management
UIs. Additionally, Arcane needs to become a first-class `just`-managed
service like every sibling module.

## Proposed Solution

Apply the identical `backend` option pattern used in
`modules/server/dockhand.nix` to both modules:

- `vexos.server.portainer.backend` / `vexos.server.arcane.backend`:
  `lib.types.enum [ "docker" "podman" ]`, default `"docker"`.
- `"docker"`: `virtualisation.docker.enable = lib.mkIf (cfg.backend ==
  "docker") (lib.mkDefault true);` /
  `virtualisation.oci-containers.backend = lib.mkIf (cfg.backend ==
  "docker") (lib.mkDefault "docker");`, mount `/var/run/docker.sock`.
- `"podman"`: mount `/run/podman/podman.sock:/var/run/docker.sock:ro`
  instead; do not set `oci-containers.backend` (podman.nix already claims it
  unconditionally when Podman is enabled).
- Two assertions per module, mirroring dockhand.nix exactly:
  1. `backend == "podman"` requires `vexos.server.podman.enable`.
  2. `backend == "docker"` (default) conflicts with
     `vexos.server.podman.enable = true` on the same host (Podman force-off
     of `virtualisation.docker.enable` plus its unconditional
     `oci-containers.backend` claim would break the Docker socket mount).

Arcane's read-only vs. read-write socket mount: Portainer already mounts
`:ro`; Arcane currently mounts read-write (no `:ro` suffix) — preserve each
module's existing read/write mode for the Docker path, and use `:ro` for the
Podman path in both (matching Dockhand's `:ro` convention for the Podman
compat socket, since Podman's compat socket is host-wide and shared).

## Implementation Steps

### 1. `modules/server/portainer.nix`
- Add `backend` option (as above).
- Replace unconditional `virtualisation.docker.enable` /
  `oci-containers.backend` lines with `cfg.backend`-conditional versions.
- Replace hardcoded socket mount with `cfg.backend`-conditional value.
- Add the two assertions.
- Update top-of-file comment to describe both modes (currently says
  "Requires Docker to be enabled").

### 2. `modules/server/arcane.nix`
- Same four changes as portainer.nix, applied to `vexos.server.arcane.*`.
- Update top-of-file comment (currently: "Docker container management UI
  (OCI container, Docker backend)").

### 3. `justfile` — Portainer text updates (already wired in, just needs
   wording updated to reflect the new option instead of a hard Docker
   requirement)
- Line 1455: `portainer) ... "(requires docker)"` → drop the hardcoded
  requirement text (backend is now configurable) or make it neutral.
- Line 1573: `portainer) UNITS="docker-portainer";` → `UNITS="docker-portainer
  podman-portainer"`, matching the Dockhand precedent (justfile:1530) of
  listing both possible unit names since `just info`/`just status` has no
  Nix-evaluation context to know which backend is configured.
- Line 2341-2346 (`just enable portainer` info block): reword "Requires:
  Docker to be enabled" line to mention the configurable backend, mirroring
  the Dockhand block (justfile:1974-1979).
- `template/server-services.nix:148`: reword the inline comment
  "(requires docker)" similarly.

### 4. `justfile` — Arcane wiring (new)
- `_server_service_names` (justfile:1133): insert `arcane` alphabetically
  (after `adguard`, before `arr`).
- `_svc` list (justfile:1291-1301, "Infrastructure" header): insert
  `_svc arcane "Web UI for managing Docker/Podman containers"` alphabetically
  before `_svc attic` (matches wording style used for dockhand/portainer).
- `just info` status-line case (justfile ~1391, alphabetical-ish placement
  near `attic`): add
  `arcane) printf "  %-18s  Web UI  http://<server-ip>:3552   (Docker/Podman container manager)\n" "$1" ;;`
- `just status` UNITS case (justfile ~1519, near `attic`): add
  `arcane) UNITS="docker-arcane podman-arcane"; URLS="http://localhost:3552" ;;`
- `_check` list (justfile:1638, "Infrastructure" header): add
  `_check arcane` alongside the other infra checks.
- `just enable` info block (justfile, alongside `attic`'s block — actual
  position wherever the case statement for `attic` lives, insert nearby):
  add an `arcane)` block mirroring `arcane.nix`'s existing top-of-file
  comment (mentions `appUrl` and `environmentFile` requirements, backend
  option, and the encryption-key/JWT-secret setup steps), consistent in
  format with the `dockhand)`/`portainer)` blocks.

### 5. `template/server-services.nix`
- Already has commented-out `vexos.server.arcane.*` lines (lines 44-46) —
  leave as-is; no changes needed beyond the portainer comment reword in step 3.

## Dependencies

None. No new flake inputs, no new packages. Context7 not required (no
external library/API involved — pure Nix option additions plus justfile
shell-script text/logic, identical in kind to the already-implemented
Dockhand change).

## Configuration Changes

New options: `vexos.server.portainer.backend` and
`vexos.server.arcane.backend` (both default `"docker"` — no behavior change
for any existing host that has these enabled, since Docker was already the
only supported/default path for both).

## Risks and Mitigations

- **Risk:** Same silent-breakage risk as Dockhand if `backend = "docker"`
  (default) coexists with `vexos.server.podman.enable = true`.
  **Mitigation:** Same defense-in-depth assertion added to both modules.
- **Risk:** Arcane's `just enable` info block references `appUrl` and
  `environmentFile` prerequisites that must still be set correctly — adding
  justfile wiring must not omit or misstate those requirements.
  **Mitigation:** Mirror the exact requirement text already present in
  `arcane.nix`'s module comments and the commented-out template block in
  `template/server-services.nix:44-46`.
- **Risk:** `just status`/`just info` for Arcane and Portainer will report
  "unit not found" for whichever backend isn't active — cosmetic only, not
  a functional issue, and already the accepted behavior for Dockhand
  post-change.
  **Mitigation:** None needed; consistent with existing precedent.
