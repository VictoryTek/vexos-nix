# Dockhand Dual-Backend Support — Spec

## Current State Analysis

`modules/server/dockhand.nix` deploys Dockhand as a single hardcoded
Podman-backed OCI container:

- Asserts `vexos.server.podman.enable == true` (fails hard otherwise).
- Mounts `/run/podman/podman.sock:/var/run/docker.sock:ro` — the Podman
  Docker-compat socket, not a real Docker socket.
- No option to choose Docker as the runtime, even though the user may have
  `vexos.server.docker.enable = true` instead.

This is inconsistent with every other container-management-UI module in the
repo. `modules/server/arcane.nix`, `portainer.nix`, `homepage.nix`,
`uptime-kuma.nix`, `nginx-proxy-manager.nix`, `stirling-pdf.nix`, `dozzle.nix`,
`authelia.nix`, `arr.nix`, and `joplin.nix` all set:

```nix
virtualisation.docker.enable = lib.mkDefault true;
virtualisation.oci-containers.backend = lib.mkDefault "docker";
```

and mount `/var/run/docker.sock` directly — no Podman dependency.

`modules/server/podman.nix` sets `virtualisation.oci-containers.backend =
"podman"` (not `mkDefault`, so it wins over any `mkDefault "docker"` set by
other modules) and force-disables `virtualisation.docker.enable` via
`lib.mkForce false`, with an explicit assertion that Podman and Docker must
not both be enabled on the same host
(`vexos.server.podman` / `vexos.server.docker` mutual-exclusion assertion).

`justfile` has three places with Dockhand-specific, Podman-only text:
- Line 1296: `_svc dockhand "Web UI for managing Podman containers"`
- Line 1397: status-check port line, `"(Podman container manager)"`
- Line 1530: `dockhand) UNITS="podman-dockhand"; ...` — systemd unit name is
  backend-prefixed (`virtualisation.oci-containers` names the unit
  `<backend>-<container-name>`, so a Docker-backed instance is
  `docker-dockhand`, matching the existing `docker-homepage` /
  `docker-joplin-server` pattern used by other services in this same file).
- Lines 1974-1979: `just enable dockhand` descriptive block — "NixOS OCI
  container via Podman", "Requires: Podman must be enabled first".

## Problem Definition

The user enabled `vexos.server.docker` (not Podman) and expects to enable
Dockhand on top of it. The current module rejects this with a hard
assertion failure, forcing an all-or-nothing choice the user does not want
(they explicitly do not want Podman on this host).

## Proposed Solution

Add a `vexos.server.dockhand.backend` option, `lib.types.enum [ "docker"
"podman" ]`, default `"docker"` (matches the rest of the repo's default
container runtime choice and requires no change for users of other
Docker-backed services). Based on the selected backend:

- `"docker"`: `virtualisation.docker.enable = lib.mkDefault true;`
  `virtualisation.oci-containers.backend = lib.mkDefault "docker";` and mount
  `/var/run/docker.sock:/var/run/docker.sock` (matches `arcane.nix` exactly).
- `"podman"`: keep existing behavior — assert `vexos.server.podman.enable`,
  mount `/run/podman/podman.sock:/var/run/docker.sock:ro`. Do NOT set
  `oci-containers.backend` here explicitly since `podman.nix` already sets it
  unconditionally (non-`mkDefault`) when Podman is enabled; setting it again
  in dockhand.nix would be redundant but harmless — omit to avoid duplicate
  precedence-setting logic across modules.

Assertion changes:
- Only assert the Podman requirement when `cfg.backend == "podman"`.
- No assertion needed for the Docker path — `virtualisation.docker.enable =
  lib.mkDefault true` self-satisfies, consistent with how `arcane.nix` /
  `portainer.nix` behave (they don't assert Docker is enabled; they default
  it on).

This follows the Module Architecture Pattern's carve-out: `lib.mkIf`/branching
on `cfg.backend` is gating a config block by an option the *same module*
declares (`vexos.server.dockhand.backend`), which is the explicitly-permitted
toggleable-subsystem pattern, not role-smuggling.

## Implementation Steps

1. **`modules/server/dockhand.nix`**
   - Add `backend` option: `lib.types.enum [ "docker" "podman" ]`, default
     `"docker"`, description explaining the two modes.
   - Replace the single unconditional assertion with a conditional one that
     only fires when `cfg.backend == "podman"`.
   - Replace the single hardcoded `volumes` socket mount with a
     `cfg.backend`-conditional value (docker socket vs. podman compat
     socket).
   - Wrap the `virtualisation.docker.enable` / `oci-containers.backend`
     lines in `lib.mkIf (cfg.backend == "docker")`.
   - Update the file's top-of-file comment block to describe both modes.

2. **`justfile`**
   - Line 1296: reword `_svc dockhand` description to be backend-neutral
     (e.g. "Web UI for managing Docker/Podman containers").
   - Line 1397: reword the inline status annotation to be backend-neutral
     (e.g. drop the parenthetical or make it "(Docker/Podman container
     manager)").
   - Line 1530: `UNITS` must reflect the configured backend. Since `just
     status` shells out without Nix evaluation context, mirror the existing
     approach used elsewhere in this file for backend-dependent unit names:
     check both `docker-dockhand` and `podman-dockhand` (whichever unit
     exists at runtime), OR read `vexos.server.dockhand.backend` similarly to
     how other conditional checks in this file are done. Simplest: try
     `docker-dockhand` first, fall back to `podman-dockhand` if the former is
     inactive/not found — avoids needing to evaluate Nix config from the
     justfile.
   - Lines 1974-1979 (`just enable dockhand` info block): make Podman
     requirement conditional/informational rather than a blanket
     "Requires: Podman must be enabled first" — mention both options.

## Dependencies

None — no new flake inputs, no new packages. Pure Nix module option addition
plus shell-script text/logic updates in `justfile`. Context7 not required
(no external library/API involved).

## Configuration Changes

New option: `vexos.server.dockhand.backend` (default `"docker"`).
Existing hosts with `vexos.server.dockhand.enable = true` and
`vexos.server.podman.enable = true` currently rely on implicit Podman
behavior — after this change they must also set
`vexos.server.dockhand.backend = "podman"` to keep working, since the new
default is `"docker"`. No such host exists yet in this repo (dockhand was
just enabled for the first time in this session and failed before reaching a
working state), so this is not a breaking change for any committed
configuration.

## Risks and Mitigations

- **Risk:** Changing the default backend to `"docker"` could silently break
  a host that has both Podman and Dockhand enabled without an explicit
  backend value.
  **Mitigation:** No committed host config currently enables Dockhand (only
  toggled locally this session, not yet built successfully), so there is no
  existing default-behavior contract to break. Documented in the module
  comment regardless, for future hosts.
- **Risk:** `justfile`'s `just status` unit-check logic for dockhand doesn't
  have access to Nix config, only to the running system — must not
  hardcode a single unit name.
  **Mitigation:** Check for either unit name at runtime (try
  `docker-dockhand`, fall back to `podman-dockhand`), matching the
  shell-only nature of the rest of `just status`.
- **Risk:** Docker + Podman mutual-exclusion assertion in `podman.nix`
  already prevents both runtimes being enabled system-wide — Dockhand's
  Docker path must not conflict with a host that has Podman enabled for
  other services while Dockhand explicitly wants `backend = "podman"`.
  **Mitigation:** When `cfg.backend == "podman"`, dockhand.nix sets no
  Docker options at all (identical to current behavior), so no conflict is
  introduced beyond what already exists today.
