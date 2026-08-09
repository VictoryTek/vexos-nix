# Specification — Expose `scripts/` under `/etc/nixos/scripts` on all roles

## Current State Analysis

`modules/packages-common.nix` (universal base, imported by every role) exposes the
justfile on deployed hosts via:

```nix
environment.etc."nixos/justfile".source = ../justfile;
```

Because `../justfile` is a path literal pointing at a single file, Nix copies that file
into its own standalone store object (`/nix/store/<hash>-justfile`) rather than
preserving it as a subpath of the full `vexos-nix` flake source tree. Confirmed on a live
deployed host (`vexos-desktop-nvidia`):

```
$ readlink -f /etc/nixos/justfile
/nix/store/fmm0qwmbnixdlscfmil7l32ial5r6x7h-justfile
$ dirname $(readlink -f /etc/nixos/justfile)
/nix/store          # NOT a copy of the flake source tree — no scripts/ sibling
```

Several justfile recipes (`create-zfs-pool` at justfile:1240, and the shared
`_run-storage-script` helper at justfile:1293, used by `create-mergerfs-pool` and
`attach-remote-storage`) resolve helper scripts under `scripts/` via a fallback chain:

1. Walk up from `$PWD` looking for `scripts/<name>` — fails on a deployed host (no
   working checkout).
2. `$_jf_raw/scripts` (`{{justfile_directory()}}` = `/etc/nixos` under the
   `bash-common.nix` alias) → `/etc/nixos/scripts` — fails, only the single `justfile`
   file is etc'd today.
3. `$_jf_dir/scripts` (`dirname(readlink -f {{justfile()}})`) → resolves to
   `/nix/store/scripts` per the bug above — always fails.
4. Static `/etc/nixos/scripts` and `$HOME/Projects/vexos-nix/scripts` — the former is
   identical to failing candidate #2; the latter only exists on this dev checkout, never
   on a real deployed host.
5. Last-resort `nix eval` against the locked `vexos-nix` flake input's `outPath` (via
   `/etc/nixos/flake.nix`) — the only candidate that reaches the real, complete source
   tree, but is unreliable in the field (observed to fail on a freshly installed
   `vexos-server-*` host — exact eval failure unconfirmed without shell access to that
   machine, but it silently swallows its error into `_vexos_store` being empty).

Net effect: on real deployed hosts, `just create-zfs-pool` (and its siblings) reliably
fail with `error: scripts/create-zfs-pool.sh not found in any known location.`

## Problem Definition

None of the fallback paths that a deployed host can realistically hit today resolve to a
directory that actually contains `scripts/`. The justfile itself already anticipates and
checks `/etc/nixos/scripts` as a fallback location (candidate #2/#4 above) — that
location is simply never populated.

## Proposed Solution

Mirror the existing justfile-exposure pattern for the whole `scripts/` directory:

```nix
environment.etc."nixos/scripts".source = ../scripts;
```

added to `modules/packages-common.nix`, immediately after the existing
`environment.etc."nixos/justfile"` line. Unlike a single-file path, a directory path
literal copies the entire directory (preserving all files within, including
`create-zfs-pool.sh`, `create-mergerfs-pool.sh`, and any future scripts under
`scripts/`) into the Nix store as one object, and NixOS's `environment.etc` symlinks
`/etc/nixos/scripts` to it. This makes candidate #2/#4 in the existing fallback chain
(`/etc/nixos/scripts`) succeed unconditionally on every deployed host, with no changes
needed to the justfile's resolution logic itself.

This is a minimal, additive change: one new line in one universal base module. It does
not touch the Module Architecture Pattern (no new `lib.mkIf`, no role gating — the line
applies unconditionally to all roles that import `packages-common.nix`, same as the
existing justfile line already does).

## Implementation Steps

1. Add `environment.etc."nixos/scripts".source = ../scripts;` to
   `modules/packages-common.nix`, directly below the existing justfile etc line.
2. No other files require changes — the justfile's existing fallback chain already
   checks `/etc/nixos/scripts` as a candidate location.

## Dependencies

None. No new packages, flake inputs, or external libraries. Context7 lookup not
applicable (pure internal NixOS module change).

## Configuration Changes

`modules/packages-common.nix` gains one `environment.etc` entry. No option surface
changes, no `configuration-*.nix` changes, no `stateVersion` changes.

## Risks and Mitigations

- **Risk:** Copying `scripts/` into the Nix store on every rebuild slightly increases
  closure size / etc-activation churn.
  **Mitigation:** `scripts/` is a small directory of shell scripts (KB-scale); negligible
  compared to the rest of the system closure. Matches the precedent already set by
  etc-exposing `justfile` and `template/*.nix`.
- **Risk:** Existing hosts won't see the fix until they rebuild.
  **Mitigation:** Expected and communicated to the user — they must run
  `just update && sudo nixos-rebuild switch --flake /etc/nixos#<variant>` (or the
  vexos-updater app) on the affected server after this change ships, as this is a
  live-system operation the user must run themselves.
- **Risk:** Does not address why the `nix eval` last-resort fallback also failed in the
  field.
  **Mitigation:** Out of scope — that fallback becomes dead-path once `/etc/nixos/scripts`
  reliably resolves via the etc file; no need to root-cause a redundant safety net that
  is no longer load-bearing for the primary failure mode.
