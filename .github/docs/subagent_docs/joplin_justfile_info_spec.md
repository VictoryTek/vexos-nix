# Joplin justfile info messages — spec

## Current state analysis

`modules/server/joplin.nix` implements Joplin Server as a two-container OCI
stack (`joplin-server` + `joplin-db`), Tailscale-only, on port
`vexos.server.joplin.port` (default `22300`), with a documented first-login
(`admin@localhost` / `admin`).

`justfile` has three places that give per-service info, keyed by a
`case "$SERVICE" in ... esac` block. Every other server service in
`modules/server/` has an entry in all three. `joplin` is missing from all
three, despite being listed in `_server_service_names` (line 1133) and the
`_svc joplin ...` catalog entry (line 1333):

1. **`_info` function** (~justfile:1405, used by `just info <service>`) —
   falls through to the `*` catch-all: `(no info available)`.
2. **`just status <service>`** case (~justfile:1508) — falls through to the
   `*` catch-all: `UNITS="$SERVICE"` (wrong — actual systemd units are
   `docker-joplin-server` / `docker-joplin-db`), `URLS=""` (no reachability
   check).
3. **Post-`just enable <service>` info case** (~justfile:1800-2300) — no
   `joplin)` branch at all, so `just enable joplin` prints only the generic
   `✓ Enabled: joplin` / `→ Run 'just rebuild' to apply.` / VexBoard hint —
   never the Web UI URL. This is the bug the user hit.

## Problem definition

`just enable joplin` gives no indication of how to reach the Joplin web UI,
unlike every other service. Root cause: three missing `case` branches in
`justfile`, not a Nix module issue.

## Proposed solution

Add a `joplin)` branch to each of the three `case` statements, following the
existing per-service pattern and reflecting joplin.nix's actual facts:
Tailscale-only exposure, port 22300 default, two backing units, first-login
credentials, and the port's own recommendation to change the baseUrl option
for non-default tailnets.

## Implementation steps

All changes are confined to `justfile` (no `lib.mkIf`/module pattern
applies — this is a shell script, not a NixOS module).

1. **`_info` case (~justfile:1434, alphabetically near `jellyfin`/`kavita`)**:
   ```
   joplin)          printf "  %-18s  Web UI  http://<tailnet-host>:22300   (Tailscale-only)\n" "$1" ;;
   ```

2. **`just status` case (~justfile:1509, alphabetically near
   `jellyfin`/`kavita`)**:
   ```
   joplin)         UNITS="docker-joplin-server docker-joplin-db"; URLS="http://localhost:22300" ;;
   ```

3. **Post-enable info case (~justfile:1905-1916, alphabetically near
   `jellyfin`/`kavita`)**:
   ```
   joplin)
     echo "  Services: docker-joplin-server.service  docker-joplin-db.service"
     echo "  Web UI:   http://<tailnet-host>:22300   (Tailscale-only — see networking.firewall.interfaces.tailscale0)"
     echo "  About:    Self-hosted sync server for Joplin desktop/mobile clients (two-container stack: app + dedicated Postgres)."
     echo "  Login:    admin@localhost / admin — change from the web UI after first boot."
     echo "  Note:     If clients get 'invalid origin' sync errors, set vexos.server.joplin.baseUrl to your tailnet's fully-qualified MagicDNS name."
     ;;
   ```

Port number and firewall scope are read from `modules/server/joplin.nix`
(`cfg.port` default 22300, `networking.firewall.interfaces.tailscale0`); no
hardcoding beyond what other Tailscale/port-scoped entries already do
elsewhere in the file.

## Dependencies

None — no new external library or dependency involved. Context7 lookup not
required (pure shell/justfile edit, no framework API surface).

## Configuration changes

None to Nix modules. `justfile` text only.

## Risks and mitigations

- **Risk:** typo in unit names breaks `just status joplin`.
  **Mitigation:** unit names (`docker-joplin-server`, `docker-joplin-db`)
  are read directly from `virtualisation.oci-containers.containers.*`
  names in `modules/server/joplin.nix:150,163` (NixOS OCI container module
  auto-prefixes container names with `docker-` when
  `virtualisation.oci-containers.backend = "docker"`, matching the pattern
  used for `dockhand`/`stirling-pdf`/`uptime-kuma` entries already in the
  file).
- **Risk:** none to build — `justfile` is not evaluated by Nix.
