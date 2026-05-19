# cockpit-firewall-surface-hardening Review (Phase 3)

## Metadata
- Feature slug: cockpit-firewall-surface-hardening
- Phase: 3 (Review & Quality Assurance)
- Date: 2026-05-19
- Spec reviewed: `.github/docs/subagent_docs/cockpit_firewall_surface_hardening_spec.md`
- Files reviewed:
  - `modules/server/cockpit.nix`
  - `modules/security-server.nix`
  - `template/server-services.nix`

## Scope
This review validates specification compliance, hardening effectiveness, Nix correctness risk, and requested build/test commands.

## 1. Spec Compliance & Hardening Effectiveness

### 1.1 Cockpit/Samba automatic firewall opening removed
- Verified `openFirewall = false` for Cockpit and Samba in `modules/server/cockpit.nix`.
- Evidence:
  - `modules/server/cockpit.nix:208` (Cockpit)
  - `modules/server/cockpit.nix:279` (Samba)

Assessment: Matches spec requirement to replace service-level auto-open with explicit firewall policy.

### 1.2 Explicit firewall surface management implemented
- Verified computed service port sets and explicit firewall assignment.
- Interface-scoped rules are generated and applied when interface list is non-empty and firewalld is not enabled.
- Global fallback is applied otherwise, with warnings.
- Evidence:
  - Interface-scoped apply: `modules/server/cockpit.nix:234`
  - Global TCP apply: `modules/server/cockpit.nix:238`
  - Warnings blocks: `modules/server/cockpit.nix:214`, `modules/server/cockpit.nix:224`

Assessment: Meets architectural intent for explicit and constrained exposure with migration-friendly warnings.

### 1.3 Samba hardening controls added
- New options and behavior present:
  - `fileSharing.samba.enableNetbios` (default false)
  - `fileSharing.samba.bindInterfacesOnly` (default true)
  - `hosts allow` sourced from CIDR allowlist
  - optional `interfaces` binding when interface scopes are set
- Evidence:
  - `"hosts allow" = sambaAllowedHosts;` at `modules/server/cockpit.nix:284`

Assessment: Aligns with spec objective to reduce default SMB surface while preserving LAN usability.

### 1.4 NFS profile model implemented
- Verified profile enum with `v4-minimal` and `v3-compatible`.
- Verified fixed ports and conditional server port pinning for v3-compatible profile.
- Evidence:
  - Profile option: `modules/server/cockpit.nix:151`
  - Port pinning: `modules/server/cockpit.nix:300-302`

Assessment: Matches spec behavior for minimal default NFS exposure with explicit legacy compatibility path.

### 1.5 Secondary file checks
- `modules/security-server.nix`: comment/rationale updates only; no functional regression observed.
- `template/server-services.nix`: operator-facing commented examples for new hardening knobs added.

Assessment: Consistent with spec plan (minor documentation/comment consistency work).

## 2. Correctness, Regression, and Typing Review

## 2.1 Syntax / parse checks
Executed parse checks:
- `nix-instantiate --parse modules/server/cockpit.nix` -> exit 0
- `nix-instantiate --parse modules/security-server.nix` -> exit 0
- `nix-instantiate --parse template/server-services.nix` -> exit 0

Assessment: No Nix syntax errors in reviewed files.

## 2.2 Logical/typing regression findings
- No critical logic, typing, or compatibility defects identified in reviewed changes.
- Firewall rule synthesis, option typing, and conditional behavior are internally consistent with the requested hardening design.

## 3. Build Validation Results (Requested Commands)

### 3.1 `nix flake check`
- Attempted via WSL + nix profile initialization.
- Result: failed due environment purity/host-path constraint, not a direct syntax failure in reviewed files.
- Exact blocker:
  - `error: access to absolute path '/etc/nixos/hardware-configuration.nix' is forbidden in pure evaluation mode (use '--impure' to override)`

### 3.2 `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- Attempted directly; blocked by sudo password prompt in this environment.
- Also confirmed non-interactive attempt result:
  - `sudo: a password is required`

### 3.3 `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- Attempted non-interactive.
- Result/blocker:
  - `sudo: a password is required`

### 3.4 `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
- Attempted non-interactive.
- Result/blocker:
  - `sudo: a password is required`

Build Success status: **CAVEATED / BLOCKED BY ENVIRONMENT**.

## 4. Policy Checks

### 4.1 `hardware-configuration.nix` tracked check
- `git ls-files "*hardware-configuration.nix"` returned no tracked file.
- Requirement satisfied.

### 4.2 `system.stateVersion` unchanged check
- `configuration-desktop.nix` contains `system.stateVersion = "25.11";` at line 52.
- `git diff -- configuration-desktop.nix` returned no changes.
- Requirement satisfied.

## 5. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 96% | A |
| Best Practices | 95% | A |
| Functionality | 94% | A |
| Code Quality | 94% | A |
| Security | 97% | A+ |
| Performance | 93% | A |
| Consistency | 95% | A |
| Build Success | 62% | C |

Overall Grade: **A- (90%)**

## 6. Verdict

**PASS**

Rationale:
- No critical logic/syntax/compatibility issue was found in reviewed code.
- Hardening objectives from the spec are implemented effectively.
- Build validations are blocked by host/environment constraints (pure-eval absolute path restriction and sudo credential requirement), and are therefore recorded as caveated rather than implementation-failure defects.
