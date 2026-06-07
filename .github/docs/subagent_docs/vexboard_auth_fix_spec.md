# Spec: vexboard service startup failure — missing configuration fields

## Current State Analysis

The upstream vexboard NixOS module (`inputs.vexboard.nixosModules.vexboard`) generates
`/etc/vexboard/config.toml` containing only `[server]` and `[database]` sections (via
`baseConfig`). The binary also searches for a relative `config/default.toml`, but the
systemd service runs with WorkingDirectory `/` (unset), so the file at
`/nix/store/.../config/default.toml` is never found.

`AppConfig` (vexboard-server/src/config.rs) requires the following top-level sections
with no serde defaults:
- `server` ✓ (in baseConfig)
- `database` ✓ (in baseConfig)
- `auth` ✗ MISSING
- `discovery` ✗ MISSING
- `docker` ✗ MISSING
- `probe` ✗ MISSING
- `metrics` ✗ MISSING

Deserialization fails at `auth` first (first missing field in struct declaration order),
producing: `Error: missing configuration field "auth"`.

The upstream module exposes a `settings` option (`lib.types.attrs`, merged via
`lib.recursiveUpdate` into the generated config.toml) specifically for supplying
configuration beyond the base. This is the correct integration point.

The `secretFile` option on the upstream module loads the file as `EnvironmentFiles` in
the systemd unit. Environment variable `VEXBOARD_AUTH__SECRET` (separator `__`) overrides
`auth.secret` from config.toml (env vars have highest priority in `AppConfig::load()`).
Our wrapper already wires `secretFile` through correctly.

## Problem Definition

`modules/server/vexboard.nix` enables `services.vexboard` without supplying the required
configuration sections. The binary fails to start immediately on any fresh enable.

## Proposed Solution

Add `settings` to the `services.vexboard` block in `modules/server/vexboard.nix` providing
defaults for all required sections not covered by `baseConfig`. Values mirror the upstream
`config/default.toml` exactly, so behaviour is identical to what the developer intended.

`auth.secret` is set to a clear placeholder string. When `secretFile` is provided by the
user, the `VEXBOARD_AUTH__SECRET` env var from that file overrides the placeholder at
runtime (env vars have highest priority). For home-server deployments without a secretFile,
the placeholder is acceptable — it signs user sessions; it is not a credential to an
external service.

## Implementation Steps

In `modules/server/vexboard.nix`, extend the `services.vexboard` block to add:

```nix
settings = {
  auth = {
    secret = "change-me-set-vexos.server.vexboard.secretFile";
    session_ttl_hours = 168;
  };
  discovery = {
    enabled = true;
    interval_secs = 60;
    server_services_only = true;
    exclude_units = [ ... full list from default.toml ... ];
  };
  docker = {
    enabled = true;
    interval_secs = 60;
    sockets = [ "/var/run/docker.sock" "/run/podman/podman.sock" ];
    exclude_images = [];
  };
  probe = {
    default_interval_secs = 30;
    timeout_secs = 5;
    max_history = 100;
  };
  metrics.push_interval_ms = 2000;
};
```

No other files require changes.

## Files to Modify

- `modules/server/vexboard.nix`

## Build/Test Commands (RAM-safe)

- `nix flake show`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-vm`

## Risks and Mitigations

- Risk: auth.secret placeholder in Nix store is world-readable → mitigated by `secretFile`
  option; acceptable for home-server use and clearly labelled as a placeholder.
- Risk: upstream adds required fields in a new release → mitigated by `lib.recursiveUpdate`
  merge — user can extend via `settings` in server-services.nix.
- Risk: discovery.exclude_units diverges from upstream default.toml → no functional risk;
  the user can override via `settings`.
