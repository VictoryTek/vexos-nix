# features.nix Untracked File — Spec

## Current State Analysis

`/etc/nixos/features.nix` is the per-host feature-toggle file, created and rewritten by
`just enable-feature <feature>` / `just disable-feature <feature>` (per its own header
comment). It is read by the upstream `vexos-nix` flake via an absolute-path,
`--impure`-gated check:

```nix
featuresModule =
  let path = /etc/nixos/features.nix;
  in if builtins.pathExists path then [ path ] else [];
```

(`flake.nix:103-105`), consumed by both `mkHost` (`nixosConfigurations.*`) and
`mkBaseModule` (`nixosModules.*Base`, used by `template/etc-nixos-flake.nix` thin
wrappers).

`/etc/nixos` is itself a local git repository (initialized by `vexos-update` on first
run, or by `scripts/install.sh` at install time) specifically so that
`nixos-rebuild switch --flake git+file:///etc/nixos#...` can be used without leaking
`secrets/` into the world-readable Nix store — `git+file://` only copies **git-tracked**
content into the evaluated flake source; untracked files are invisible to it, whether or
not `.gitignore` mentions them.

`/etc/nixos/features.nix` is **not** `.gitignore`d, but it is also **never explicitly
`git add`ed** anywhere in the codebase after its creation by the `just enable-feature`
recipe. It only becomes tracked if it happens to exist at the moment of the one-time
`git init; git add .; git commit` migration in `vexos-update`
(`modules/nix.nix:141-155`) — i.e. only if a feature was enabled *before* the very first
update/deploy ever ran on that host. Any feature enabled/disabled afterward produces an
untracked (or, after a content change, modified-but-uncommitted) `features.nix`.

## Problem Definition

Two existing repair loops already force-add specific host-local files before any
`git+file://` evaluation, precisely because untracked files are invisible to that
scheme:

- `modules/nix.nix:166` (inside `vexos-update`, used by `just update` and the Up GUI
  app):
  ```bash
  for _f in hardware-configuration.nix kernel-install-override.nix stateless-user-override.nix server-services.nix; do
  ```
- `scripts/install.sh:395` (installer, run once per host bootstrap /
  re-run-of-installer):
  ```bash
  for f in flake.nix hardware-configuration.nix stateless-user-override.nix; do
  ```

Neither list includes `features.nix`. Consequently:

1. A user runs `just enable-feature gaming` (writes/updates `/etc/nixos/features.nix`,
   untracked or modified-but-uncommitted).
2. `just rebuild` (`path:/etc/nixos#...`, no git filtering) picks it up correctly —
   packages install, appear to work, persist across reboots (no re-evaluation happens on
   reboot).
3. `just update` (→ `vexos-update`) or `just deploy` → any subsequent
   `git+file:///etc/nixos` evaluation silently excludes the untracked/uncommitted
   `features.nix`. All `vexos.features.*.enable` options revert to their default
   (`false`). Every feature-gated package (Steam, MangoHud, Docker, libvirtd, etc.)
   disappears from the rebuilt closure in one shot.
4. Flatpak apps declared via `vexos.flatpak.managedApps` (set unconditionally by
   `modules/gaming.nix`, independent of `cfg.enable`) are separately reconciled by
   `modules/flatpak.nix`'s stamp-hash service and may or may not be removed depending on
   exact hash-transition timing — a secondary, cosmetic side effect of the same root
   cause, not a separate bug.

Confirmed via `nix store diff-closures` between a "broken" and a "working" generation on
the affected host: gaming + development + virtualization packages vanish **together**,
consistent with the entire `features.nix` file dropping out of evaluation, not a
per-feature issue.

## Proposed Solution

Add `features.nix` to both existing force-add loops, exactly matching the established
pattern (no new mechanism, no new file, no abstraction):

1. `modules/nix.nix:166` — add `features.nix` to the `for _f in ...` list.
2. `scripts/install.sh:395` — add `features.nix` to the `for f in ...` list.

This ensures that whenever `/etc/nixos/features.nix` exists, it is force-added (and, in
`vexos-update`'s case, committed via the existing "commit any newly staged files" step
immediately after the loop at `modules/nix.nix:174-179`) before any `git+file://`
evaluation — identical treatment to `server-services.nix`, which has the exact same
"created after initial git-tracking, must survive `git+file://` builds" lifecycle.

No option, module, or architecture changes. No new `lib.mkIf` guards. Two one-line
additions to existing loops.

## Implementation Steps

1. `modules/nix.nix:166`: add `features.nix` to the existing space-separated file list.
2. `scripts/install.sh:395`: add `features.nix` to the existing space-separated file
   list.
3. No other files require changes — `configuration-desktop.nix`,
   `modules/gaming.nix`/`development.nix`/`3d-print.nix`/`virtualization.nix`,
   `modules/flatpak.nix`, and `flake.nix`'s `featuresModule` are all already correct;
   the bug is purely in what gets staged before `git+file://` reads the tree.

## Dependencies

None — pure shell script edit inside existing Nix module strings. No new packages,
libraries, or flake inputs. Context7 not applicable (no external library/API
involved).

## Configuration Changes

None to any `configuration-*.nix`, `system.stateVersion`, or flake inputs.

## Risks and Mitigations

- **Risk:** force-adding `features.nix` unconditionally when it doesn't exist would
  error. **Mitigation:** both loops already guard with
  `if [ -f "/etc/nixos/$_f" ]; then ... fi` — adding the filename to the list is safe by
  construction; a host with no `features.nix` simply skips it, matching current
  behaviour for `server-services.nix`.
- **Risk:** none to `hardware-configuration.nix`/`system.stateVersion` — untouched.
- **Risk:** this does not fix the transient case where a user runs `just enable-feature`
  and then immediately runs `just update`/`just deploy` in the same breath without an
  intervening `just rebuild` — the fix stages/commits the file as part of
  `vexos-update`'s existing pre-build step, which already runs before the `git+file://`
  dry-build/switch in that same script, so this is in fact covered. `scripts/install.sh`
  runs its force-add loop before its own `git+file://` dry-build/switch too, so the
  ordering is consistent with the existing pattern.
