# Harmonia Public Key — Spec

## Current state analysis
- `modules/nix.nix` defines `vexos.harmonia.publicKey` with `default = ""` (lines 86-100).
- Its own doc comment (lines 95-98) instructs: "Left empty by default: fill this in
  once, here, after running `just harmonia-info` on the cache host for the first time.
  It is not a secret and is safe to commit."
- `just harmonia-info` was run on the cache host (vexos-vmc) and returned a working,
  verified key:
  ```
  vexos.harmonia.cacheUrl  = "http://vexos-vmc:5000";
  vexos.harmonia.publicKey = "vexos-vmc-1:Nm4amMYYdvIlY7EZUHbDVI0GTY8orUpWRM89UpX1Vjs=";
  ```
- `vexos.harmonia.cacheUrl` already defaults to `"http://cache:5000"` (Tailscale
  MagicDNS name), so only `publicKey` needs to change here — the URL is intentionally
  left as the stable `cache` alias, not the concrete `vexos-vmc` hostname.

## Problem definition
With `publicKey` empty, `modules/nix.nix`'s `warnings` block (lines 120-127) fires on
every host build, and the Harmonia substituter is never added to `nix.settings.substituters`
(lines 144-149) — every host compiles locally instead of pulling from the cache.

## Proposed solution
Set the `default` value of `options.vexos.harmonia.publicKey` in `modules/nix.nix` to
the verified key string. No option type, structure, or other logic changes.

## Implementation steps
1. `modules/nix.nix`: change `default = "";` → `default = "vexos-vmc-1:Nm4amMYYdvIlY7EZUHbDVI0GTY8orUpWRM89UpX1Vjs=";`
   under `options.vexos.harmonia.publicKey`.
   - This is a universal base module (no role gating) — consistent with Module
     Architecture Pattern Option B; no `lib.mkIf` needed.

## Dependencies
None — no new inputs, packages, or libraries.

## Configuration changes
- `vexos.harmonia.publicKey` default changes from `""` to the verified key. Any host
  that already set an explicit override keeps its own value (NixOS option precedence).
- `system.stateVersion` unaffected.

## Risks and mitigations
- Risk: key is wrong/stale → substituter would fail signature verification, not a
  silent security hole (unsigned/mis-signed paths are simply not fetched).
  Mitigation: value was copied verbatim from a successful `just harmonia-info` run
  against the live cache host.
- Risk: none to build determinism — purely a default value used only when caches are
  reachable at build/rebuild time.
