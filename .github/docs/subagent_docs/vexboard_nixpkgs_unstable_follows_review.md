# Review: vexboard_nixpkgs_unstable_follows (Phase 3 QA)

Date: 2026-06-22
Feature: vexboard_nixpkgs_unstable_follows
Spec: .github/docs/subagent_docs/vexboard_nixpkgs_unstable_follows_spec.md

## Scope

Reviewed:
- `flake.nix` (vexboard input change)
- `flake.lock` (lock graph after update)
- `nix flake show --impure` output
- `nix eval` dry-evaluation for 5 variants
- `bash scripts/preflight.sh` output

## Findings

### 1. Specification Compliance — PASS

- `vexboard` input converted from single-line `vexboard.url = ...` to attrset form with
  `inputs.nixpkgs.follows = "nixpkgs-unstable"` exactly as specified.
- Comment updated to document the pattern (analogous to `up` following `nixpkgs`) and
  preserve the warning against using `nixpkgs` (stable).

### 2. Lock graph — PASS

- `nixpkgs_3` node eliminated from `flake.lock`.
- `vexboard.inputs.nixpkgs` now resolves to `["nixpkgs-unstable"]` (outer flake input).
- rust-overlay and flake-utils_2 remain as independent nodes (correct — no outer follows
  available for these).

### 3. Build validation — PASS (5 variants)

All five core variants evaluated without error:

| Variant | Result |
|---------|--------|
| vexos-desktop-amd | `/nix/store/4n4qxlw3nbp636vsy6a9pay9rz22z3al-nixos-system-vexos-26.05.drv` |
| vexos-desktop-nvidia | `/nix/store/flyd8fxi8ppadwy34gk3xnisz66zbfgd-nixos-system-vexos-26.05.drv` |
| vexos-desktop-vm | `/nix/store/0b54pjhiyss1wa1mlhddv1h6sqklskgy-nixos-system-vexos-26.05.drv` |
| vexos-server-amd | `/nix/store/m7r6afdfiwda5n1mgvanf6gcgikchfzi-nixos-system-vexos-26.05.drv` |
| vexos-headless-server-amd | `/nix/store/s0y2jcp7kjr1rkacxkq53fi2a6yvbcaj-nixos-system-vexos-26.05.drv` |

### 4. Preflight — PASSED

`bash scripts/preflight.sh` exited with "Preflight PASSED — safe to push."

Warnings noted (all pre-existing, not introduced by this change):
- Check 6: nixpkgs-fmt formatting issues in existing files
- Check 7a: placeholder secret in `modules/server/vexboard.nix:74` (unchanged)
- Check 7e: gitleaks not installed

### 5. Additional checks — PASS

- `hardware-configuration.nix` not tracked in git (confirmed by preflight)
- `system.stateVersion` not modified
- New follows declaration uses `nixpkgs-unstable` (outer flake input) — correct
- No new `lib.mkIf` guards added
- Module Architecture Pattern unchanged

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
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Final Status

**PASS**
