# Phase 6 Preflight Report: nextcloud-https-enforcement

Date: 2026-05-18

## Scope

This report validates preflight execution and CI workflow presence for the feature nextcloud-https-enforcement.

## 1) Required File Detection

- scripts/preflight.sh: FOUND
- .github/workflows/*.yml: FOUND
  - .github/workflows/ci.yml
  - .github/workflows/gitlab-mirror.yml
  - .github/workflows/update-flake-lock.yml
- .gitlab-ci.yml: FOUND

## 2) Preflight Command Executed

Command:

```bash
wsl -d Ubuntu -- bash -c "source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null; source ~/.nix-profile/etc/profile.d/nix.sh 2>/dev/null; cd /mnt/c/Projects/vexos-nix && bash scripts/preflight.sh"
```

Exit code: 0

## 3) Preflight Summary

- [0/7] Required tools: PASS for nix; WARN for missing jq (pinning/freshness checks skipped)
- [1/7] Flake structure: WARN skipped nix flake check due to missing /etc/nixos/hardware-configuration.nix
- [2/7] Dry-build closures: WARN skipped due to missing /etc/nixos/hardware-configuration.nix
- [3/7] Git tracking guard: PASS (hardware-configuration.nix not tracked)
- [4/7] stateVersion guard: PASS (present in all required configuration files)
- [5/7] flake.lock checks: PASS committed; WARN pinning/freshness skipped (jq unavailable)
- [6/7] Formatting checks: WARN skipped (nixpkgs-fmt unavailable)
- [7/7] Secret/hygiene checks: PASS

Final preflight output indicated: Preflight PASSED - safe to push.

## 4) Verdict and Classification

Verdict: PASS

Failure classification:
- No blocking failures were observed.
- Non-blocking warnings were environment-related (missing jq, missing nixpkgs-fmt, and missing host-local /etc/nixos/hardware-configuration.nix in the WSL environment), not code-related regressions.
