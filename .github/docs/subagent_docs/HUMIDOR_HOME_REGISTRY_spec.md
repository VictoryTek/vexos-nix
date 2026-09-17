# humidor + home-registry server modules — Spec

## Current state analysis

- `modules/server/joplin.nix` is the established pattern for a two-container
  OCI stack (app + dedicated `postgres`) with no nixpkgs package: dedicated
  Docker network, auto-generated Postgres password via a `<name>-secrets-init`
  oneshot, `systemd.tmpfiles.rules` for `dataDir` and `dataDir/dump` only
  (never `dataDir/postgres`, which the postgres image's entrypoint chowns
  itself), a nightly `pg_dump` via `modules/lib/dump-timer.nix`, and
  `vexos.server.backup.servicePaths.<name> = [ "${cfg.dataDir}/dump" ]`.
- `modules/server/default.nix` is a flat import list, alphabetized within
  category comment blocks.
- `justfile` drives all service lifecycle UX generically off two data
  tables (`_server_service_names`, `_service_catalog`) plus four per-service
  `case` blocks (info-line printer ~L2180, systemd-unit lookup ~L2300,
  quick-open URL lookup ~L2390, detailed `info` block ~L3124). Adding a
  service only requires adding entries to these six locations — no new
  recipes are needed since `just enable <service>` is already generic.
- `template/server-services.nix` documents every toggle with commented-out
  defaults; it's what `just enable` scaffolds `/etc/nixos/server-services.nix`
  from on first use.
- Neither humidor nor home-registry has a nixpkgs package; both are
  personal apps distributed as `ghcr.io/victorytek/<name>` images.

### Upstream compose files (from github.com/VictoryTek/humidor and
### github.com/VictoryTek/home-registry, confirmed by user to match the
### live Dockge deployment)

**humidor** (`docker-compose.yml`, Rust app, no separate prod compose —
default branch image tag is `latest` per `deploy.yml`'s metadata-action):
```yaml
humidor:
  environment:
    DATABASE_URL: postgresql://${POSTGRES_USER:-humidor_user}:${POSTGRES_PASSWORD}@humidor_db:5432/${POSTGRES_DB:-humidor_db}
    RUST_LOG: ${RUST_LOG:-info}
    PORT: ${PORT:-9898}
  ports: ["9898:9898"]
humidor_db:
  image: postgres:17
  environment:
    POSTGRES_DB: ${POSTGRES_DB:-humidor_db}
    POSTGRES_USER: ${POSTGRES_USER:-humidor_user}
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

**home-registry** (`docker-compose.prod.yml`, Rust app, GHCR image tag
defaults to `beta`):
```yaml
db:
  image: postgres:17
  environment:
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    POSTGRES_DB: home_inventory
app:
  image: ghcr.io/${GITHUB_REPOSITORY_OWNER:-victorytek}/home-registry:${VERSION:-beta}
  environment:
    DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@db:5432/home_inventory
    PORT: 8210
    RUST_LOG: ${RUST_LOG:-info}
```

## Problem definition

Both apps need to move from ad-hoc Dockge stacks into declarative
`vexos.server.<name>` NixOS modules, following the same conventions as
`joplin.nix`, and be reachable through the generic `just enable <service>`
UX.

**Key divergence from joplin (flagged to user, resolved):** neither app
reads discrete `POSTGRES_HOST`/`POSTGRES_USER`/`POSTGRES_PORT` env vars —
both expect a single composed `DATABASE_URL`. Resolved: the
`<name>-secrets-init` oneshot writes both `POSTGRES_PASSWORD=...` and a
fully-assembled `DATABASE_URL=postgresql://<user>:<password>@<name>-db:5432/<db>`
into the generated secrets file; the app container's only DB-related
config is `environmentFiles = [ effectiveEnvFile ]` (no separate
`POSTGRES_HOST`/`POSTGRES_USER`/`POSTGRES_PORT` entries in its
`environment{}`, since the app doesn't read them).

**home-registry's DB user/name are hardcoded upstream** (`postgres` /
`home_inventory`, not overridable without upstream code changes) —
resolved: module hardcodes them to match, no `dbUser`/`dbName` options
added. Upstream improvement notes captured separately (see
`HUMIDOR_HOME_REGISTRY_upstream_notes.md`) per user's request, since these
are the user's own apps.

## Proposed solution architecture

Two new modules, each following `joplin.nix` line-for-line in structure:

### `modules/server/humidor.nix`

```
options.vexos.server.humidor = {
  enable          = mkEnableOption "Humidor cigar/humidor tracker";
  port            = mkOption { type = port; default = 9898; };
  dataDir         = mkOption { type = str; default = "/var/lib/humidor"; };
  environmentFile = mkOption { type = nullOr path; default = null; };
  openFirewall    = mkOption { type = bool; default = true; };
};
```
- `effectiveEnvFile` = `cfg.environmentFile` or `${cfg.dataDir}/secrets/humidor-env`.
- `humidor-secrets-init` (only when `environmentFile == null`) writes:
  ```
  POSTGRES_PASSWORD=<openssl rand -hex 24>
  DATABASE_URL=postgresql://humidor_user:<same password>@humidor-db:5432/humidor_db
  ```
- `humidor-network` oneshot: `docker network inspect humidor-net || docker network create humidor-net`.
- `systemd.tmpfiles.rules`: `dataDir` and `dataDir/dump` only (0700 root root), same
  comment as joplin explaining why `dataDir/postgres` is excluded.
- `virtualisation.oci-containers.containers.humidor-db`:
  - `image = "postgres:17"`
  - `environment = { POSTGRES_USER = "humidor_user"; POSTGRES_DB = "humidor_db"; }`
  - `environmentFiles = [ effectiveEnvFile ]`
  - `volumes = [ "${cfg.dataDir}/postgres:/var/lib/postgresql/data" ]`
  - `extraOptions = [ "--network=humidor-net" ]`
- `virtualisation.oci-containers.containers.humidor`:
  - `image = "ghcr.io/victorytek/humidor:latest"`
  - `ports = [ "${toString cfg.port}:9898" ]`
  - `environment = { PORT = "9898"; RUST_LOG = "info"; }`
  - `environmentFiles = [ effectiveEnvFile ]` (supplies `DATABASE_URL`)
  - `extraOptions = [ "--network=humidor-net" ]`
  - `dependsOn = [ "humidor-db" ]`
- `docker-humidor-db`/`docker-humidor` `.after`/`.requires` →
  `humidor-network.service` + (conditionally) `humidor-secrets-init.service`.
- `vexos.server.backup.servicePaths.humidor = [ "${cfg.dataDir}/dump" ];`
- `dumpTimer.mkDumpTimer { name = "humidor"; container = "humidor-db"; command = "pg_dump -U humidor_user humidor_db"; outputPath = "${cfg.dataDir}/dump/humidor.sql"; }`
  (no `offsetMinute`/`unitName` — hash-derived, per instructions).
- `networking.firewall.interfaces.tailscale0`... — **not applicable**:
  joplin scopes to `tailscale0` because it documents itself as
  Tailscale-only by design. humidor/home-registry have no such stated
  constraint, so `openFirewall` opens `cfg.port` on the standard
  `networking.firewall.allowedTCPPorts` (global list), matching the
  simpler pattern used by non-Tailscale-scoped modules (e.g.
  `grimmory.nix`'s firewall handling). *(Implementation should verify
  grimmory.nix's exact firewall line before writing this.)*

### `modules/server/home-registry.nix`

Same shape, with these substitutions:
- `options.vexos.server.home-registry` — nix attribute names with `-` need
  quoting (`"home-registry"`) consistent with how `nginx-proxy-manager` /
  `kiji-proxy` etc. are already declared elsewhere in this repo; check
  existing hyphenated-name module for the exact quoting convention before
  writing.
- `port` default `8210`.
- `dataDir` default `/var/lib/home-registry`.
- Docker network: `home-registry-net`.
- Secrets-init writes:
  ```
  POSTGRES_PASSWORD=<openssl rand -hex 24>
  DATABASE_URL=postgres://postgres:<same password>@home-registry-db:5432/home_inventory
  ```
- `home-registry-db` container: `POSTGRES_USER = "postgres"; POSTGRES_DB = "home_inventory";` (hardcoded, matches upstream).
- `home-registry` app container: `image = "ghcr.io/victorytek/home-registry:beta"`, `PORT = "8210"`, `RUST_LOG = "info"`.
- Dump: `container = "home-registry-db"; command = "pg_dump -U postgres home_inventory";`
  `outputPath = "${cfg.dataDir}/dump/home-registry.sql"`.
- Same firewall approach as humidor (global allowedTCPPorts, not
  tailscale0-scoped).

### `modules/server/default.nix`

Add both under a new or existing category comment block — likely
`── Food & Home ──` (home-registry: home inventory) sits oddly next to
`mealie.nix`/`wishlist.nix`/`listmonk.nix`; humidor (cigar tracking) has
no obvious existing category. Proposal: add a new
`── Personal Trackers ──` block for both, placed after `── Food & Home ──`.
Implementation should use judgment / ask if a better fit exists once the
actual app purpose is confirmed (humidor = cigar collection tracker,
home-registry = home inventory tracker, per repo descriptions).

### justfile wiring (six locations, mirroring joplin's entries exactly)

1. `_server_service_names` (~L1619): insert `home-registry` and `humidor`
   alphabetically into the space-separated list.
2. `_service_catalog` (~L1627): add two `Group|name|description` lines in
   the same new/existing category chosen above.
3. Info-line `case` block (~L2180-2220): one line per service, e.g.
   `humidor)  printf "  %-18s  Web UI  http://<server-ip>:9898\n" "$1" ;;`
4. systemd-unit lookup `case` block (~L2300-2340): e.g.
   `humidor)  echo "docker-humidor docker-humidor-db" ;;`
5. Quick-open URL `case` block (~L2390-2420): e.g.
   `humidor)  URLS="http://localhost:9898" ;;`
6. Detailed `info` block (~L3121-3130 region, per-service multi-line
   `echo` block): short description, service units, web UI URL, any
   first-run notes (e.g. no default admin credentials documented upstream
   for either app — implementation should check each app's README for a
   first-login note to mirror joplin's "Login:" line, or omit if none
   exists).

### `template/server-services.nix`

Add commented-out toggle lines for both, in the matching category block,
following the exact comment style of the `joplin` entry (port note, "no
further config needed" note since secrets auto-generate).

## Dependencies

No new flake inputs. No nixpkgs packages. Both images pulled at runtime
from `ghcr.io/victorytek/<name>` via `virtualisation.oci-containers`
(already how joplin/grimmory/etc. work) — no Context7 lookup needed (no
new library/framework integration, per Dependency Policy's exclusions:
"Internal code changes with no new dependencies").

## Configuration changes

- Two new files: `modules/server/humidor.nix`, `modules/server/home-registry.nix`.
- `modules/server/default.nix`: two new imports.
- `justfile`: six edits (see above).
- `template/server-services.nix`: two new commented toggle blocks.
- New file: `.github/docs/subagent_docs/HUMIDOR_HOME_REGISTRY_upstream_notes.md`
  — improvement notes on humidor/home-registry's own env-var handling
  (DATABASE_URL-only, home-registry's non-configurable DB user/name),
  since the user owns both apps and asked these be written down rather
  than silently worked around.

## Risks and mitigations

- **Port collision**: 9898 and 8210 don't collide with any existing
  module's default port in this repo (not verified exhaustively —
  implementation should grep existing `default = <port>;` values before
  finalizing).
- **Image tag drift**: `latest` (humidor) and `beta` (home-registry) are
  moving tags, matching upstream's own default deploy behavior — not
  pinned, consistent with these being the user's own actively-developed
  apps rather than third-party stable releases.
- **Firewall scoping assumption**: joplin's tailscale0-only scoping is
  explicitly because that module documents itself as Tailscale-only by
  design. Nothing in the user's request states the same constraint for
  humidor/home-registry, so this spec defaults to the standard global
  `allowedTCPPorts` pattern — implementation should confirm this
  assumption is correct (or flag back) rather than silently copying
  joplin's tailscale-only scoping, since that's a meaningfully different
  exposure decision.
- **`home-registry` attribute quoting**: Nix requires `"home-registry"`
  wherever the hyphenated name is used as an attribute key (`config.vexos.server."home-registry"`,
  `systemd.services."docker-home-registry"`, etc.) — implementation must
  audit every reference for correct quoting; a missed one is a silent
  eval-time attribute-path bug, not a syntax error.
