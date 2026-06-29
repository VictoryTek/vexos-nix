# Spec: pnpm insecure + networkmanager option rename

## Current State Analysis

Two build-blocking issues discovered when enabling the `gaming` feature:

### Issue 1 — pnpm insecure package (CRITICAL, build failure)
- **File:** `modules/development.nix:39`
- **Symptom:** `error: Refusing to evaluate package 'pnpm-10.29.2'` — flagged with CVE-2026-48995, CVE-2026-50014/15/16/17, CVE-2026-50573, CVE-2026-55699
- **Root cause:** `pkgs.pnpm` (stable nixpkgs) resolves to `pnpm-10.29.2` which nixpkgs has now marked insecure. The insecure block propagates through `environment.sessionVariables` at evaluation time.
- **Affected configs:** `configuration-desktop.nix` (which imports `development.nix` conditionally via `vexos.features.development`)

### Issue 2 — networkmanager.packages renamed (WARNING, becomes error in strict eval)
- **File:** `modules/gnome.nix:257`
- **Symptom:** `evaluation warning: The option 'networking.networkmanager.packages' has been renamed to 'networking.networkmanager.plugins'`
- **Root cause:** NixOS 26.05 renamed this option. The existing comment was written for NixOS 25.11 where `.plugins` had a D-Bus registration issue; that issue no longer applies.
- **Affected configs:** `configuration-desktop.nix`, `configuration-stateless.nix`, `configuration-server.nix`, `configuration-htpc.nix`

## Problem Definition

The gaming feature enable-flow fails to build on `vexos-desktop-vm` due to pnpm being insecure. The networkmanager option rename is a warning that should be resolved before it becomes an error in a future NixOS point release.

## Proposed Solution Architecture

### Fix 1 — Switch pnpm to unstable overlay
Replace `pkgs.pnpm` with `pkgs.unstable.pnpm` in `modules/development.nix`. The project already uses `pkgs.unstable` for other packages (the overlay is provided via `unstableOverlayModule` in `flake.nix`). The unstable channel tracks pnpm more aggressively and is expected to have a patched version.

### Fix 2 — Rename .packages to .plugins in gnome.nix
Change `networking.networkmanager.packages` to `networking.networkmanager.plugins`. Remove the outdated NixOS 25.11 comment about D-Bus registration; the rename is now correct on NixOS 26.05.

## Implementation Steps (Option B compliant)

Both fixes are edits to existing shared modules — no new files needed, no `lib.mkIf` guards required.

1. `modules/development.nix:39` — change `pkgs.pnpm` to `pkgs.unstable.pnpm`
2. `modules/gnome.nix:257` — change `.packages` to `.plugins`; update inline comment to remove outdated 25.11 caveat

## Dependencies

No new flake inputs. No Context7 lookup required (internal code changes only, no new external libraries).

## Configuration Changes

None beyond the two line edits above.

## Risks and Mitigations

- `pkgs.unstable.pnpm` version is unknown at spec time. Risk: if unstable also contains an insecure pnpm, the dry-build will fail → Phase 4 refinement would remove pnpm entirely (since `bun` covers the same use case).
- `.plugins` rename: low risk — this is a direct nixpkgs option rename with no behavior change.
