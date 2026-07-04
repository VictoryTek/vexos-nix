# M-26 — `vexos-update` embedded as a Nix string, no shellcheck

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-26 (ARCH 1.6) · `modules/nix.nix` (already read in full during
M-14), `pkgs/` (existing package convention, read `pkgs/default.nix` +
`pkgs/portbook/default.nix` for the pattern to match)

## Current State

`vexos-update` (~210 lines after the M-14 fixes) is built inline via
`pkgs.writeShellScriptBin "vexos-update" ''...''` directly inside
`modules/nix.nix` (a Nix daemon/binary-cache config module, not a package
definition) — no shellcheck runs on it at build time, and it's the wrong module for a
substantial shell application to live in.

Custom packages in this repo already follow an established convention:
`pkgs/<name>/default.nix`, wired into `pkgs/default.nix`'s overlay as
`pkgs.vexos.<name>`. No existing package uses `writeShellApplication` yet (this will
be the first), but the convention for where a new package lives and how it's
registered is well-established.

## Problem Definition

Move the script to a real package using `writeShellApplication` (which shellchecks the
script at build time — a build failure if shellcheck finds anything), and make that
shellcheck coverage reachable from a fast, standalone preflight step (not just
incidentally covered by a full system `nixos-rebuild dry-build`, which — per this
session's own experience — is frequently unavailable, e.g. no sudo in this sandbox).

## Proposed Solution

1. `pkgs/vexos-update/default.nix` (new) — `writeShellApplication { name =
   "vexos-update"; text = ''<exact same script body>''; }`. No `runtimeInputs` needed:
   the script already relied purely on ambient system PATH (git, nix, nixos-rebuild,
   coreutils) before this change, and `writeShellApplication`'s wrapper *prepends* to
   PATH rather than replacing it, so this is behaviorally identical.
2. `pkgs/default.nix` — register it as `pkgs.vexos.vexos-update`.
3. `modules/nix.nix` — replace the inline `pkgs.writeShellScriptBin "vexos-update"
   ''...''` in `environment.systemPackages` with `pkgs.vexos.vexos-update`.
4. `scripts/preflight.sh` — add a fast, standalone check that builds
   `nixosConfigurations.vexos-desktop-amd.pkgs.vexos.vexos-update` directly (verified
   this attribute path is reachable via `nix build --impure` without any new flake
   output) — this forces the shellcheck to actually run, independent of whether the
   broader per-variant dry-build steps run at all.

## Implementation Steps

1. Create `pkgs/vexos-update/default.nix` with the exact script body moved verbatim
   (no logic changes — this is a pure relocation, not a rewrite).
2. Register in `pkgs/default.nix`.
3. Update `modules/nix.nix` to reference the new package.
4. Add the preflight check.

## Configuration Changes

None to `flake.nix` — the existing `nixosConfigurations.<x>.pkgs.vexos.*` attribute
path is reachable directly; no new `packages.<system>.*` output needed.

## Risks and Mitigations

- **Script content must move verbatim** — any accidental edit during the move risks
  silently changing update behavior; will diff old vs. new script text after the move
  to confirm byte-for-byte equivalence (aside from the wrapper boilerplate
  `writeShellApplication` itself adds, which is standard and expected).
- **Shellcheck may surface real findings** in a 210-line script that's never been
  linted before — if so, these will be fixed as part of this same change (the whole
  point of moving it), not deferred.
