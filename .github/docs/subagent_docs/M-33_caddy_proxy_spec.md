# M-33 — Caddy LAN reverse-proxy layer

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-33 (FEATURES 2.5)

## Scope decision (confirmed with user)

The plan's original ask included Avahi publication so `<service>.<hostname>.local`
names resolve automatically over mDNS. This repo's Avahi/mDNS configuration
(`modules/network.nix`'s `nssmdns4`/`denyInterfaces`,
`modules/network-desktop.nix`'s `publish.userServices`) is explicitly flagged
in standing project memory as hard-won and fragile (SMB/NAS discovery).
Presented the tradeoff to the user; confirmed scope: **add the Caddy
virtualHost layer only, with no new Avahi records.** The generated
`<service>.<hostname>.local` names are real Caddy virtualHosts (routable by
Host header) but require the operator's own DNS/hosts-file resolution to
reach by name — no change to the existing Avahi/mDNS setup.

## Current State

`modules/server/caddy.nix` already exists and documents exactly this pattern
in its own comment:
```
# Virtual hosts are configured in /etc/nixos/server-services.nix
# or via Caddy's JSON API.  Example:
#   services.caddy.virtualHosts."jellyfin.local".extraConfig = ''
#     reverse_proxy localhost:8096
#   '';
```
It manages `services.caddy.enable`, `httpPort`/`httpsPort` (default
8880/8443, shifted off 80/443 to avoid colliding with `nginx.nix`), and its
own `openFirewall`. This is the natural attachment point — `proxy.nix`
generates the `virtualHosts` this comment describes manually, on the same
Caddy instance, rather than starting a second one.

Enumerated every server module's enable option and web-UI port directly from
source (not assumed from memory) to build the service table below. Several
modules (`jellyfin`, `plex`, `tautulli`, `home-assistant`, `node-red`,
`komga`) don't expose a `vexos.server.<x>.port` option at all — they just set
the upstream module's `openFirewall = true` and rely on its fixed/default
port. Their ports are hardcoded in the table below, sourced from the actual
upstream NixOS module defaults (verified via nixpkgs source, not recalled):
Jellyfin 8096, Plex 32400, Tautulli 8181, Home Assistant 8123, Node-RED 1880,
Komga 8080. Reverse-proxy/infra modules that don't make sense to put behind
another proxy are excluded: `caddy`, `nginx`, `traefik`, `nginx-proxy-manager`
(all reverse proxies themselves), `unbound` (DNS, no HTTP UI), `matrix-conduit`
(API only, no browser UI), `papermc`/`rustdesk` (non-HTTP protocols).

## Proposed Solution

New `modules/server/proxy.nix`, `vexos.server.proxy.enable`, asserting
`vexos.server.caddy.enable = true`. Builds a static table of
`{ name, enable, port }` for ~40 services, filters to enabled ones, and
generates one `services.caddy.virtualHosts."<name>.${hostName}.local"` entry
per enabled service, each `reverse_proxy 127.0.0.1:<port>`. Caddy already
auto-detects `.local`/non-public hostnames and uses its internal CA for
these (no ACME/Let's Encrypt attempt), satisfying the plan's "local TLS"
without extra configuration.

Known maintenance tradeoff (documented in the file itself): this table is
hand-maintained and will need a one-line addition whenever a new server
module with a web UI is added — same category of drift risk as M-30, but
unavoidable without a much larger refactor (adding a uniform port-registration
convention to all ~40 existing modules, which is far outside this item's
blast radius).

## Implementation Steps

1. `modules/server/proxy.nix` — new file, service table, virtualHost
   generation, assertion on `vexos.server.caddy.enable`.
2. `modules/server/default.nix` — register the new module.

## Configuration Changes

New option defaults to `false` — zero behavior change unless explicitly
enabled, and even then only adds `virtualHosts` to an already-enabled Caddy
instance; no new firewall ports (reuses `caddy.nix`'s existing
`httpPort`/`httpsPort`).

## Risks and Mitigations

- **Risk:** a typo'd port in the hand-maintained table silently proxies to
  the wrong service.
  **Mitigation:** cross-checked every port against the actual module source
  (either the vexos wrapper's own option default or the upstream NixOS
  module's default) rather than recalling from memory; verified in Phase 3
  via `extendModules` that every enabled service's virtualHost target port
  matches its actual configured port.
- **Risk:** enabling `vexos.server.proxy` without `vexos.server.caddy`
  silently does nothing (Caddy never starts).
  **Mitigation:** unconditional assertion (outside `lib.mkIf`, matching the
  `arr.nix` pattern from M-32) requires `vexos.server.caddy.enable = true`.
- **Risk:** Avahi/SMB regression.
  **Mitigation:** explicitly out of scope per user decision — zero lines
  touched in `network.nix`/`network-desktop.nix`.
