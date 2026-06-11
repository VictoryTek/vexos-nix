# username_option — Specification

## Problem

`modules/users.nix:25` hardcodes the account creation as `users.users.nimda = { ... }`.
The `vexos.user.name` option exists and is read correctly by all consumer modules
(extraGroups, home-manager, gnome, network, syncthing, etc.), but the account itself
is always created as `nimda`. Setting the option to any other value produces a broken
system: the account `nimda` is created, but all group memberships and home-manager
target the non-existent named account.

## Code Fix

`modules/users.nix:25` — change hardcoded attrset key:
```nix
# BEFORE:
users.users.nimda = {

# AFTER:
users.users.${cfg.name} = {
```

## Comment Cleanup (10 files)

Stale "nimda" references in comments only — no logic changes:

| File | Line | Current | Updated |
|---|---|---|---|
| `modules/audio.nix` | 46 | `# Grant nimda raw ALSA access` | `# Grant the primary user raw ALSA access` |
| `modules/gaming.nix` | 102 | `# Grant nimda access to GameMode…` | `# Grant the primary user access to GameMode…` |
| `modules/server/jellyfin.nix` | 28 | `# Allow nimda to manage media directories` | `# Allow the primary user to manage media directories` |
| `modules/impermanence.nix` | 223 | `#   users.nimda.directories = [` | `#   users.${config.vexos.user.name}.directories = [` |
| `modules/impermanence.nix` | 227 | `#   users.nimda.files = [` | `#   users.${config.vexos.user.name}.files = [` |
| `home-desktop.nix` | 2 | no nimda reference | no change needed |
| `home-headless-server.nix` | 2 | `for user "nimda"` | `for the primary user` |
| `home-htpc.nix` | 2 | `for user "nimda"` | `for the primary user` |
| `home-server.nix` | 2 | `for user "nimda"` | `for the primary user` |
| `home-stateless.nix` | 2 | `for user "nimda"` | `for the primary user` |
| `home-vanilla.nix` | 2 | `for user "nimda"` | `for the primary user` |

## Out of Scope (future item)

Original intent was to auto-detect and adopt the existing NixOS username at install time.
This is feasible only on the migration path (running system) — not on a fresh ISO install.
Flagged as a future MASTER_PLAN item; not implemented here.

## Files Changed

- `modules/users.nix` (code fix)
- `modules/audio.nix` (comment)
- `modules/gaming.nix` (comment)
- `modules/server/jellyfin.nix` (comment)
- `modules/impermanence.nix` (comment × 2)
- `home-headless-server.nix` (comment)
- `home-htpc.nix` (comment)
- `home-server.nix` (comment)
- `home-stateless.nix` (comment)
- `home-vanilla.nix` (comment)
