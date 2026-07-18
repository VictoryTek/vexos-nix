# Grimmory Server — Implementation Spec

## Current State Analysis

- `modules/server/` follows a consistent per-service module pattern: `options.vexos.server.<svc>`,
  `config = lib.mkIf cfg.enable { ... }`, `networking.firewall.allowedTCPPorts = lib.optional
  cfg.openFirewall cfg.port;`. Services with no native NixOS module are deployed via
  `virtualisation.oci-containers.containers.<name>`.
- **No nixpkgs package or NixOS module exists for Grimmory** (confirmed via live `search.nixos.org`
  query against the `unstable` channel — no packages, no options match `grimmory`). It must be
  deployed as an OCI container.
- `modules/server/joplin.nix` is the closest and only precedent in this repo for a **two-container
  stack** (app + dedicated database, not the host's native DB service): dedicated Docker network
  created by an idempotent oneshot systemd unit, `dependsOn` for container start ordering, a
  `*-secrets-init` oneshot unit that auto-generates a random password into
  `${dataDir}/secrets/<svc>-env` on first activation when `environmentFile` is left `null` (so
  `enable = true;` alone is sufficient — no mandatory manual secret step), and a nightly dump timer
  (`pg_dump` there) instead of raw file-backup of the live database directory, matched by a
  `backup.nix` `servicePaths` entry pointing only at the dump path.
- `modules/server/komga.nix` / `modules/server/kavita.nix` are the "Books & Comics" section in
  `modules/server/default.nix` — Grimmory (ebook/comic/audiobook library) belongs in this same
  section. Unlike Komga/Kavita (native NixOS modules, no container), Grimmory has no native module,
  so it follows Joplin's OCI two-container pattern instead — closer in shape to Joplin than to its
  section-mates.
- Komga/Kavita both default `openFirewall = true` on the **global** `networking.firewall.allowedTCPPorts`
  list (LAN-reachable by design, unlike Joplin which was deliberately scoped to `tailscale0` only per
  an explicit user decision specific to that service). Grimmory is a LAN media-library reader like
  Komga/Kavita, not a notes-sync backend, so it follows their global-firewall default rather than
  Joplin's Tailscale-only scoping.
- `modules/server/backup.nix` maintains a `servicePaths` map keyed by service name; header comment
  invites new modules to add an entry so restic picks them up automatically.
- `template/server-services.nix` documents every toggle with a commented example line;
  `justfile`'s `_server_service_names` variable is the authoritative space-separated list consumed
  by `just enable/disable <service>`; `justfile` also has a `_svc` description line, a
  `service-info` printf block, a `service status` UNITS/URLS case, and a longer per-service
  `echo` info block (~line 2190, see the `joplin)` case) that all need a matching entry for
  every service.

## Problem Definition

Add Grimmory (self-hosted digital library for ebooks/comics/audiobooks —
https://github.com/grimmory-tools/grimmory) as a new optional server service
(`vexos.server.grimmory.enable`), following the Module Architecture Pattern (Option B) and the
existing OCI two-container precedent (`joplin.nix`).

## Proposed Solution Architecture

New file: `modules/server/grimmory.nix` (role-agnostic addition file — no `lib.mkIf` role/display/
gaming guards involved, matching how `vaultwarden.nix`/`joplin.nix` are structured).

### Upstream deployment reference (source of truth)

Fetched directly from `grimmory-tools/grimmory`'s `develop` branch,
`deploy/compose/docker-compose.yml` (the project's own maintained Docker Compose reference,
not a third-party tutorial):

```yaml
grimmory:
  image: grimmory/grimmory:v0.38.2
  environment:
    - USER_ID=1000
    - GROUP_ID=1000
    - TZ=Etc/UTC
    - DATABASE_URL=jdbc:mariadb://mariadb:3306/grimmory
    - DATABASE_USERNAME=grimmory
    - DATABASE_PASSWORD=your_secure_password
    - SWAGGER_ENABLED=false
    - FORCE_DISABLE_OIDC=false
  depends_on:
    mariadb: { condition: service_healthy }
  ports: [ "6060:6060" ]
  volumes:
    - ./data:/app/data
    - ./books:/books
    - ./bookdrop:/bookdrop

mariadb:
  image: lscr.io/linuxserver/mariadb:11.4.8
  environment:
    - PUID=1000
    - PGID=1000
    - TZ=Etc/UTC
    - MYSQL_ROOT_PASSWORD=super_secure_password
    - MYSQL_DATABASE=grimmory
    - MYSQL_USER=grimmory
    - MYSQL_PASSWORD=your_secure_password
  volumes:
    - ./config:/config
  healthcheck:
    test: [ "CMD", "mariadb-admin", "ping", "-h", "localhost" ]
```

Key facts confirmed from the app's own README: `/books` is the library's permanent storage;
`/bookdrop` is a watched auto-import staging folder (files are enriched with metadata and queued
for review, then moved into the library); admin account is created on first visit to the web UI
(no published default credentials, unlike Joplin/Vaultwarden); auth supports local accounts or
OIDC (`FORCE_DISABLE_OIDC=false` is the upstream default — leaves OIDC available but not forced).

### Containers (Docker backend, via `virtualisation.oci-containers`)

Two containers on a dedicated user-defined Docker network `grimmory-net` (mirrors
`joplin-network`/`joplin-net`):

- `grimmory-db` — `lscr.io/linuxserver/mariadb:11.4.8`, no published ports, config/data at
  `${cfg.dataDir}/mariadb-config:/config`. No tmpfiles rule needed for this subdirectory — like
  Joplin's Postgres precedent, the LinuxServer.io base image's `s6-init` entrypoint chowns
  `/config` to its own managed UID/GID (derived from `PUID`/`PGID`) on first run; a tmpfiles rule
  here would re-assert root ownership on every `nixos-rebuild switch` (tmpfiles runs every
  activation) and strip the already-running container's access without restarting it.
- `grimmory` (app) — `grimmory/grimmory:v0.38.2` (pinned stable tag, not `:latest`, matching the
  upstream compose file's own recommendation), publishes `${cfg.port}:6060`, connects to
  `grimmory-db` by container name over `grimmory-net`.

```nix
systemd.services."grimmory-network" = {
  description   = "Create dedicated Docker network for the Grimmory stack";
  wantedBy      = [ "multi-user.target" ];
  after         = [ "docker.service" ];
  requires      = [ "docker.service" ];
  serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  script = ''
    ${pkgs.docker}/bin/docker network inspect grimmory-net >/dev/null 2>&1 || \
      ${pkgs.docker}/bin/docker network create grimmory-net
  '';
};
```

Both containers get `extraOptions = [ "--network=grimmory-net" ];`; `docker-grimmory.service`
additionally has `dependsOn = [ "grimmory-db" ];`. No explicit "wait for healthy" logic is
implemented (Docker Compose's `condition: service_healthy` has no equivalent in
`virtualisation.oci-containers`) — matching Joplin's precedent, the generated `docker-grimmory
.service` unit's default `Restart=on-failure` recovers automatically if the app's first DB
connection attempt races MariaDB's startup.

### Options (`options.vexos.server.grimmory`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | bool | false | `mkEnableOption` |
| `port` | port | 6060 | Host port for the app container (upstream default) |
| `dataDir` | str | `/var/lib/grimmory` | Host dir for app data (`app-data/`), MariaDB config (`mariadb-config/`), the nightly dump (`dump/`), and the auto-generated secrets file (`secrets/`) |
| `libraryDir` | str | `${cfg.dataDir}/books` | Host path bind-mounted to `/books` — the permanent ebook/comic/audiobook library. Overridable to point at existing storage (e.g. a `mergerfs`/`storage-remote` pool already used by this repo's storage-tier modules) |
| `bookdropDir` | str | `${cfg.dataDir}/bookdrop` | Host path bind-mounted to `/bookdrop` — the watched auto-import staging folder |
| `userId` / `groupId` | int | 1000 / 1000 | Passed as `USER_ID`/`GROUP_ID` (app) and `PUID`/`PGID` (db) env vars; also used to pre-create `libraryDir`/`bookdropDir`/`app-data` with matching ownership, since (unlike the LinuxServer.io db image) the Grimmory app image does not self-chown its mounts |
| `environmentFile` | nullOr path | null | Optional systemd EnvironmentFile supplying `DATABASE_PASSWORD`, `MYSQL_PASSWORD` (same value, two var names — one per container's expectation), and `MYSQL_ROOT_PASSWORD`. Leave unset (default) for zero-config auto-generation, matching Joplin's "Zero-Config Revision" |
| `openFirewall` | bool | true | Opens `${cfg.port}` on the **global** `networking.firewall.allowedTCPPorts` list (LAN-reachable, matching Komga/Kavita, not Joplin's Tailscale-only scoping) |

### Secrets (zero-config, matching Joplin's revised design)

```nix
systemd.services."grimmory-secrets-init" = lib.mkIf (cfg.environmentFile == null) {
  description   = "Generate Grimmory MariaDB credentials on first activation";
  wantedBy      = [ "multi-user.target" ];
  serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  script = ''
    install -d -m 0700 "${cfg.dataDir}/secrets"
    if [ ! -f "${effectiveEnvFile}" ]; then
      dbPass=$(${pkgs.openssl}/bin/openssl rand -hex 24)
      rootPass=$(${pkgs.openssl}/bin/openssl rand -hex 24)
      {
        echo "DATABASE_PASSWORD=$dbPass"
        echo "MYSQL_PASSWORD=$dbPass"
        echo "MYSQL_ROOT_PASSWORD=$rootPass"
      } > "${effectiveEnvFile}"
      chmod 0600 "${effectiveEnvFile}"
    fi
  '';
};
```

Both containers' generated `docker-<name>.service` units get `after`/`requires` on
`grimmory-network.service` (+ `grimmory-secrets-init.service` when `environmentFile == null`),
same as Joplin.

### Environment variables

App container (`grimmory`):
```
USER_ID          = toString cfg.userId
GROUP_ID         = toString cfg.groupId
TZ               = config.time.timeZone (fallback "Etc/UTC")
DATABASE_URL     = "jdbc:mariadb://grimmory-db:3306/grimmory"
DATABASE_USERNAME = "grimmory"
SWAGGER_ENABLED  = "false"
FORCE_DISABLE_OIDC = "false"
```
(`DATABASE_PASSWORD` comes from `environmentFile`.)

DB container (`grimmory-db`):
```
PUID           = toString cfg.userId
PGID           = toString cfg.groupId
TZ             = config.time.timeZone (fallback "Etc/UTC")
MYSQL_DATABASE = "grimmory"
MYSQL_USER     = "grimmory"
```
(`MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD` come from `environmentFile`.)

### Volumes

```nix
grimmory:
  volumes = [
    "${cfg.dataDir}/app-data:/app/data"
    "${cfg.libraryDir}:/books"
    "${cfg.bookdropDir}:/bookdrop"
  ];
grimmory-db:
  volumes = [ "${cfg.dataDir}/mariadb-config:/config" ];
```

### tmpfiles

```nix
systemd.tmpfiles.rules = [
  "d ${cfg.dataDir} 0755 root root -"
  "d ${cfg.dataDir}/app-data ${cfg.userId} ${cfg.groupId} -" # mode 0755, owner match container's USER_ID/GROUP_ID
  "d ${cfg.libraryDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
  "d ${cfg.bookdropDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
  "d ${cfg.dataDir}/dump 0700 root root -"
];
```
No rule for `mariadb-config` — see the container section above for why.

### Backup integration

Nightly `mariadb-dump` (not a raw file-copy of the live `/config` directory) to
`${cfg.dataDir}/dump/grimmory.sql`, timer at `23:15` (offset 15 min from Joplin's `23:30` purely to
avoid two dump jobs landing on the exact same wall-clock second; both still finish well before
restic's default daily `~00:00` run):

```nix
systemd.services."grimmory-mariadb-dump" = {
  description = "Dump Grimmory MariaDB database for backup";
  after    = [ "docker-grimmory-db.service" ];
  requires = [ "docker-grimmory-db.service" ];
  serviceConfig.Type = "oneshot";
  script = ''
    ${pkgs.docker}/bin/docker exec grimmory-db mariadb-dump -u root -p"$(grep MYSQL_ROOT_PASSWORD ${effectiveEnvFile} | cut -d= -f2)" grimmory > "${cfg.dataDir}/dump/grimmory.sql"
  '';
};
systemd.timers."grimmory-mariadb-dump" = {
  wantedBy = [ "timers.target" ];
  timerConfig = { OnCalendar = "*-*-* 23:15:00"; Persistent = true; };
};
```

One line added to `modules/server/backup.nix`'s `servicePaths` map:
```nix
grimmory = [ "${config.vexos.server.grimmory.dataDir}/dump" "${config.vexos.server.grimmory.libraryDir}" ];
```
Dump for the database (not live `/config`), plus the actual library files (irreplaceable user
media), matching Immich/Photoprism's precedent of backing up the full media tree by default.
`bookdropDir` is deliberately excluded — it's a transient staging area; files land there and are
expected to move into `libraryDir` once processed.

### Firewall

```nix
networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
```

### Other repo touch points (Phase 2 scope)

- `modules/server/default.nix` — add `./grimmory.nix` in the "Books & Comics" section, alongside
  `komga.nix`/`kavita.nix`.
- `modules/server/backup.nix` — add the `grimmory` servicePaths entry above.
- `template/server-services.nix` — add a commented example block (enable flag + note that
  MariaDB credentials auto-generate, matching Joplin's comment style), in the Books & Comics
  section.
- `justfile`:
  - `_server_service_names` — add `grimmory` (alphabetical: between `grafana` and
    `headscale`... actually between `forgejo`/`grafana` and `headscale` — precise slot is
    alphabetically after `grafana`, before `headscale`).
  - `_svc grimmory "Self-hosted ebook/comic/audiobook library"` in the services-listing block.
  - `service-info` printf line: `http://<server-ip>:6060`.
  - `service status` case: `UNITS="docker-grimmory docker-grimmory-db"; URLS="http://localhost:6060"`.
  - Detailed per-service info block (matching the `joplin)` case) noting the two systemd units,
    the web UI URL, first-run admin account creation, and the `libraryDir`/`bookdropDir` mount
    points.

## Dependencies

- `grimmory/grimmory:v0.38.2` (Docker Hub; `ghcr.io/grimmory-tools/grimmory:v0.38.2` also
  available as an alternate registry per upstream's own compose file comments) — no nixpkgs
  equivalent exists (confirmed via live `search.nixos.org` query, see Current State Analysis).
  Context7 has no entry for Grimmory (not a code library/SDK); verified instead via the project's
  own GitHub repository and its maintained `deploy/compose/docker-compose.yml`.
- `lscr.io/linuxserver/mariadb:11.4.8` (LinuxServer.io) — matches the version pinned in Grimmory's
  own official compose reference file exactly.
- No new flake inputs; no changes to `flake.nix`.

## Configuration Changes Required Post-Merge (operator, not Claude)

None required for a working default instance — `vexos.server.grimmory.enable = true;` alone is
sufficient (MariaDB credentials auto-generate on first activation, matching Joplin's zero-config
design). Optional:

1. Set `vexos.server.grimmory.libraryDir` / `bookdropDir` to point at existing storage (e.g. a
   `mergerfs` pool) if not using the default `dataDir`-relative paths.
2. `just enable grimmory` / `just rebuild` (or `sudo nixos-rebuild dry-build` per Phase 3/6 gates —
   actual `switch` is user-initiated only, per FORBIDDEN COMMANDS).
3. Visit `http://<server-ip>:6060`, create the admin account (no published default credentials to
   change, unlike Joplin/Vaultwarden — first visitor sets it up).

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Second two-container OCI stack in this repo (after Joplin) — new surface area for the network/secrets-init pattern | Directly reuses Joplin's already-reviewed pattern (network oneshot, secrets-init oneshot, `dependsOn` ordering); no new mechanism invented |
| No Compose-style "wait for healthy DB" equivalent in `virtualisation.oci-containers` | Same residual risk already accepted for Joplin; `Restart=on-failure` on the generated systemd unit recovers automatically |
| App image doesn't self-chown bind mounts (unlike the LinuxServer.io db image) | `userId`/`groupId` options pre-create `app-data`/`libraryDir`/`bookdropDir` with matching ownership via tmpfiles, so the app's non-root process can write to them from first boot |
| `libraryDir` defaults under `dataDir`, but users likely want their existing book collection elsewhere | Exposed as an overridable option (unlike Joplin, which has no user-media equivalent) so operators can point at a `mergerfs`/`storage-remote` pool without editing the module |
| Backing up `libraryDir` by default could be large (whole media library) | Matches existing Immich/Photoprism precedent of backing up full media trees by default; operator can override `backup.nix`'s per-service behavior the same way as those services if undesired |
| `grimmory-net` Docker network name could collide with a manually-created same-named network | Idempotent `docker network inspect \|\| create` guard, same as Joplin's `joplin-net` |
| Default `openFirewall = true` on the global list exposes an app with no published default admin credentials to the whole LAN until first visitor claims the admin account | Same trust model as Komga/Kavita/Jellyfin, all LAN-reachable by default in this repo; first visitor should claim the admin account promptly. Noted in module header comment |

## Sources

- https://github.com/grimmory-tools/grimmory — project overview, feature set, supported formats
- https://raw.githubusercontent.com/grimmory-tools/grimmory/develop/README.md — first-run flow,
  `/books` vs `/bookdrop` volume semantics, local/OIDC auth
- https://raw.githubusercontent.com/grimmory-tools/grimmory/develop/deploy/compose/docker-compose.yml —
  authoritative, maintained-by-upstream deployment reference: image tags, env var names, volumes,
  ports, healthcheck command
- `search.nixos.org` (via live MCP query, `unstable` channel) — confirmed no `grimmory` package or
  option exists in nixpkgs
- `lscr.io/linuxserver/mariadb` image conventions (`PUID`/`PGID`/`TZ`, s6-init self-chowning
  `/config`) — taken directly from upstream's own compose file and LinuxServer.io's documented
  base-image behavior, already implicitly relied upon by this repo's precedent reasoning in
  `joplin.nix`'s Postgres tmpfiles comment (same self-chowning class of base image)
- In-repo precedent review: `modules/server/joplin.nix` (two-container OCI + dedicated DB,
  secrets-init, dump timer — primary structural template), `modules/server/komga.nix` /
  `modules/server/kavita.nix` (Books & Comics section placement, global-firewall default),
  `modules/server/nginx-proxy-manager.nix` (single-container OCI port-mapping conventions),
  `modules/server/backup.nix`, `template/server-services.nix`, `justfile`
