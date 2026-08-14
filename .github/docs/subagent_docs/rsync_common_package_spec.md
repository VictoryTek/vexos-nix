# rsync in Common Packages — Spec

## Current State Analysis
`modules/packages-common.nix` is the universal-base package list (Option B
pattern) imported by `configuration-desktop.nix`, `configuration-server.nix`,
`configuration-headless-server.nix`, `configuration-htpc.nix`, and
`configuration-stateless.nix`. It is NOT imported by `configuration-vanilla.nix`,
which is deliberately a stock/minimal role ("vanilla stays stock until
[explicitly opted into]" per its header comment) — confirmed with user, who
chose to leave vanilla out of scope for this change.
`rsync` does not currently appear anywhere in the repo's `.nix` files.

## Problem Definition
Add `rsync` as a CLI tool available on all roles that already receive the
common package set.

## Proposed Solution
Add `rsync` to the `environment.systemPackages` list in
`modules/packages-common.nix`, alongside the other general-purpose CLI tools
(`git`, `curl`, `wget`).

## Implementation Steps (Module Architecture Pattern — Option B)
Single-line addition to the existing universal base file's package list — no
new module, no `lib.mkIf` guard, no role-specific file needed. This is exactly
the kind of change `packages-common.nix` exists for.

1. Edit `modules/packages-common.nix`: add `rsync` to `environment.systemPackages`.

## Dependencies
`pkgs.rsync` — standard nixpkgs package, no new flake input.

## Configuration Changes
None (no new options).

## Risks and Mitigations
None of note — additive, common CLI tool, no conflicts with existing packages.

## Verification Plan
1. `nix flake show --impure`
2. `nix eval --impure` toplevel drvPath for one representative role from each
   of the five affected roles (or dry-build where sudo is available)
3. `git ls-files hardware-configuration.nix` — must stay empty
4. Confirm no `stateVersion` changes
