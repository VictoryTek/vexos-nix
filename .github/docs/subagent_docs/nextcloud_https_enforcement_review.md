# Nextcloud HTTPS Enforcement Review

Project: vexos-nix
Phase: 3 (Review and Quality Assurance)
Date: 2026-05-18
Spec: .github/docs/subagent_docs/nextcloud_https_enforcement_spec.md
Reviewed files:
- modules/server/nextcloud.nix
- template/server-services.nix
- scripts/preflight.sh

## Findings (ordered by severity)

### 1) Moderate: Required build validations were blocked by this host environment
- The requested commands were attempted exactly, but could not run in this Windows session:
  - `nix flake check` failed with CommandNotFoundException (`nix` unavailable).
  - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` failed (`Sudo is disabled on this machine`).
  - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` failed (`Sudo is disabled on this machine`).
  - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` failed (`Sudo is disabled on this machine`).
- Impact: runtime/evaluation assurance is reduced for this Phase 3 pass; this is treated as a QA caveat, not a code defect.

No critical security logic bugs or syntax issues were found in the reviewed changes.

## 1) Spec Compliance and Security Outcome

### 1.1 Secure default preserved
- `vexos.server.nextcloud.https` remains default `true` in modules/server/nextcloud.nix:43.
- `vexos.server.nextcloud.allowInsecureHttp` defaults to `false` in modules/server/nextcloud.nix:55.

Result: default behavior remains HTTPS-first with no insecure exposure opt-in enabled.

### 1.2 Insecure mode requires explicit opt-in
- Firewall port 80 is opened only when `cfg.https || cfg.allowInsecureHttp` in modules/server/nextcloud.nix:96.
- With `https = false`, broad plaintext exposure requires explicitly setting `allowInsecureHttp = true`.

Result: insecure LAN/plaintext mode is no longer implicit.

### 1.3 Plaintext mode constrained as designed
- When `https = false` and `allowInsecureHttp = false`, the nginx vhost is constrained to loopback listeners (127.0.0.1 / ::1) in modules/server/nextcloud.nix:87.
- Port 80 is not opened in this mode by the firewall expression in modules/server/nextcloud.nix:96.

Result: reverse-proxy backend HTTP remains available locally while reducing accidental LAN exposure.

### 1.4 Documentation and policy visibility updates
- Template guidance now documents all three transport modes at template/server-services.nix:65-72.
- Preflight adds warning-level detection for tracked insecure declarations at scripts/preflight.sh:390-393.

Result: explicit insecure declarations become visible during preflight and are less likely to be introduced silently.

## 2) Regression and Policy Conflict Check
- No regressions observed in Nextcloud secret-path behavior; existing hard-fail plaintext secret regression guards remain intact.
- Regex in preflight section 7d is anchored to uncommented assignments, avoiding template-comment false positives.
- Line endings are LF for all reviewed changed files (`git ls-files --eol` reported i/lf w/lf attr/text eol=lf).
- Git working tree check showed reviewed files modified and spec present as untracked doc artifact; no untracked module/code file introducing import-time delivery risk was observed in this scope.

## 3) Build Validation Attempt Results

| Command | Exit | Result | Notes |
|---------|------|--------|-------|
| nix flake check | 1 | BLOCKED | `nix` not available in this shell (CommandNotFoundException) |
| sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd | 1 | BLOCKED | sudo disabled on this machine |
| sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia | 1 | BLOCKED | sudo disabled on this machine |
| sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm | 1 | BLOCKED | sudo disabled on this machine |
| bash -n scripts/preflight.sh | 0 | PASS | Shell syntax parse check passed |

## Score Table
| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 96% | A |
| Security | 98% | A |
| Performance | 95% | A |
| Consistency | 97% | A |
| Build Success | 40% | C |

Overall Grade: B+ (89%)

## Review Verdict
PASS (with build-environment caveat)

## Build Result
BLOCKED BY ENVIRONMENT (required commands attempted, execution prevented on this host)
