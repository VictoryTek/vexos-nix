# Phase 6 Preflight Report

Feature: encrypted-secrets-backend-sops-nix
Date: 2026-05-18
Status: PASS

## 1) Preflight Script Detection
- Detected: scripts/preflight.sh

## 2) CI Workflow Detection
- GitHub Actions workflows detected in .github/workflows/:
  - ci.yml
  - gitlab-mirror.yml
  - update-flake-lock.yml
- GitLab CI detected: .gitlab-ci.yml

## 3) Preflight Execution
Command:
```bash
wsl -d Ubuntu -- bash -c "source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null; source ~/.nix-profile/etc/profile.d/nix.sh 2>/dev/null; cd /mnt/c/Projects/vexos-nix && bash scripts/preflight.sh"
```

Observed execution (equivalent shell separator used by runner):
```bash
wsl -d Ubuntu -- bash -c "source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null; source ~/.nix-profile/etc/profile.d/nix.sh 2>/dev/null; cd /mnt/c/Projects/vexos-nix; bash scripts/preflight.sh"
```

Exit code: 0

Key output excerpts:
- "vexos-nix Preflight Validation"
- "✓ PASS  nix 2.34.1"
- "⚠ WARN  jq not found — flake.lock pinning and freshness checks will be skipped"
- "⚠ WARN  Skipping nix flake check — /etc/nixos/hardware-configuration.nix not found."
- "⚠ WARN  Skipping dry-build — /etc/nixos/hardware-configuration.nix not found."
- "⚠ WARN  nixpkgs-fmt not installed — skipping format check"
- "Preflight PASSED — safe to push."

## 4) Result Classification
- Final result: PASS
- Failure type: N/A (no failure)
- Warning classification: Environment-related (WSL environment missing jq, nixpkgs-fmt, and host-specific /etc/nixos/hardware-configuration.nix)
- Code-related failure detected: No
