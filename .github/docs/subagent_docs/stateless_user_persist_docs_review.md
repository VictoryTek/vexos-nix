# Review: Stateless Role — User-writable Persistent Documents Directory

## Modified Files
- `configuration-stateless.nix`
- `modules/impermanence.nix`

## Findings

### Specification Compliance
Implementation matches spec. `~/Documents` is persisted via a system-level
`environment.persistence."/persistent".directories` entry with absolute path and
correct ownership. The user-level `users.<name>.directories` approach was rejected
during implementation because the impermanence module asserts that all ephemeral
filesystem parents must have `neededForBoot = true`, and `/home` is declared in
this machine's `hardware-configuration.nix` without that flag. System-level
directories with an absolute path trigger the same assertion; the fix is a `/home`
tmpfs declaration in `modules/impermanence.nix`.

### Best Practices
- `lib.mkForce` is used correctly for all `/home` tmpfs attributes, consistent with
  the existing `/` tmpfs pattern.
- The `environment.persistence` entry uses absolute path + explicit `user`/`group`/`mode`,
  matching impermanence documentation.
- Comment in `configuration-stateless.nix` explains both what the entry does and WHY
  the system-level approach is used instead of `users.<name>.directories`.

### Consistency
- Follows Option B: stateless-specific persistence lives in `configuration-stateless.nix`.
- No `lib.mkIf` guards added to shared modules.
- The `/home` tmpfs declaration in `modules/impermanence.nix` belongs there because it
  is a structural requirement of the impermanence setup, not stateless-role-specific logic.

### Maintainability
- To add more persistent user directories in future, the pattern is clear:
  append another entry to the same `directories` list in `configuration-stateless.nix`.
- The `/home` tmpfs declaration is self-documenting via comments.

### Security
- No secrets, no world-writable paths, no plaintext credentials.
- `mode = "0755"` for `~/Documents` is appropriate (user-owned, group/world can read
  but not write; home itself is `0755` by NixOS default).

### Build Validation

| Target | Result |
|--------|--------|
| `nix flake show --impure` | PASS |
| `vexos-stateless-amd` | PASS (drvPath emitted) |
| `vexos-stateless-nvidia` | PASS |
| `vexos-stateless-vm` | PASS |
| `vexos-desktop-amd` | PASS (regression check) |
| `vexos-desktop-vm` | PASS (regression check) |

`hardware-configuration.nix` not committed (confirmed by dirty-tree warning, not a tracked file).
`system.stateVersion` unchanged (not touched by this change).

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 98% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99.75%)**

## Result: PASS
