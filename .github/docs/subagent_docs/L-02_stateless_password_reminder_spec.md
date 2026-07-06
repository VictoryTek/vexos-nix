# L-02 — justfile stateless password reminder is wrong

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-02 (BUGS L2) · `justfile:22-30`

## Current State

`justfile`'s `default` recipe prints, on the stateless role:
```
Login password resets to 'vexos' on every reboot (by design).
To change permanently, update initialPassword in
configuration-stateless.nix and rebuild.
```

Checked the actual mechanism directly:
- `configuration-stateless.nix:43` — `users.users.${config.vexos.user.name}.hashedPassword = lib.mkDefault "!";`
  — the account starts **locked (no password)**, not defaulted to `"vexos"`.
  There is no `initialPassword` option anywhere in this file.
- `configuration-stateless.nix:119-131` — a `warnings` block (not the
  justfile) already correctly documents the real remediation: run
  `scripts/stateless-setup.sh`, or manually write
  `/etc/nixos/stateless-user-override.nix` with a hash from
  `mkpasswd -m sha-512`.
- `scripts/stateless-setup.sh:364-371` — confirms exactly this: it writes
  `/mnt/etc/nixos/stateless-user-override.nix` containing
  `users.users.nimda.hashedPassword = lib.mkOverride 50 "${HASHED_PW}";`.
  This file lives in `/etc/nixos` (persisted, not on the wiped tmpfs root),
  so once set, the password **persists across reboots** — it does not
  "reset to 'vexos'" on each boot as the justfile claims.

## Problem Definition

The justfile's stateless-role reminder is wrong on three counts: the wrong
default (locked, not `"vexos"`), the wrong behavior claim (persists once
set, doesn't reset each reboot), and the wrong fix location
(`initialPassword` in `configuration-stateless.nix` doesn't exist — the real
mechanism is `hashedPassword` in `stateless-user-override.nix`).

## Proposed Solution

Rewrite the reminder text to match `configuration-stateless.nix`'s own
already-correct `warnings` block and `stateless-setup.sh`'s actual behavior:
locked by default, set via `stateless-setup.sh` (or manually via
`stateless-user-override.nix` + `mkpasswd -m sha-512`), persists once set.

## Implementation Steps

1. `justfile` — rewrite lines 26-27 (the stateless reminder echo lines).

## Configuration Changes

None — text-only change to a `just` recipe's printed output; no NixOS
module or option changes.

## Risks and Mitigations

- **None** — output-text-only change in a private `[private]` default
  recipe; no build-affecting code touched. Verified with `just --list` /
  a dry invocation that the recipe still parses and runs correctly.
