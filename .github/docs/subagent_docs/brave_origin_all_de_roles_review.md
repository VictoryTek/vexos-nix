# Brave Origin as Default Browser & Dock Favorite on All DE Roles — Review

## Specification Compliance

All four implementation steps from `brave_origin_all_de_roles_spec.md` were
carried out exactly as specified:

1. `modules/gnome-server.nix:20`, `modules/gnome-htpc.nix:20`,
   `modules/gnome-stateless.nix:20` — `favorite-apps` first entry changed
   from `"brave-browser.desktop"` to `"brave-origin.desktop"`, same list
   position as before and matching `modules/gnome-desktop.nix:25`.
2. `home/gnome-common-desktop.nix` deleted; content moved verbatim (only the
   header comment updated) to new `home/gnome-common-browser.nix`.
3. `home-desktop.nix` import updated to the new filename.
4. `home-server.nix`, `home-htpc.nix`, `home-stateless.nix` — added
   `./home/gnome-common-browser.nix` import plus the
   `vexos-migrate-dock-brave-origin` one-shot systemd user service, copied
   verbatim from `home-desktop.nix`.

## Consistency — Module Architecture Pattern (Option B)

- No new `lib.mkIf` role/display/gaming guards introduced in any shared
  module. `modules/gnome-server.nix`, `-htpc.nix`, `-stateless.nix` remain
  role-specific addition files with only a literal value changed.
- `home/gnome-common-browser.nix` follows the existing precedent of
  `home/gnome-common.nix`: a shared addition file imported by the DE roles
  that need it (desktop, server, htpc, stateless), and deliberately not
  imported by `home-vanilla.nix` / `home-headless-server.nix`.

## Completeness

- Confirmed via grep: no remaining `favorite-apps` entries pin
  `brave-browser.desktop` anywhere in `*.nix`. The only surviving
  `brave-browser.desktop` string occurrences are the migration-comment prose
  in the four `home-*.nix` files (intentional — describes what the one-shot
  service repairs).
- Confirmed via grep: no other file references the deleted
  `home/gnome-common-desktop.nix` filename except historical spec/review
  docs under `.github/docs/subagent_docs/`, which are not live config.
- Confirmed roles correctly excluded: `home-vanilla.nix` and
  `home-headless-server.nix` import only `./home/bash-common.nix` — untouched.
  `configuration-vanilla.nix` does not import `modules/packages-desktop.nix`,
  so `brave-origin.desktop` is not installed there — pinning it in the dock
  would have broken the app icon.

## Security / Performance

No new packages, no secrets, no privilege changes. No performance impact —
same dconf keys and a stamp-guarded oneshot service already proven on the
desktop role.

## Build Validation — LIMITATION (documented per project rules, not asserted)

This session's shell is a Windows/Git-Bash environment with no `nix` binary
on `PATH` (verified: `nix flake show --impure` → `nix: command not found`,
`uname -a` → `MINGW64_NT`). The mandated build-validation commands
(`nix flake show --impure`, `sudo nixos-rebuild dry-build --flake
.#vexos-{desktop,server,htpc,stateless}-amd`) require a NixOS host and could
not be executed from here. Per the project's "verify before asserting" rule,
this is reported as a gap rather than assumed to pass.

What *was* verified locally, as a substitute static check:
- Brace-balance count on every edited file (all matched: home-desktop.nix
  33/33, home-server.nix 24/24, home-htpc.nix 21/21, home-stateless.nix
  29/29, gnome-server.nix 11/11, gnome-htpc.nix 11/11, gnome-stateless.nix
  13/13, gnome-common-browser.nix 4/4).
- No dangling references to the removed filename in any `.nix` file.
- `git ls-files hardware-configuration.nix` — not applicable check, no
  hardware file touched.
- `system.stateVersion` — not touched in any `configuration-*.nix`.
- No new flake inputs added — `follows` check not applicable.

**PASS / NEEDS_REFINEMENT: NEEDS_REFINEMENT** (blocked solely on the build
step, not on any code defect found). The user must run, on a NixOS host with
this branch checked out:

```
nix flake show --impure
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd
sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd
```

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | N/A — unverified (no build environment) | — |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 0% (not executable in this environment) | Blocked |

**Overall Grade: Blocked on Build Validation — all reviewable criteria pass;
`sudo nixos-rebuild dry-build` must be run on the actual NixOS host before
this can be marked APPROVED / preflight can run.**
