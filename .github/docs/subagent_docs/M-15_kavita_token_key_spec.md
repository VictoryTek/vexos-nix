# M-15 — Kavita crash-loops without a manually created token file

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-15 (BUGS M22) · `modules/server/kavita.nix:22`

## Current State

```nix
services.kavita = {
  enable = true;
  port = 5000;
  tokenKeyFile = "/var/lib/kavita/token-key"; # Must exist; generate with: openssl rand -base64 32 > /var/lib/kavita/token-key
};
```

Verified against the pinned nixpkgs revision (`nixos/modules/services/web-apps/kavita.nix`):
`tokenKeyFile` has no default (mandatory, `type = lib.types.path`) and is consumed via
`serviceConfig.LoadCredential = [ "token:${cfg.tokenKeyFile}" ];`. `LoadCredential=`
requires the referenced file to exist and be readable by the service manager (root) at
unit start — if it's missing, systemd fails to start the unit outright, and with
`Restart = "always"` (set by the upstream module), the unit retries forever without
ever succeeding: a permanent crash loop, exactly as reported. The comment tells the user
to create the file manually, but nothing in this module enforces or automates it, and
`just enable kavita` (the standard workflow every other service in this project uses)
gives no indication this step is required.

The upstream module's own description: "a secret with at 512+ bits... generated with
`head -c 64 /dev/urandom | base64 --wrap=0`" — a purely internal JWT signing key, never
typed or memorized by a human. Unlike code-server's password (which a user must
actually know to log in), there's no reason to require manual creation here.

## Problem Definition

Kavita must never crash-loop on first enable; the token key should be handled the same
way this codebase already handles other purely-internal secrets that don't need human
input (e.g. VexBoard's auth secret, H-15).

## Proposed Solution

Auto-generate the token key on first activation via `system.activationScripts`,
matching the exact pattern already established for VexBoard's secret
(`modules/server/vexboard.nix`): idempotent (only generates if missing), creates the
containing directory itself rather than depending on ordering relative to kavita's own
`systemd.tmpfiles` rule, and writes with `chmod 0600` (root-owned, which is fine since
`LoadCredential=` is processed by the service manager as root regardless of the
containing directory's ownership).

## Implementation Steps

1. `modules/server/kavita.nix` — add
   `system.activationScripts.kavitaTokenKey` generating
   `/var/lib/kavita/token-key` via `openssl rand -base64 64 | tr -d '\n'` (64 random
   bytes = 512 bits, matching the upstream module's own stated minimum) when the file
   doesn't already exist.

## Configuration Changes

None.

## Risks and Mitigations

- **Directory ownership**: `/var/lib/kavita` is created by kavita's own upstream
  `systemd.tmpfiles.rules` as `kavita:kavita 0750`, but the activation script also
  `mkdir -p`s it itself (root-owned fallback if it runs first) — root can read/write
  there regardless either way, and `LoadCredential=` reads the file as root before the
  kavita user is ever involved, so ownership of the token file itself doesn't need to
  match the kavita user.
- **Verify the generated key satisfies the 512-bit minimum** — confirmed
  `openssl rand -base64 64` produces exactly 64 random bytes (512 bits) before
  base64 encoding, matching the upstream module's own documented generation command.
