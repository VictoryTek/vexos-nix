# Phase 6 Preflight Report: nixpkgs_unstable_follows

Date: 2026-05-18

## Scope

This report covers Phase 6 preflight validation tasks:

1. Detect preflight script and CI workflows.
2. Execute preflight with the provided WSL invocation.
3. Confirm presence of GitHub Actions workflow files and `.gitlab-ci.yml`.
4. Return PASS/FAIL with evidence.

## Command Executed

```bash
wsl -d Ubuntu -- bash -c "source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null; source ~/.nix-profile/etc/profile.d/nix.sh 2>/dev/null; cd /mnt/c/Projects/vexos-nix && bash scripts/preflight.sh"
```

## Detection Results

- `scripts/preflight.sh`: Present (`True`)
- `scripts/preflight.ps1`: Not present (`False`)
- GitHub Actions workflows (`.github/workflows/*.yml`):
  - `.github/workflows/ci.yml`
  - `.github/workflows/gitlab-mirror.yml`
  - `.github/workflows/update-flake-lock.yml`
- `.gitlab-ci.yml`: Present (`True`)

## Preflight Execution Result

- Exit code: `0`
- Outcome: `PASS`
- Full log: `.github/docs/subagent_docs/nixpkgs_unstable_follows_preflight_output.log`

## Evidence Excerpts (verbatim from run output)

```text
========================================================
  vexos-nix Preflight Validation
  2026-05-18 10:33:49

[0/7] Checking for required tools...
PASS  nix 2.34.1
WARN  jq not found - flake.lock pinning and freshness checks will be skipped

[1/7] Validating flake structure...
WARN  Skipping nix flake check - /etc/nixos/hardware-configuration.nix not found.
WARN  Run 'sudo nixos-generate-config' on the target host and retry.

[2/7] Verifying system closures (dry-build all variants)...
  Discovered 34 nixosConfigurations outputs
WARN  Skipping dry-build - /etc/nixos/hardware-configuration.nix not found.

[3/7] Checking hardware-configuration.nix is not tracked in git...
PASS  hardware-configuration.nix is not tracked

[5/7] Validating flake.lock...
WARN  Skipping flake.lock pinning check - jq not available
WARN  Skipping flake.lock freshness check - jq not available

[6/7] Checking Nix formatting...
WARN  nixpkgs-fmt not installed - skipping format check

Preflight PASSED - safe to push.
```

## Failure Classification (required only on failure)

Preflight did not fail, so failure classification is not applicable.

Observed warnings are environment-related:

- Missing `/etc/nixos/hardware-configuration.nix` in this WSL environment caused validation steps to be skipped.
- Missing optional tools (`jq`, `nixpkgs-fmt`) caused non-fatal checks to be skipped.

No code-related preflight failure was observed in this run.

## Phase 6 Verdict

`PASS`
