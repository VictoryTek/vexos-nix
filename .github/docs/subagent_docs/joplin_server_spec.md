# Joplin Sync Server — Implementation Spec

## Current State Analysis

- `modules/server/` follows a consistent per-service module pattern: `options.vexos.server.<svc>`,
  `config = lib.mkIf cfg.enable { ... }`, `networking.firewall.allowedTCPPorts = lib.optional
  cfg.openFirewall cfg.port;`. Services with no native NixOS module (Arcane, Dockhand, Portainer,
  Dozzle, etc.) are deployed via `virtualisation.oci-containers.containers.<name>` — see
  `modules/server/arcane.nix` as the closest precedent (single OCI container, `environmentFile`
  for secrets, `appUrl`-style required-URL assertion).
- **No nixpkgs package or NixOS module exists for Joplin Server** (confirmed: `pkgs.joplin-server`
  is absent from the pinned `nixos-26.05` nixpkgs; only `joplin-desktop`, the client app, is
  packaged). It must be deployed as an OCI container, same as Arcane/Dockhand.
- `modules/server/default.nix` is a flat import list wired into both `configuration-server.nix`
  and `configuration-headless-server.nix` via `./modules/server`; no per-role choice is needed —
  adding the module here makes it available (but disabled by default) on both server roles.
- `modules/server/backup.nix` maintains a `servicePaths` map keyed by service name, and its own
  header comment explicitly invites new service modules to add an entry there so they're covered
  by the existing restic backup job with no separate list to maintain. It has a hardcoded
  `config.services.postgresql.enable` special case that runs `pg_dumpall` for the **native**
  Postgres service only — it does not (and, by design here, should not) know about per-container
  Postgres instances.
- `modules/network.nix` enables `services.tailscale` universally (all roles), with
  `extraUpFlags = [ "--accept-routes=false" ]`. No MagicDNS domain or tailnet name is recorded
  anywhere in the repo — the operator will supply the actual tailnet hostname/IP at deploy time.
- `modules/server/cockpit.nix` establishes the repo's precedent for interface-scoped firewall
  rules (`networking.firewall.interfaces.<ifname>.allowedTCPPorts`) instead of the global
  `networking.firewall.allowedTCPPorts` list, for services that should only be reachable over a
  specific interface.
- `template/server-services.nix` documents every toggle with a commented example line, and
  `justfile`'s `_server_service_names` variable is the authoritative list consumed by
  `just enable/disable <service>` for validation.

## Problem Definition

Add Joplin Server as a new optional server service (`vexos.server.joplin.enable`) so the user's
Joplin desktop/mobile clients can sync notes against a self-hosted server, reachable only over
their existing Tailscale tailnet (per user decision — no public exposure, no reverse proxy/TLS
needed since Tailscale's WireGuard tunnel already encrypts the transport).

## Decisions Confirmed With User

1. **Database:** dedicated containerized PostgreSQL (`postgres:16`), not SQLite and not the host's
   native `services.postgresql`. Rationale discussed and accepted: matches Joplin's own official
   `docker-compose.server.yml` reference topology; avoids opening the host's shared Postgres to
   TCP/pg_hba access from the Docker bridge (which would be a non-surgical change affecting every
   current/future consumer of native Postgres on the host).
2. **Exposure:** Tailscale tailnet only. No reverse proxy, no ACME/TLS cert. Firewall rule scoped
   to the `tailscale0` interface only (cockpit.nix precedent), not the global allowed-ports list.
3. **Mailer/SMTP:** skipped. No `MAILER_*` environment variables in v1. The single default admin
   account's password is changed manually through the web UI after first boot (documented in the
   module header comment, matching how Vaultwarden's admin token and Nextcloud's admin password
   are handled).

## Proposed Solution Architecture

New file: `modules/server/joplin.nix` (role-agnostic addition — Option B "addition file" for the
optional-service layer; no `lib.mkIf` role/display/gaming guards involved, so no separate
qualifier file is needed, matching how `vaultwarden.nix`/`arcane.nix` are structured).

### Containers (Docker backend, via `virtualisation.oci-containers`)

Two containers on a dedicated user-defined Docker network `joplin-net` (first two-container stack
in this repo — no existing single-container service needs inter-container DNS, so a small oneshot
systemd unit is added to create the network idempotently before either container starts):

- `joplin-db` — `postgres:16`, no published ports (reachable only from `joplin-server` over
  `joplin-net`), data at `${cfg.dataDir}/postgres`.
- `joplin-server` — `joplin/server:latest`, publishes `${cfg.port}:22300`, connects to `joplin-db`
  by container name (Docker's embedded DNS resolves container names on user-defined networks).

```
systemd.services."joplin-network" = {
  description   = "Create dedicated Docker network for the Joplin Server stack";
  wantedBy      = [ "multi-user.target" ];
  after         = [ "docker.service" ];
  requires      = [ "docker.service" ];
  serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  script = ''
    ${pkgs.docker}/bin/docker network inspect joplin-net >/dev/null 2>&1 || \
      ${pkgs.docker}/bin/docker network create joplin-net
  '';
};
```

Both containers get `extraOptions = [ "--network=joplin-net" ];` and their generated
`docker-<name>.service` units get `after`/`requires` on `joplin-network.service`
(`docker-joplin-server.service` additionally depends on `docker-joplin-db.service`).

### Options (`options.vexos.server.joplin`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | bool | false | `mkEnableOption` |
| `port` | port | 22300 | Host port for the app container (Joplin's own default) |
| `baseUrl` | str | `"http://joplin.example.ts.net:22300"` | Placeholder intentionally invalid, asserted non-default, matching `vaultwarden.domain`/`arcane.appUrl`. Documented as "set to your Tailscale MagicDNS name or tailnet IP" |
| `dataDir` | str | `/var/lib/joplin-server` | Host dir for Postgres data (`postgres/`) and nightly dump (`dump/`) |
| `environmentFile` | nullOr path | null | systemd EnvironmentFile supplying `POSTGRES_PASSWORD` (shared by both containers); required via assertion |
| `openFirewall` | bool | true | Opens `${cfg.port}` on the `tailscale0` interface only, **not** the global allowed-ports list |

### Environment variables (app container)

```
APP_PORT          = "22300"
APP_BASE_URL      = cfg.baseUrl
DB_CLIENT         = "pg"
POSTGRES_DATABASE = "joplin"
POSTGRES_USER     = "joplin"
POSTGRES_PORT     = "5432"
POSTGRES_HOST     = "joplin-db"
```
(`POSTGRES_PASSWORD` comes from `environmentFile`, shared with the `joplin-db` container which
also needs `POSTGRES_USER`/`POSTGRES_DB` set via plain `environment` and `POSTGRES_PASSWORD` via
the same `environmentFile`.)

### Assertions

- `cfg.environmentFile != null` — required, must supply `POSTGRES_PASSWORD=...`.
- `cfg.baseUrl != "http://joplin.example.ts.net:22300"` — must be set to the real tailnet
  hostname/IP, mirroring the `vaultwarden.domain`/`arcane.appUrl` pattern.

### Backup integration

A nightly `pg_dump` (not a raw file-copy of the live `postgres/` data directory, which would be
backup-inconsistent) writing to `${cfg.dataDir}/dump/joplin.sql`:

```
systemd.services."joplin-postgres-dump" = {
  description = "Dump Joplin PostgreSQL database for backup";
  after    = [ "docker-joplin-db.service" ];
  requires = [ "docker-joplin-db.service" ];
  serviceConfig.Type = "oneshot";
  script = ''
    install -d -m 0700 "${cfg.dataDir}/dump"
    ${pkgs.docker}/bin/docker exec joplin-db pg_dump -U joplin joplin > "${cfg.dataDir}/dump/joplin.sql"
  '';
};
systemd.timers."joplin-postgres-dump" = {
  wantedBy = [ "timers.target" ];
  # Scheduled before backup.nix's restic "daily" default (systemd's "daily" ≈ 00:00) so a fresh
  # dump exists before the day's restic run reads this path.
  timerConfig = { OnCalendar = "*-*-* 23:30:00"; Persistent = true; };
};
```

One line added to `modules/server/backup.nix`'s `servicePaths` map:
```nix
joplin = [ "${config.vexos.server.joplin.dataDir}/dump" ];
```
(Deliberately backs up only the `dump/` subdirectory, not `postgres/` — same reasoning as the
native-Postgres `pg_dumpall` special case: dump files are safe to file-backup, live database
files are not.)

### Firewall

```nix
networking.firewall.interfaces.tailscale0.allowedTCPPorts =
  lib.optional cfg.openFirewall cfg.port;
```
No entry added to the global `networking.firewall.allowedTCPPorts` — the service must not be
reachable from the LAN/WAN interface, per the user's Tailscale-only decision.

### Other repo touch points (Phase 2 scope)

- `modules/server/default.nix` — add `./joplin.nix` (Cloud & Files section, next to `nextcloud.nix`/`syncthing.nix`).
- `modules/server/backup.nix` — add the `joplin` servicePaths entry above.
- `template/server-services.nix` — add a commented example block (enable flag + `baseUrl` +
  `environmentFile` + generation command for the Postgres password), in the Cloud & Files section.
- `justfile`'s `_server_service_names` — add `joplin` to the space-separated list (alphabetical:
  between `jellyfin` and `kavita`).

## Dependencies

- `joplin/server:latest` (Docker Hub) — no nixpkgs equivalent exists; pulled at container-start
  time like every other OCI-container service in this repo (Arcane, Dockhand, Portainer, etc.).
  Context7 was checked and has no entry for Joplin (not a code library); research was done via
  the official Docker Hub page and Joplin's own `docker-compose.server.yml` in its GitHub repo
  instead (see Sources below).
- `postgres:16` (Docker Hub) — matches the version pinned in Joplin's own official compose
  reference file.
- No new flake inputs; no changes to `flake.nix`.

## Configuration Changes Required Post-Merge (operator, not Claude)

1. `sudo install -d -m 0700 -o root -g root /etc/nixos/secrets` (if not already present).
2. `echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)" | sudo tee /etc/nixos/secrets/joplin-env >/dev/null && sudo chmod 0600 /etc/nixos/secrets/joplin-env`
3. In `/etc/nixos/server-services.nix`:
   ```nix
   vexos.server.joplin.enable = true;
   vexos.server.joplin.baseUrl = "http://<your-tailscale-magicdns-name-or-ip>:22300";
   vexos.server.joplin.environmentFile = "/etc/nixos/secrets/joplin-env";
   ```
4. `just enable joplin` / `just rebuild` (or `sudo nixos-rebuild dry-build` per Phase 3/6 gates —
   actual `switch` is user-initiated only, per FORBIDDEN COMMANDS).
5. First login at `http://<tailnet-address>:22300` with `admin@localhost` / `admin`, then
   immediately change the admin password.
6. Point each Joplin client at Synchronisation target "Joplin Server", URL =
   `vexos.server.joplin.baseUrl`, with the admin (or a newly created) account's credentials.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Two-container stack is new territory for this repo's OCI-container modules | Kept the network-creation logic to one small idempotent oneshot unit; documented inline; no impact on any other module |
| `joplin-net` Docker network name could collide if the operator manually creates a same-named network | Idempotent `docker network inspect \|\| create` guard avoids failure; name is specific enough (`joplin-net`) to be an unlikely collision |
| Dedicated Postgres isn't covered by `backup.nix`'s native `pg_dumpall` path | Nightly `pg_dump` timer + one `servicePaths` entry gives equivalent coverage without touching the shared native-Postgres logic |
| Dump timer racing the restic backup timer | Dump scheduled for 23:30, restic's default "daily" (~00:00) runs after — documented assumption; if the operator customizes `vexos.server.backup.timerConfig` to run earlier than 23:30, the dump could be stale for one cycle (noted in module comment) |
| Firewall scoped to `tailscale0` assumes `services.tailscale.enable` is on for this host | Already true for all roles via `modules/network.nix` (base module, unconditional) — verified, not an added dependency |
| Default admin credentials (`admin@localhost`/`admin`) are public knowledge (upstream default) | Documented prominently in the module header comment (same treatment as Vaultwarden's `ADMIN_TOKEN` and Nextcloud's admin password), instructing immediate password change after first login. Acceptable residual risk since the service is Tailscale-only, not internet-facing |
| Postgres container has no published port, but shares the host's Docker daemon with every other OCI-container service | Same trust boundary as every other Docker-based service already in this repo (Arcane, Portainer, Dockhand, etc.) — no new exposure introduced |

## Addendum: Zero-Config Revision

After initial implementation and review, the user requested no post-enable manual steps at all
(no manual secrets file, no manual `baseUrl` tuning, no mandatory password-change checklist).
Revised design:

- `environmentFile` is now optional (default `null`). When unset, a new `joplin-secrets-init`
  oneshot systemd unit generates `POSTGRES_PASSWORD` via `openssl rand -hex 24` on first
  activation, writing it to `${dataDir}/secrets/joplin-env` (0600, root-only, idempotent —
  skipped if the file already exists). Both containers' ordering (`after`/`requires`) now
  includes this unit whenever `environmentFile == null`.
- `baseUrl` now defaults to `"http://${config.networking.hostName}:${toString cfg.port}"` instead
  of an invalid placeholder — Tailscale MagicDNS resolves bare hostnames for most tailnets (it
  adds the tailnet's DNS search domain to resolv.conf), so this works out of the box without
  requiring the operator to know their tailnet's `.ts.net` suffix at option-set time.
- Both assertions (`baseUrl != placeholder`, `environmentFile != null`) are removed — `enable =
  true;` alone is now sufficient to deploy a working instance.
- The "change the admin password immediately" instruction was demoted from a required step to
  an informational recommendation in the module header comment, since the service is
  Tailscale-only (not internet-facing) and this repo treats that as an acceptable residual risk
  for a personal instance (same treatment already given to Vaultwarden's `ADMIN_TOKEN` handling).

No changes to the container/network/backup architecture from the original spec — only the
configuration-surface and secret-provisioning mechanics changed.

## Sources

- https://hub.docker.com/r/joplin/server — official image, env var reference (`APP_PORT`,
  `APP_BASE_URL`, `DB_CLIENT`, `POSTGRES_*`, `STORAGE_DRIVER`, default admin credentials, SQLite
  vs. Postgres guidance)
- https://github.com/laurent22/joplin/blob/dev/docker-compose.server.yml — official reference
  compose topology (confirms `postgres:16`, `db`/`app` service split, env var names)
- https://discourse.joplinapp.org/t/mailer-settings/42716 — Joplin forum, mailer env var behavior
  and known issues (informed the decision to skip mailer for v1)
- https://knightli.com/en/2026/06/05/joplin-server-docker-compose-setup/ — reverse proxy guidance,
  `APP_BASE_URL` format rules, default admin credential handling
- https://docs.vultr.com/how-to-host-a-joplin-server-with-docker-on-ubuntu — firewall/port
  guidance, client-side sync configuration steps, admin password change flow
- nixpkgs search (`nixos-26.05`, pinned in this repo's `flake.nix`) — confirmed no
  `pkgs.joplin-server` package and no `services.joplin-server` NixOS module exist; only
  `joplin-desktop` (client) is packaged
- In-repo precedent review: `modules/server/arcane.nix`, `modules/server/vaultwarden.nix`,
  `modules/server/nextcloud.nix`, `modules/server/dockhand.nix`, `modules/server/cockpit.nix`,
  `modules/server/backup.nix`, `modules/network.nix`, `template/server-services.nix`, `justfile`
