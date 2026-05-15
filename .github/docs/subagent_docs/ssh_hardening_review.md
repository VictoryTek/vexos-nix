# SSH Hardening Review

**Feature:** `ssh_hardening`  
**Reviewed file:** `modules/network.nix`  
**Spec:** `.github/docs/subagent_docs/ssh_hardening_spec.md`  
**Date:** 2026-05-15  
**Reviewer:** QA subagent

---

## Specification Compliance

### Settings checklist

| Item | Expected | Actual | Result |
|------|----------|--------|--------|
| `PermitRootLogin` | `"no"` (unchanged) | `"no"` | ✅ PASS |
| `PasswordAuthentication` | `lib.mkDefault false` | `lib.mkDefault false` | ✅ PASS |
| `KbdInteractiveAuthentication` | `lib.mkDefault false` | `lib.mkDefault false` | ✅ PASS |
| `AuthenticationMethods` | `lib.mkDefault "publickey"` | `lib.mkDefault "publickey"` | ✅ PASS |
| `PermitEmptyPasswords` | `"no"` (hard, no mkDefault) | `"no"` | ✅ PASS |
| `X11Forwarding` | `false` (hard, no mkDefault) | `false` | ✅ PASS |
| `MaxAuthTries` | `lib.mkDefault "3"` | `lib.mkDefault "3"` | ✅ PASS |
| `LoginGraceTime` | `lib.mkDefault "30s"` | `lib.mkDefault "30s"` | ✅ PASS |
| `keyFiles` with `builtins.pathExists` guard | present | present | ✅ PASS |
| `Macs` / `KexAlgorithms` | NOT added | not present | ✅ PASS |

All 10 checklist items pass.

**Spec discrepancy noted:** `PermitEmptyPasswords` and `X11Forwarding` appear in the review checklist and in the implementation but are absent from the proposed replacement block in spec §3.1. The implementation is correct per the checklist; the spec's §3.1 proposed block is simply incomplete. This is a documentation gap in the spec, not a defect in the implementation.

**Minor omission:** The spec §3.1 includes an explanatory comment block above the `users.users.nimda.openssh.authorizedKeys.keyFiles` line; the implementation does not include that comment. The code is correct without it, but the comment would aid future maintainers.

---

## Code Quality

### Indentation and formatting

The SSH block uses 2-space indent for `services.openssh`, 4-space for `enable`/`settings`, and 6-space for settings attributes — consistent with the surrounding file style.

Column-aligned `=` within the `settings` block is consistent with the project's alignment style (see the `connection = { ... }` block in the `wired-fallback` profile above it in the same file). ✅

### `lib.mkDefault` vs plain assignment correctness

| Setting | Treatment | Correct? | Reason |
|---------|-----------|----------|--------|
| `PermitRootLogin` | plain | ✅ | Security invariant — no host should override |
| `PasswordAuthentication` | `lib.mkDefault` | ✅ | Desktop/LAN hosts may legitimately need it during setup |
| `KbdInteractiveAuthentication` | `lib.mkDefault` | ✅ | Same override use-case as above |
| `AuthenticationMethods` | `lib.mkDefault` | ✅ | Future 2FA hosts need to override |
| `PermitEmptyPasswords` | plain | ✅ | Security invariant — no host should permit empty passwords |
| `X11Forwarding` | plain | ✅ | No valid use case for X11 forwarding in this project |
| `MaxAuthTries` | `lib.mkDefault` | ✅ | Bastion/jump hosts may need more tries |
| `LoginGraceTime` | `lib.mkDefault` | ✅ | Slow WAN links may need more time |

All `lib.mkDefault` / plain assignments are correct per spec rationale. ✅

### `lib.optional` usage

```nix
users.users.nimda.openssh.authorizedKeys.keyFiles =
  lib.optional (builtins.pathExists ../authorized_keys) ../authorized_keys;
```

- `lib.optional` (singular, not `lib.optionals`) is correct — it takes a single value and returns `[value]` or `[]`. A list is what `keyFiles` expects. ✅
- `builtins.pathExists` is evaluated at Nix evaluation time. File exists at repo root → path added. File absent → empty list, build succeeds. ✅
- Relative path `../authorized_keys` resolves correctly from `modules/` to repo root, consistent with the established pattern in `modules/branding.nix`. ✅

### Scope placement

`users.users.nimda.openssh.authorizedKeys.keyFiles` is at module top level (2-space indent), between `services.openssh` and `networking.firewall.allowedTCPPorts`. This is correct NixOS module placement — NixOS merges all top-level option assignments across modules. It is not orphaned and not nested inside `services.openssh`. ✅

---

## Security Assessment

| Control | Status | Assessment |
|---------|--------|------------|
| Password brute-force via SSH | Mitigated | `PasswordAuthentication = lib.mkDefault false` |
| openssh 8.7+ PAM bypass via kbd-interactive | Mitigated | `KbdInteractiveAuthentication = lib.mkDefault false` |
| Belt-and-suspenders auth gate | Present | `AuthenticationMethods = lib.mkDefault "publickey"` |
| Empty password accounts | Blocked | `PermitEmptyPasswords = "no"` (hard) |
| X11 forwarding attack surface | Eliminated | `X11Forwarding = false` (hard) |
| Brute-force window per connection | Reduced | `MaxAuthTries = lib.mkDefault "3"` (from default 6) |
| Incomplete-connection DoS window | Reduced | `LoginGraceTime = lib.mkDefault "30s"` (from default 120s) |
| Operator lockout on empty `authorized_keys` | Mitigated | `lib.mkDefault` preserves password-auth override path; `builtins.pathExists` guard prevents build failure |
| Root login | Blocked | `PermitRootLogin = "no"` (unchanged) |

No security regressions introduced. The combination of `PasswordAuthentication`, `KbdInteractiveAuthentication`, and `AuthenticationMethods` is the correct triple for openssh 9.x to fully block password-based login paths. ✅

---

## Build Validation

**nix flake check:** Deferred to CI — nix unavailable on Windows host.

**Static validation results:**

1. **Brace balance:** The `services.openssh = { ... };` block closes correctly with matching `};`. No unclosed braces detected. ✅
2. **Value types:** All values are valid Nix types for `services.openssh.settings` (which accepts `attrsOf (oneOf [ bool int str ])`):
   - Strings: `"no"`, `"publickey"`, `"3"`, `"30s"` ✅
   - Booleans: `false` ✅
   - `lib.mkDefault` wrapping valid types ✅
3. **`lib` in scope:** The module signature `{ config, pkgs, lib, ... }:` includes `lib`. ✅
4. **`builtins.pathExists`:** Valid Nix builtin; no import required. ✅
5. **`../authorized_keys` path:** The file exists at repo root (confirmed from workspace structure). ✅
6. **Option path `users.users.nimda.openssh.authorizedKeys.keyFiles`:** Valid NixOS option path for the `openssh` module's per-user authorized keys. ✅
7. **No `Macs` or `KexAlgorithms`:** Correctly absent. ✅

No static syntax issues found.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 92% | A |
| Best Practices | 98% | A+ |
| Functionality | 97% | A+ |
| Code Quality | 97% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 97% | A+ |
| Build Success | 85% | B (deferred to CI — nix unavailable on Windows) |

**Overall Grade: A (96%)**

---

## Issues Found

### MINOR — Spec §3.1 proposed block incomplete
`PermitEmptyPasswords` and `X11Forwarding` are in the review checklist and correctly implemented, but absent from the spec's §3.1 proposed replacement block. The spec document should be updated to match the implementation. **Not a blocker — implementation is correct.**

### MINOR — Missing explanatory comment on `keyFiles` line
Spec §3.1 includes a 4-line comment above the `users.users.nimda.openssh.authorizedKeys.keyFiles` assignment explaining the `lib.optional`/`builtins.pathExists` pattern. The implementation omits it. **Not a blocker — code is self-evident and other comments exist in the file.**

---

## Verdict

**PASS**

The implementation is correct, secure, and idiomatic. All 10 specification compliance checklist items pass. `lib.mkDefault` / plain assignment choices are correct throughout. The `lib.optional` + `builtins.pathExists` guard is properly constructed. No syntax errors detected. Build validation deferred to CI (nix unavailable on Windows).

The two minor issues (incomplete spec block, missing comment) do not affect correctness, security, or buildability and do not require refinement.
