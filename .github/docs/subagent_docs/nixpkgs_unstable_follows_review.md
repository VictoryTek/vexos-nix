# Review: nixpkgs_unstable_follows (Phase 3 QA)

Date: 2026-05-18
Feature: nixpkgs_unstable_follows
Spec: .github/docs/subagent_docs/nixpkgs_unstable_follows_spec.md

## Scope
Reviewed:
- flake.nix
- scripts/preflight.sh
- .github/docs/subagent_docs/full_code_analysis.md
- command attempts from repo root

## Findings
1. Phase 2 no-op is spec compliant.
- Spec section 6 requires explicit no code change, no `nixpkgs-unstable.follows`, no nested follows, and no preflight edits.
- `flake.nix` still has `nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable"` and comment forbidding follows.
- `git diff -- flake.nix scripts/preflight.sh` returned no output.

2. Entry decision quality: justified and safe (with known cost).
- Keeping `nixpkgs-unstable` separate preserves intended behavior for `pkgs.unstable` consumers.
- Forcing follows would collapse unstable into stable and can change package availability and versions.
- `full_code_analysis.md` classifies this as intentional known cost and recommends no code change unless cost becomes material.
- Residual risk remains evaluation and closure overhead; this is documented and acceptable.

3. Correctness and security regression check.
- No code changes for this target were detected in reviewed files.
- No new correctness or security regression is introduced by the no-op decision.

## Build Validation Attempts
Commands attempted from repo root and outcomes:

1) `nix flake check`
- Result: BLOCKED
- Blocker: `nix` command unavailable (`CommandNotFoundException: nix`)

2) `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- Result: BLOCKED
- Blocker: `sudo` unavailable (`Sudo is disabled on this machine...`)

3) `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
- Result: BLOCKED
- Blocker: `sudo` unavailable (`Sudo is disabled on this machine...`)

Build Success is graded N/A for this review due host-environment limitations (Windows host without Nix and sudo).

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 96% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 90% | A- |
| Consistency | 100% | A |
| Build Success | N/A | N/A |

Overall Grade: A (98%) with Build Success N/A (environment blocked)

## Final Status

PASS

Rationale:
- Phase 2 no-op matches spec recommendation exactly.
- Keeping as-is is justified and safe for the intended stable and unstable split.
- No correctness or security regression is introduced.
- Build commands were attempted but could not run in this environment; blockers are documented above.
