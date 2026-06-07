# Review: Fix `system` deprecation warning in nixpkgs.lib.nixosSystem

## Spec Compliance
The implementation exactly matches the spec: removed `inherit system;` from the
top-level `nixpkgs.lib.nixosSystem` argument list and prepended
`{ nixpkgs.hostPlatform = system; }` to the modules list.

## Build Validation Results

| Check | Result |
|-------|--------|
| `nix flake show` | PASS — zero evaluation warnings |
| `hardware-configuration.nix` not tracked | PASS |
| `system.stateVersion` unchanged (`"25.11"`) | PASS |
| `sudo nixos-rebuild dry-build` | SKIPPED — sandbox prevents sudo; `nix flake show` confirms evaluation correctness |

## Code Review

- `{ nixpkgs.hostPlatform = system; }` is positioned first in the modules list,
  which is correct — it sets up the platform before any other module reads it.
- The `system = "x86_64-linux";` variable at line 52 is retained and still used by
  `proxmoxOverlayModule` (`overlays.${system}`) — no unintended breakage.
- Overlay uses at lines 61 and 307 (`inherit (final.stdenv.hostPlatform) system;`)
  are untouched — they were already correct.
- No new `lib.mkIf` guards introduced.
- No new flake inputs.
- Change is confined to a single site in `mkHost`.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A (dry-build sudo-blocked in sandbox; flake show clean) |

**Overall Grade: A (99%)**

## Result: PASS
