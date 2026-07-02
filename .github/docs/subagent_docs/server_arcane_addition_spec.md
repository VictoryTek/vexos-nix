# Arcane server service — Spec

## Current State Analysis

- `modules/server/` follows Option B (universal base + role additions); each optional
  service is a self-contained file exposing `vexos.server.<service>.enable` plus any
  service-specific options, imported unconditionally by `modules/server/default.nix`
  and gated at runtime via `lib.mkIf cfg.enable`.
- `vaultwarden.nix` and `headscale.nix` were requested but **already exist**, are
  already imported in `modules/server/default.nix`, and are already documented/toggled
  in `template/server-services.nix`. No changes needed for those two.
- The closest prior art for a new Docker management UI is `modules/server/portainer.nix`
  (plain `virtualisation.oci-containers` container on the Docker backend, named volume
  for state, firewall port opened unconditionally) and `modules/server/dockhand.nix`
  (Podman-backed variant with a host data directory and an assertion on a prerequisite
  runtime).
- Arcane is a Docker-only management UI (per user request: "the docker management app"),
  so the Portainer pattern (Docker backend via `virtualisation.oci-containers`) is the
  correct fit, not the Podman/Dockhand pattern.

## Problem Definition

Add a new optional server service, Arcane, following the existing module pattern, wired
into the umbrella import list and the host-facing template file — matching how every
other optional service in this repo is exposed.

## Research (Context7 — `/getarcaneapp/arcane`, cross-checked with getarcane.app docs)

- Official image: `ghcr.io/getarcaneapp/manager:latest`
- Default port: `3552` (HTTP, also serves the API + WebSocket for live updates)
- Required env vars:
  - `APP_URL` — public URL Arcane is served at (used for links/redirects)
  - `ENCRYPTION_KEY` — 32-byte key (hex/base64/raw), used to encrypt stored secrets
  - `JWT_SECRET` — 32-byte secret, used to sign auth JWTs
  - Both secrets should be generated with `openssl rand -hex 32` and must be supplied
    out-of-band, not hardcoded in the Nix store (matches this repo's existing pattern
    for `vaultwarden.nix`/`vexboard.nix`, which use a `secretFile`/`environmentFile`
    loaded via systemd `EnvironmentFile`, never inlined as plaintext Nix strings).
- Recommended env vars: `PUID` / `PGID` (default `65532`) for file ownership inside the
  data volume.
- Required volumes:
  - `/var/run/docker.sock:/var/run/docker.sock` — grants Arcane control of the host's
    Docker daemon (this is the entire point of the app; equivalent to Portainer's mount)
  - a persistent data volume mounted at `/app/data` (SQLite DB + project/compose state)
- Arcane's docker-compose reference also mentions optional `/builds` and `/backups`
  mounts for its build/backup features — out of scope for a minimal server-role add;
  omitted, matching this repo's "minimum code that solves the problem" principle.

## Proposed Solution / Architecture

New file: `modules/server/arcane.nix` (Option B addition file, one service per file,
no `lib.mkIf` role-gating inside — same pattern as every existing `modules/server/*.nix`).

```
options.vexos.server.arcane = {
  enable          = lib.mkEnableOption "Arcane Docker management UI";
  port            = lib.mkOption { type = port; default = 3552; };
  appUrl          = lib.mkOption { type = str; default = "http://arcane.example.com";
                                    # placeholder, asserted non-default like vaultwarden.domain };
  environmentFile = lib.mkOption { type = nullOr path; default = null;
                                    # must contain ENCRYPTION_KEY=... and JWT_SECRET=... };
};

config = lib.mkIf cfg.enable {
  assertions = [
    { appUrl != default placeholder }
    { environmentFile != null }
  ];
  virtualisation.docker.enable = lib.mkDefault true;
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.arcane = {
    image = "ghcr.io/getarcaneapp/manager:latest";
    ports = [ "${toString cfg.port}:3552" ];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
      "arcane-data:/app/data"
    ];
    environment = {
      APP_URL = cfg.appUrl;
      PUID = "65532";
      PGID = "65532";
    };
    environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
  };
  networking.firewall.allowedTCPPorts = [ cfg.port ];
};
```

## Implementation Steps

1. Create `modules/server/arcane.nix` per the design above, with a header comment
   documenting the image, port, and the two required secrets (mirrors the header style
   of `vaultwarden.nix`/`dockhand.nix`).
2. Add `./arcane.nix` to `modules/server/default.nix` under the
   `── Container Runtime ──` section, next to `./dockhand.nix` (both are Docker/Podman
   management UIs).
3. Add Arcane to `template/server-services.nix`:
   - append `arcane` to the "Available services" comment list at the top
   - add a commented toggle block under `── Container Runtime ──` documenting the port
     and the required `environmentFile` secret, matching the style used for
     `vaultwarden`/`vexboard`.
4. No flake input changes — no new flake-level dependency, this is a plain OCI container
   pulled at deploy time (same as Portainer/Dockhand), so no `follows` declarations apply.

## Dependencies

- No new Nix flake inputs.
- External OCI image `ghcr.io/getarcaneapp/manager:latest`, verified via Context7
  (`/getarcaneapp/arcane`) and getarcane.app official install docs (2026-07-01).

## Configuration Changes

- `modules/server/default.nix` — add one import line.
- `template/server-services.nix` — add one list entry + one commented toggle block.

## Risks and Mitigations

- **Docker socket mount = root-equivalent host access.** Same risk profile as Portainer,
  which this repo already ships; no new precedent set. Documented in the module header.
- **Secrets in Nix store.** Mitigated by requiring `environmentFile` (systemd
  EnvironmentFile, generated out-of-band with `openssl rand -hex 32`), never inlining
  `ENCRYPTION_KEY`/`JWT_SECRET` as plaintext option defaults — assertion enforces this
  is set before the service activates.
- **Placeholder `APP_URL` shipped by mistake.** Mitigated with an assertion identical to
  `vaultwarden.nix`'s `domain` check.
