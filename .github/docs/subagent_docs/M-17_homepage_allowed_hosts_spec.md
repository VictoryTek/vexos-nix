# M-17 — Homepage rejects all requests without HOMEPAGE_ALLOWED_HOSTS

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-17 (BUGS M24) · `modules/server/homepage.nix`

## Current State

```nix
virtualisation.oci-containers.containers.homepage = {
  image = "ghcr.io/gethomepage/homepage:latest";
  ports = [ "${toString cfg.port}:3000" ];
  volumes = [ "homepage-config:/app/config" "/var/run/docker.sock:/var/run/docker.sock:ro" ];
};
```

Homepage v0.10+ (this module always pulls `:latest`) requires `HOMEPAGE_ALLOWED_HOSTS`
— a comma-separated list of exact `host:port` combinations permitted in the incoming
`Host` header (added for CSRF protection around Next.js Server Actions). There is no
wildcard support — every hostname/IP the dashboard will actually be accessed through
must be listed explicitly. Without this env var set, Homepage rejects every request
regardless of what host/port it's reached on.

## Problem Definition

Wire up `HOMEPAGE_ALLOWED_HOSTS` so the dashboard is reachable at all, while letting
the user customize it for their actual LAN hostname(s)/IP(s) — which aren't knowable at
build time in a generic template repo.

## Proposed Solution

Add `vexos.server.homepage.allowedHosts` (a plain string option, matching this module's
existing style for `port` — not a hard-assertion-gated required option, since a working
default exists), defaulting to `"localhost:${toString cfg.port}"` (works for direct
on-host access and testing out of the box) with a description telling the user to add
their real LAN hostname/IP for remote access. Wire it to
`environment.HOMEPAGE_ALLOWED_HOSTS`.

## Implementation Steps

1. `modules/server/homepage.nix` — add the `allowedHosts` option; add
   `environment.HOMEPAGE_ALLOWED_HOSTS = cfg.allowedHosts;` to the container
   definition.

## Configuration Changes

None.

## Risks and Mitigations

- **No wildcard support in Homepage itself** — documented in the option description
  rather than worked around; the user must list every access path explicitly, which is
  an upstream Homepage constraint, not something this module can paper over.
- **Default only covers `localhost`** — a real LAN deployment needs the user to add
  their server's actual address; this is unavoidable without knowing the deployment's
  network topology at build time, same class of constraint as `vaultwarden.domain`.
