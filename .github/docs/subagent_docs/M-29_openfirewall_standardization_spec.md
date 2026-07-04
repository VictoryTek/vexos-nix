# M-29 — Firewall exposure inconsistency: standardize `openFirewall`

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-29 (ARCH 3.1) · scattered across `modules/server/*`

## Current State

23 of 58 `modules/server/*.nix` modules already expose an `openFirewall` option
(`bool`, default `true`) that gates their `networking.firewall.allowedTCPPorts` /
`allowedUDPPorts` assignment via `lib.optional`/`lib.optionals`. Read every remaining
file directly (not relying on the MASTER_PLAN's own count, which is approximate) and
found 29 modules that assign firewall ports unconditionally:

`headscale`, `forgejo`, `minio`, `matrix-conduit`, `arcane`, `traefik`, `syncthing`,
`dozzle`, `nextcloud`, `caddy`, `attic`, `paperless`, `grafana`, `dockhand`,
`stirling-pdf`, `code-server`, `kavita`, `navidrome`, `portainer`, `photoprism`,
`ntfy`, `authelia`, `nginx-proxy-manager`, `listmonk`, `homepage`, `nginx`,
`uptime-kuma`, `unbound`, `proxmox`, `mealie`.

**One exception found on inspection: `syncthing` already conforms.** It has its own
toggle (`openGuiFirewall`, default `false`) that gates the one port that actually
needs gating (the GUI, which has no auth by default) — the sync ports themselves are
opened via NixOS's own `services.syncthing.openDefaultPorts`, which is core,
always-on Syncthing functionality, not a security-sensitive default. Renaming
`openGuiFirewall` → `openFirewall` would be purely cosmetic and would blur the fact
that it only gates the GUI, not "the firewall" broadly — leaving it as-is.

Of the true 29, two hardcode a literal port instead of using a typed `port` option:
`kavita` (`settings.Port = 5000`, firewall `[ 5000 ]`) and `ntfy`
(`listen-http = ":2586"`, firewall `[ 2586 ]`). Both need a `port` option added per the
MASTERPLAN's request ("Add ... a typed `port` option"), in addition to `openFirewall`.

## Problem Definition

Enabling any of these 29 services unconditionally opens its port(s) to the network,
with no per-module way to opt out (e.g. running the service bound to localhost/VPN
only, behind a separate reverse proxy that itself is the only exposed port). This is
inconsistent with the 23 modules that already give the operator this choice, and
several of the 29 (code-server, minio console, dockhand pre-auth, arcane
root-equivalent Docker access) are exactly the kind of sensitive services where an
opt-out matters most.

## Proposed Solution

Apply the exact pattern already established by the 23 conforming modules to all 29:

1. Add `openFirewall = lib.mkOption { type = lib.types.bool; default = true;
   description = "..."; };` to each module's options block. `default = true`
   preserves current behavior exactly — this is purely an opt-out, not a behavior
   change.
2. Wrap each module's `networking.firewall.allowedTCPPorts`/`allowedUDPPorts`
   assignment in `lib.optional cfg.openFirewall <port>` (single port) or
   `lib.optionals cfg.openFirewall [ <ports> ]` (multiple ports), matching the
   existing convention in `loki.nix`/`kiji-proxy.nix`/etc.
3. For `kavita` and `ntfy`: add a typed `port = lib.mkOption { type =
   lib.types.port; default = <current hardcoded value>; ... }` option, thread it
   through the service config in place of the literal, and gate the firewall
   entry the same way as every other module.
4. `traefik`: its `dashboardPort` is already independently gated by
   `insecureDashboard`; combine both conditions (`cfg.openFirewall &&
   cfg.insecureDashboard`) so a global `openFirewall = false` also suppresses the
   dashboard port, not just `httpPort`/`httpsPort`.
5. `nextcloud`: port 80/443 are already conditionally opened based on
   `cfg.https`/`cfg.allowInsecureHttp`; AND those conditions with `cfg.openFirewall`.
6. `syncthing`: no change — already conforms via its own correctly-scoped toggle.

No change to `ci.yml`, `flake.nix`, or any non-server module — this item is scoped to
`modules/server/*.nix` per its MASTER_PLAN source (`ARCH 3.1`).

## Implementation Steps

For each of the 29 files, add the `openFirewall` option and gate the firewall
assignment. `kavita`/`ntfy` additionally get a `port` option. `traefik`/`nextcloud`
combine the new toggle with their existing conditional logic instead of replacing it.

## Configuration Changes

None — every new option defaults to `true`, so no `nixosConfigurations` output
changes behavior unless a host explicitly sets `openFirewall = false`.

## Risks and Mitigations

- **Risk:** a typo in the `lib.optional`/`lib.optionals` wrapping could silently drop
  a port that should stay open.
  **Mitigation:** every edit is a mechanical wrap of the existing port list/value —
  verified via `nix eval` per-target evaluation in Phase 3, plus a targeted
  `extendModules` check enabling a sample of the changed services with
  `openFirewall` at its default (`true`) to confirm the port set is unchanged from
  before the edit.
- **Risk:** `kavita`/`ntfy` port-option threading could break the service if the
  option isn't wired into every place the literal previously appeared.
  **Mitigation:** grepped each file for all occurrences of the literal port number
  before editing to ensure every occurrence is replaced.
