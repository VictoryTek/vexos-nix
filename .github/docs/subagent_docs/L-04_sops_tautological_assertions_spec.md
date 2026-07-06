# L-04 — `secrets-sops.nix` assertions are tautologically true

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-04 (BUGS L4) · `modules/secrets-sops.nix:50-75`
(current file: lines 50-107)

## Current State

`modules/secrets-sops.nix`'s `config = lib.mkIf (cfg.backend == "sops") { ... }`
block declares 14 `assertions`:
- `cfg.sopsFile != null` — real check; `sopsFile` is a user-facing option
  (default `null`) that could legitimately be left unset.
- The other 13 all take the shape
  `config.sops.secrets ? "<name>"` / `"sops secret '<name>' must be declared..."`
  — but every one of those 13 names is unconditionally declared in the
  `sops.secrets = { ... }` attrset a few lines below, **in this exact same
  `config` block**. Since both the assertion and the declaration are
  merged from the same static, always-active module (gated only by the
  same `cfg.backend == "sops"` condition the assertions themselves are
  already inside), `config.sops.secrets` is guaranteed to contain all 13
  names by construction — these can never evaluate to `false`.

Confirmed no other module conditionally removes or overrides any of these
`sops.secrets.*`/`sops.templates.*` entries (grepped for `sops.secrets` and
`sops.templates` elsewhere in the repo — this file is the sole declaration
site), so there's no code path where the assertion could ever meaningfully
fire.

## Problem Definition

13 of 14 assertions are dead weight: they add ~55 lines that look like
real validation but can never fail, adding no protection and just noise
for anyone reading this file to understand what's actually enforced.

## Proposed Solution

Remove the 13 tautological assertions; keep only `cfg.sopsFile != null`,
matching the plan's own proposed fix exactly.

## Implementation Steps

1. `modules/secrets-sops.nix` — delete the 13 `config.sops.secrets ? "..."`
   assertion blocks; leave everything else (the `sops.secrets`/`sops.templates`
   declarations, the `vexos.server.*.mkForce` wiring) untouched.

## Configuration Changes

None — removing assertions that can never fire has zero effect on any
evaluated configuration's behavior.

## Risks and Mitigations

- **Risk:** this file wires actual secrets paths for 8+ services
  (Nextcloud, PhotoPrism, MinIO, Attic, VexBoard, kiji-proxy, Listmonk,
  Vaultwarden, Authelia) — a mistake here could silently break secret
  provisioning for a real deployment.
  **Mitigation:** the change only deletes assertion blocks; the
  `sops.secrets`/`sops.templates`/`mkForce` lines that actually wire
  secrets are not touched at all. Verified via `extendModules` with
  `vexos.secrets.backend = "sops"` and a real `sopsFile` that the sops
  config still evaluates identically (same secrets, same templates, same
  forced paths) before and after the removal.
