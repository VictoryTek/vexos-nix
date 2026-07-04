# M-04 — headscale serverUrl bound to 0.0.0.0

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-04 · `modules/server/headscale.nix:24`

## Current State

```nix
services.headscale = {
  enable = true;
  port = cfg.port;
  serverUrl = "http://0.0.0.0:${toString cfg.port}";
  ...
};
```

`server_url` (headscale's own term) is not a bind address — it's the public URL every
Tailscale client receives in its config and then tries to *connect to directly*.
`0.0.0.0` is a wildcard bind address with no meaning as a connection target; every
client would fail to reach the control server. This is broken for any real deployment,
not an edge case.

Verified against the pinned nixpkgs revision
(`nixos/modules/services/networking/headscale.nix`, read in full): the top-level
`services.headscale.serverUrl` option this module currently sets is **deprecated** —
`mkRenamedOptionModule [ "services" "headscale" "serverUrl" ] [ "services" "headscale"
"settings" "server_url" ]` forwards it with a warning. The current option is
`services.headscale.settings.server_url` (default `"http://127.0.0.1:8080"`, also a
placeholder value, description: "The url clients will connect to."). This directly
confirms the API-currency question the MASTER_PLAN item raised.

## Problem Definition

Headscale needs a real, externally-reachable URL, not a bind address, and the module
should use the current (non-deprecated) option path.

## Proposed Solution

Add a required `vexos.server.headscale.serverUrl` option, following the exact pattern
already established in this codebase for "must be set to a real value" options
(`vaultwarden.nix`'s `domain`): a deliberately-invalid placeholder default plus a hard
assertion, rather than silently defaulting to something that looks plausible but isn't.

```nix
serverUrl = lib.mkOption {
  type = lib.types.str;
  default = "https://headscale.example.com";
  description = ''
    Public URL that Tailscale clients connect to directly — must be a real,
    externally-reachable address (e.g. "https://headscale.example.com" or
    "http://192.168.1.50:8085"), never a bind address like 0.0.0.0. The default
    placeholder is intentionally invalid.
  '';
};
```

Wire it to the current, non-deprecated option path:
`services.headscale.settings.server_url = cfg.serverUrl;` (not the deprecated top-level
`serverUrl`).

## Implementation Steps

1. `modules/server/headscale.nix` — add the `serverUrl` option, an assertion that it's
   been changed from the placeholder, and set `services.headscale.settings.server_url`
   instead of the deprecated `services.headscale.serverUrl`.

## Configuration Changes

None — no flake changes, no new dependencies.

## Risks and Mitigations

- **Existing deployments with the old broken default** will now hit the assertion and
  fail to build until they set `vexos.server.headscale.serverUrl` — this is the correct
  outcome (their headscale was already non-functional for real clients; the assertion
  makes that visible instead of silently deploying something broken).
- **`services.headscale.address`** (default `127.0.0.1`, controls the actual bind
  address) is untouched — out of scope for this fix, which is specifically about
  `server_url`, not the listen address.
