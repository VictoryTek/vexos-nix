# M-23 — Services exposed LAN-wide with no authentication, no opt-out

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-23 (BUGS M26) · `loki.nix`, `netdata.nix`, `zigbee2mqtt.nix`,
`kiji-proxy.nix`, `portbook.nix` (all read in full)

## Current State

All five modules unconditionally open their port
(`networking.firewall.allowedTCPPorts = [ <port> ];`, no option gating it) and none
have any authentication of their own:
- `loki.nix`: `auth_enabled = false` explicitly set; port 3100 always opened.
- `netdata.nix`: no auth mechanism at all; port 19999 always opened.
- `zigbee2mqtt.nix`: frontend binds `0.0.0.0`, no auth on the web UI; port always opened.
- `kiji-proxy.nix`: no auth; forwards AI API traffic (including API keys via
  `environmentFile`) through an unauthenticated proxy; port always opened. Its own
  header comment already documents the intended usage as localhost-only
  (`HTTP_PROXY=http://127.0.0.1:<port>` in client env), making LAN-wide exposure by
  default a real gap, not a design choice.
- `portbook.nix`: read-only diagnostic info (port listing), no auth; port always opened.

## Problem Definition

Give each service an opt-out from LAN exposure, and specifically default kiji-proxy to
*not* being LAN-reachable at all, matching its own documented usage pattern.

## Proposed Solution

Add `openFirewall` to each module (matching the established pattern already used
elsewhere in this codebase, e.g. `vaultwarden.nix`):
- `loki.nix`, `netdata.nix`, `zigbee2mqtt.nix`, `portbook.nix`: `openFirewall` defaults
  to `true` — each of these is *meant* to be LAN-reachable for its core purpose (Loki
  receives logs from other machines; Netdata/Portbook are LAN dashboards; Zigbee2MQTT's
  whole point is a LAN-controllable web UI). Defaulting to `false` would silently break
  the primary use case for anyone who's already relying on it.
- `kiji-proxy.nix`: `openFirewall` defaults to **false** — its own documentation already
  frames it as localhost-only, and it's uniquely sensitive (proxies AI API traffic,
  potentially carrying API keys, with zero authentication of its own).

For kiji-proxy specifically, the MASTER_PLAN's literal wording is "bind kiji-proxy to
loopback by default" (an application-level bind-address change, e.g.
`PROXY_PORT=127.0.0.1:<port>`). Checked upstream (`pkgs/kiji-proxy/default.nix` +
`github.com/dataiku/kiji-proxy`) and could not confirm the binary's `PROXY_PORT` env
var accepts a `host:port` format rather than only a bare port/`:port` — the project's
own docs don't specify, and guessing wrong risks breaking the proxy outright (silently
ignoring the host part, or failing to start). Achieving the same practical outcome —
nothing else on the LAN can reach it — via `openFirewall = false` (leaving the
application's own bind behavior untouched) is lower-risk and doesn't depend on an
unverified assumption about the binary's argument parsing.

Add a one-line warning comment to each module's header noting the lack of built-in
authentication, so a user enabling `openFirewall = true` (or leaving it at that default
for the other four) does so with the tradeoff visible.

## Implementation Steps

1. `modules/server/loki.nix`, `netdata.nix`, `zigbee2mqtt.nix`, `portbook.nix` — add
   `openFirewall` option (default `true`); wire
   `networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall <port>;`;
   add a warning comment.
2. `modules/server/kiji-proxy.nix` — add `openFirewall` option (default `false`); wire
   the same way; add a warning comment.

## Configuration Changes

None.

## Risks and Mitigations

- **Behavior change for kiji-proxy**: existing deployments relying on LAN access to
  kiji-proxy would need to explicitly set `openFirewall = true` after this change —
  intentional, since the current default (always open) contradicts the service's own
  documented intended usage and its sensitivity (unauthenticated AI-traffic proxy).
- **No behavior change for the other four**: `openFirewall` defaults to `true`,
  matching current behavior exactly; only adds an opt-out that didn't exist before.
- **kiji-proxy bind address left unchanged** — explicitly documented above why, rather
  than silently deviating from the MASTER_PLAN's literal wording without explanation.
