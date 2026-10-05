# Daily flake update: add vexportal — Spec

## Current state
`.github/workflows/update-flake-lock-daily.yml` runs
`nix flake update nixpkgs up vexboard`. `vexportal` is in neither the daily
nor the weekly workflow, so `flake.lock` pins VexPortal at 83e44796 (2026-08-24)
while upstream HEAD is dfebb37f. Hosts build the pinned rev, so they never
see new VexPortal commits.

## Problem
VexPortal is a first-party app (same class as `up` and `vexboard`; see
`pkgs/vexos-update/default.nix` and `pkgs/vexos-deploy/default.nix`, which
already treat all three identically) but is missing from the daily update.

## Solution
In the daily workflow only:
- header comment: `(nixpkgs 26.05, up, vexboard, vexportal)`
- step name: `Update nixpkgs stable, up, vexboard, and vexportal`
- command: `nix flake update nixpkgs up vexboard vexportal`

No Nix module changes, so Option B module architecture is unaffected.

## Dependencies
None new. `vexportal` is an existing root input in `flake.nix`.

## Risks
- Input name typo makes `nix flake update` fail: mitigated by matching the
  `flake.nix` input name `vexportal` and validating with `nix flake show`.
- A broken upstream VexPortal commit lands in the lock daily: same exposure
  as `up`/`vexboard`; accepted.
