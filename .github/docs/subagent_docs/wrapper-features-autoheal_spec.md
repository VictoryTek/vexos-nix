# Auto-heal stale thin wrapper (features.nix loading) — Spec

## Current State Analysis

`/etc/nixos/flake.nix` (the "thin wrapper") is written once, at install time, as a copy
of `template/etc-nixos-flake.nix` at whatever commit existed then. `just update` /
`just deploy` / the Up app (via `vexos-update`, `modules/nix.nix:128-296`) only run
`nix flake update --flake git+file:///etc/nixos`, which re-pins the `vexos-nix` flake
**input** (upstream modules/config content) — none of them touch the wrapper file's own
text.

Confirmed on a freshly-recreated VM (`vexos-desktop-vm`): its `/etc/nixos/flake.nix`
matches the current template's overall structure (`hostModule`, `mkVanillaVariant`,
`mkHeadlessServerVariant`, etc. all present) but is completely missing the "Optional
per-host feature toggles" block and every `hasFeatures`/`featuresFile` reference added
in commit `7fd75de`. `features.nix` itself was verified tracked, committed, and
containing the correct all-enabled content (via `git -C /etc/nixos show HEAD:features.nix`)
— so the previous fix (force-adding `features.nix` before `git+file://` builds) is
necessary but not sufficient: the wrapper never includes it in the module list at all on
this host, regardless of git state.

A manual escape hatch already exists: `justfile:887` (`fix-flake`), which detects an
old-style (`] ++ modules;`) or current-style (`lib.optional hasKernelOverride`) wrapper
and sed-patches in the `features.nix` load. Nothing calls it automatically — a user must
know it exists and run it themselves. `enable-feature`/`disable-feature` print a warning
suggesting it, but only after the user has already noticed something is wrong.

## Problem Definition

Because the wrapper is never resynced, this bug is permanent for every already-deployed
VexOS host, not a one-time transitional issue. It will keep recurring across "all vexos
devices" until each host's wrapper is patched — and template improvements will keep
silently failing to reach deployed machines in the future unless something makes that
propagation automatic.

## Proposed Solution

Move the exact patch logic already proven in `fix-flake` into `vexos-update` itself, so
every update run self-heals the wrapper before evaluating anything via `git+file://`.
Reuse, don't duplicate the underlying mechanism — same two sed patterns, run as root
(vexos-update already runs privileged, so no `sudo` prefix needed inside it, unlike the
standalone `just fix-flake` recipe used by an unprivileged shell).

Guard by variant: only applies to roles that actually wire in `featuresModule`
(desktop, htpc, server) — matching the existing `_require-desktop-role` guard's
exclusion list (`stateless`, `headless`, `vanilla`), since those roles never load
`features.nix` by design.

Fold the patched `flake.nix` into the existing force-add-and-commit step
(`modules/nix.nix:166-179`) by adding `flake.nix` to that loop's file list, so a patched
wrapper is committed the same way `features.nix` and the other host-local files already
are — consistent, already-proven mechanism, no new git logic.

## Implementation Steps

1. `modules/nix.nix`: insert an auto-heal block immediately before the existing
   "Repair repos initialised with old gitignore" force-add loop. It checks
   `$VARIANT` against the stateless/headless/vanilla exclusion, then checks whether
   `/etc/nixos/flake.nix` already loads `features.nix`; if not, applies the same
   old-style/current-style sed patches `fix-flake` uses (without `sudo`, since the
   script already runs as root).
2. `modules/nix.nix`: add `flake.nix` to the existing force-add loop's file list so any
   patch just applied gets staged and committed via the existing "commit any newly
   staged files" step immediately after.
3. No changes to `justfile`'s `fix-flake` recipe — it remains available as a manual
   tool; `vexos-update` duplicates its two sed patterns inline (a shell script baked
   into a Nix module cannot shell out to `just` cleanly) rather than being unified,
   since the calling contexts (privileged script vs. user-run recipe) differ in
   whether `sudo` is needed per-command.

## Dependencies

None — pure shell script edit inside an existing `writeShellScriptBin` string. No new
packages, libraries, or flake inputs.

## Configuration Changes

None to any `configuration-*.nix`, `system.stateVersion`, or flake inputs.

## Risks and Mitigations

- **Risk:** sed patch could apply to the wrong wrapper shape and corrupt `flake.nix`.
  **Mitigation:** reuses the exact, already-shipped `fix-flake` patterns unchanged — no
  new pattern-matching logic introduced. Both patterns are anchored to specific,
  distinctive strings (`] ++ modules;` / `lib.optional hasKernelOverride`) that only
  exist in exactly the two known wrapper generations.
- **Risk:** could misfire on stateless/headless/vanilla, wiring in a `features.nix`
  reference those roles' base modules don't declare an option for, breaking eval.
  **Mitigation:** explicit variant guard skips those roles entirely, matching the
  existing `_require-desktop-role` exclusion list used elsewhere in the justfile for
  exactly this role/feature applicability boundary.
- **Risk:** patched `flake.nix` invisible to the subsequent `git+file://` build.
  **Mitigation:** `flake.nix` is already tracked from the one-time initial `git add .`
  (it is not `.gitignore`d); adding it to the force-add loop stages the modification and
  the existing commit step commits it before `nix flake update`/dry-build/switch run —
  identical treatment to `features.nix` in the previous fix.
