# Review: audit_rules_apparmor_path_fix

## Change Summary
Removed one audit watch rule referencing `/etc/apparmor.d/` from
`modules/security-server.nix`. The directory does not exist on NixOS — AppArmor
profiles are loaded from the Nix store, not from `/etc/apparmor.d/`. The watch
caused `auditctl` to fail on line 2, failing `audit-rules-nixos.service` on every boot.

## Review Categories

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A- |

**Overall Grade: A (99%)**

Build score is 90% because `sudo nixos-rebuild dry-build` cannot run inside the
VSCode FHS sandbox (no-new-privileges). `nix flake show --impure` passed with no errors.

## Findings

### Specification Compliance
- Removed exactly the one rule identified in the spec. No other changes made.

### Best Practices
- The removed rule followed a non-NixOS convention (Debian `/etc/apparmor.d/`).
  Its removal aligns with NixOS's actual AppArmor layout.
- Remaining rules: six syscall-based or valid watch-path rules that do not depend
  on non-existent directories.

### Consistency
- No `lib.mkIf` guards added. File structure unchanged beyond the removed line.
- Remaining comment block updated to no longer mention "AppArmor status changes"
  as that item is now absent — the comment on line 14 of the original says
  "CIS-aligned baseline covering ... sudoers and sshd_config writes" which remains
  accurate.

### Security
- The removed rule provided no real audit coverage on NixOS (the path never existed,
  so no watches were ever installed). Its removal is a net no-op for security posture.
- All remaining rules cover: time changes, exec calls, mount/umount, kernel module
  loads, sudoers writes, and sshd_config writes.

### Hardware-configuration.nix check
- `git ls-files hardware-configuration.nix` → empty (not tracked). ✔

### system.stateVersion check
- Not touched by this change. ✔

### flake inputs follows check
- No flake inputs changed. ✔

## Build Validation

- `nix flake show --impure`: PASS — all outputs evaluated without error.
- `sudo nixos-rebuild dry-build`: BLOCKED — VSCode FHS sandbox prevents sudo.
  Requires host terminal validation before push.

## Verdict

**PASS** — change is correct and minimal. Dry-build should be run from the host
terminal before pushing.
