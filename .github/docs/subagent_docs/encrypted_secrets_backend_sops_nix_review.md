# Phase 3 Review: encrypted-secrets-backend-sops-nix

Spec: `.github/docs/subagent_docs/encrypted_secrets_backend_sops_nix_spec.md`
Review date: 2026-05-18
Reviewer: Phase 3 Review & QA subagent

## Verdict

**NEEDS_REFINEMENT**

A **CRITICAL** issue was found: the new module `modules/secrets-sops.nix` is present in the working tree but is currently untracked in git, which can break the feature in a clean checkout/CI even though local evaluation may appear to work.

## Findings (Ordered by Severity)

### CRITICAL

1. Untracked required module: `modules/secrets-sops.nix`
- Evidence:
  - `git status --short` reports `?? modules/secrets-sops.nix`
  - `git ls-files --eol ... modules/secrets-sops.nix ...` returned no entry for this file while returning tracked entries for the other modified files
- Impact:
  - `configuration-server.nix` and `configuration-headless-server.nix` import this module, so if it is omitted from commit history, the feature is incomplete and can fail in downstream builds.
- Required fix:
  - Add and commit `modules/secrets-sops.nix` with the rest of this feature.

### HIGH

No additional high-severity issues found.

### MEDIUM

1. Build validation commands could not be fully executed in this environment
- Native PowerShell blocker: `nix` not available in PATH.
- WSL blocker for direct `nix flake check`: flakes feature/purity mismatch unless additional flags are provided; pure eval fails on absolute `/etc/nixos/hardware-configuration.nix` import.
- WSL blocker for required dry-build commands: `sudo -n` failed with `sudo: a password is required`.
- Effect on review: Build Success scored as **N/A** (environment/tooling blocked).

### LOW

1. Operator docs command clarity
- `template/server-services.nix` uses `sops secrets/server/secrets.yaml`; explicit `sops edit secrets/server/secrets.yaml` may be clearer for operators.
- Not a functional blocker.

## Specification Compliance Review

### 1) Spec compliance, maintainability, consistency, security

Implemented and aligned with spec intent:
- `flake.nix` adds `sops-nix` input with `inputs.nixpkgs.follows = "nixpkgs"` and wires `sops-nix.nixosModules.sops` into server/headless pathways.
- `configuration-server.nix` and `configuration-headless-server.nix` import `modules/secrets-sops.nix`.
- `modules/secrets.nix` remains backend-agnostic plaintext compatibility hardening.
- New `modules/secrets-sops.nix` introduces:
  - `vexos.secrets.backend = "plaintext" | "sops"` defaulting to plaintext
  - `vexos.secrets.sopsFile`, age key options, and backend-gated assertions
  - `sops.secrets` declarations and `sops.templates` for env-file consumers
  - backend-driven `mkForce` wiring of service secret file paths
- Server modules (`nextcloud`, `minio`, `photoprism`, `attic`) now use explicit options for credential file paths with legacy plaintext defaults.
- `scripts/preflight.sh` adds plaintext regression guards and backend consistency checks.
- `template/server-services.nix` documents backend opt-in and required secret keys.

Open issue preventing pass:
- Required new module file is untracked (critical delivery/integration risk).

### 2) Context7 API currency validation (sops-nix)

Validated against Context7 library:
- Resolved ID: `/mic92/sops-nix`
- Reviewed current README patterns for:
  - Flake input + `nixosModules.sops` integration
  - `sops.defaultSopsFile`
  - `sops.age.keyFile`, `sops.age.generateKey`, `sops.age.sshKeyPaths`
  - `sops.secrets` declarations
  - `sops.templates` + `config.sops.placeholder.*` + template `.path` consumption

Result: Implementation uses current, supported patterns. No deprecated API usage identified.

### 3) Validation command results

Requested commands and outcomes:
- `nix flake check`
  - Blocked in native PowerShell (`nix` not found).
  - WSL retry reached Nix but failed due pure evaluation of `/etc/nixos/hardware-configuration.nix` import in this environment.
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
  - Blocked in WSL: `sudo: a password is required` under `sudo -n` (non-interactive sudo unavailable).
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
  - Same blocker.
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
  - Same blocker.

Build Success: **N/A (environment/tooling blocked)**.

### 4) Repository guard checks

- `hardware-configuration.nix` tracked check:
  - `git ls-files hardware-configuration.nix '**/hardware-configuration.nix'` produced no output.
  - Result: not tracked.
- `system.stateVersion` unchanged check:
  - No `system.stateVersion` diff detected in `configuration-server.nix` and `configuration-headless-server.nix`.
  - `configuration-desktop.nix` also showed no diff in the captured review command output.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 74% | C |
| Best Practices | 82% | B- |
| Functionality | 65% | D |
| Code Quality | 86% | B |
| Security | 84% | B |
| Performance | 95% | A |
| Consistency | 80% | B- |
| Build Success | N/A | N/A |

**Overall Grade: C+ (80%)**

## Required Refinement Actions

1. Add and commit `modules/secrets-sops.nix`.
2. Re-run required validation commands in an environment with:
   - Nix + flakes enabled
   - access to `/etc/nixos/hardware-configuration.nix` for this repo pattern
   - sudo capability for `nixos-rebuild dry-build` targets.
3. (Recommended) Update template command to explicit `sops edit ...` wording for operator clarity.

## Final Status

**NEEDS_REFINEMENT**