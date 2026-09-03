# Harmonia cache: opt-in instead of on-by-default — Spec

## Current state

`modules/nix.nix` (universal base, imported by every `configuration-*.nix`) declares:

- `vexos.harmonia.cacheUrl` default `"http://cache:5000"`
- `vexos.harmonia.publicKey` default `"vexos-vmc-1:Nm4amMYYdvIlY7EZUHbDVI0GTY8orUpWRM89UpX1Vjs="`

Because both are non-empty, `nix.settings.substituters` / `trusted-public-keys`
(lines 144-152) add `http://cache:5000` on **every host and every variant**.

The `cache` MagicDNS name was never actually provisioned and the Harmonia host
was only ever a test, so every rebuild on every machine now emits:

```
warning: unable to download 'http://cache:5000/nix-cache-info': Could not resolve host: cache
```

(5 retries per rebuild). Disabling the server does not help — the client
substituter list is driven entirely by these committed defaults.

## Problem

A binary cache that "every present and future host picks up automatically" was
wired as a default. It never worked, and it should not be enabled fleet-wide by
default. Nothing in the repo opts in explicitly, so nothing depends on the
default value.

## Solution

Make `vexos.harmonia` opt-in, symmetric with the `vexos.attic` option pair
directly above it (which already defaults to `null` / `""` = off):

- `vexos.harmonia.cacheUrl` default → `null`
- `vexos.harmonia.publicKey` default → `""`
- Update the option-block comments and `publicKey` description to describe
  opt-in usage (set both in a host config / `server-services.nix`) instead of
  "commit the key and every host picks it up".

No change to the `config` block: lines 104-152 already gate every
harmonia/attic substituter and key behind `cacheUrl != null` / `publicKey != ""`,
and the `warnings` entry (119-126) already covers "cacheUrl set, key missing".

## Implementation steps

1. `modules/nix.nix`: flip the two defaults.
2. `modules/nix.nix`: rewrite the `# ── Harmonia client options ──` comment
   block and the `publicKey` option `description` to reflect opt-in.

Module Architecture Pattern: unchanged. `modules/nix.nix` stays a universal
base with no role/flag `lib.mkIf`. The `cacheUrl != null` guard is the
module's own toggleable-subsystem carve-out (explicitly allowed).

## Dependencies

None. No new inputs, no external APIs.

## Risks & mitigations

- **Risk:** a host that silently relied on the default cache loses it.
  **Mitigation:** `grep -rn 'vexos.harmonia' hosts/ template/ configuration-*.nix`
  returns nothing — no consumer exists. The cache also never resolved.
- **Risk:** the Harmonia *server* module (`modules/server/harmonia.nix`) and
  `kernel-builder.nix` still work; they are independent (`vexos.server.harmonia.*`).
  A future cache host re-enables clients by setting `vexos.harmonia.cacheUrl`
  + `publicKey` explicitly. Documented in the rewritten comment.
- **Stale `/etc/nix/nix.conf`:** the `http://cache:5000` entry persists on each
  host until its next `nixos-rebuild switch`. Expected; not a repo concern.
