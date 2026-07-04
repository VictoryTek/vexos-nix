# H-12b — Auto-detect existing NixOS username on the migration path

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN (H-12 design intent) · `scripts/migrate-to-stateless.sh` (read in full)

## Current State

`scripts/migrate-to-stateless.sh` hardcodes `nimda` in three places, even though
`vexos.user.name` (fixed by H-12, `modules/users.nix`) already correctly parametrizes
every consumer module:

- `getent shadow nimda` — reads the shadow hash of the literal account "nimda", not
  whatever account the user actually logs in as.
- `users.users.nimda.hashedPassword = lib.mkOverride 50 "..."` written into
  `/etc/nixos/stateless-user-override.nix` — hardcoded target user.
- The final "Login credentials after reboot: Username: nimda" printout.

If the user's existing NixOS install uses a different account name (renamed during
their original install, or never named "nimda" to begin with), this script silently
preserves the password hash of a nonexistent/wrong account, and the printed
instructions are simply incorrect.

`scripts/install.sh` was checked (`grep` for `useradd`/`nimda`/user-creation logic —
no matches) and confirmed to do no user-account handling at all; the account is created
declaratively by `modules/users.nix` on first activation. There is no prior account to
detect on a fresh ISO install, so per the user's decision, the install.sh side of H-12b
("optional installer prompt") is out of scope for this pass — only the migration script,
which does have a real prior account to detect, is being fixed.

## Problem Definition

The migration script should adopt whatever account is actually UID 1000 on the system
being migrated, rather than assuming "nimda".

## Proposed Solution

1. Detect the real primary user early in the script (right where the disk-layout
   detection already happens): `DETECTED_USER=$(getent passwd 1000 | cut -d: -f1)`,
   falling back to `nimda` if that lookup returns nothing (matches the existing default
   and keeps the script working unchanged on a genuinely-nimda system).
2. Replace all three hardcoded `nimda` references with `$DETECTED_USER`.
3. When `$DETECTED_USER` differs from the default `"nimda"`, add a
   `vexos.user.name = "$DETECTED_USER";` line to the same
   `/etc/nixos/stateless-user-override.nix` file the script already writes (no new file
   — this file is already persisted to `@persist/etc/nixos/` and already imported via
   `statelessUserOverrideModule`/`roles.stateless.hostLocalModules`, the very same
   mechanism H-19 just formalized). When it matches the default, don't add the line —
   no need to write a no-op override.

## Implementation Steps

1. `scripts/migrate-to-stateless.sh`:
   - Add `DETECTED_USER` detection near the top (after root/live-ISO checks, before the
     disk-layout section — a natural early "who are we migrating" step).
   - `getent shadow nimda` → `getent shadow "$DETECTED_USER"`.
   - The `stateless-user-override.nix` heredoc: change `users.users.nimda.hashedPassword`
     to `users.users.${DETECTED_USER}.hashedPassword`, and conditionally prepend
     `vexos.user.name = "$DETECTED_USER";` when it differs from `"nimda"`.
   - Final printout: `Username: ${DETECTED_USER}` instead of the literal `nimda`.

## Configuration Changes

None to `flake.nix`/modules — `vexos.user.name` already exists and is already consumed
correctly everywhere (H-12). This is purely a shell-script fix.

## Risks and Mitigations

- **UID 1000 lookup failing** (e.g. a system where the primary user isn't UID 1000) —
  falls back to `"nimda"`, identical to today's hardcoded behavior; no regression.
- **`stateless-user-override.nix` is a heredoc, not a Nix-templated file** — need to be
  careful that `$DETECTED_USER` interpolates correctly as a bare (unquoted) Nix
  identifier only when it's a valid one; NixOS usernames are POSIX usernames
  (`[a-z_][a-z0-9_-]*`), which are also always valid bare Nix attribute names, so
  `users.users.${DETECTED_USER}.hashedPassword` is safe without extra quoting.
