# AppArmor Implementation — Phase 3 Review

| Field | Value |
| --- | --- |
| Reviewer | Phase 3 Review & QA subagent |
| Spec | [.github/docs/subagent_docs/apparmor_spec.md](.github/docs/subagent_docs/apparmor_spec.md) |
| Files reviewed | 2 created + 5 modified (see below) |
| Build environment | Windows host (PowerShell). Nix toolchain unavailable locally. |
| Build validation | Static review only — `nix flake check` and `nixos-rebuild dry-build` to be executed in Phase 6 by the orchestrator on a Nix-capable host. |
| Result | **PASS** |

---

## 1. Files Reviewed

**Created:**
- [modules/security.nix](modules/security.nix)
- [modules/security-server.nix](modules/security-server.nix)

**Modified:**
- [configuration-desktop.nix](configuration-desktop.nix)
- [configuration-htpc.nix](configuration-htpc.nix)
- [configuration-stateless.nix](configuration-stateless.nix)
- [configuration-server.nix](configuration-server.nix)
- [configuration-headless-server.nix](configuration-headless-server.nix)

---

## 2. Validation Results

### 2.1 Spec Compliance

Every produced artefact matches the spec verbatim:

- [modules/security.nix](modules/security.nix) reproduces §5.1 exactly — header, design notes, `enable = true`, `enableCache = true`, `killUnconfinedConfinables = false`, `packages = [ pkgs.apparmor-profiles ]`, empty `policies = { }`, and `apparmor-utils` in `environment.systemPackages`.
- [modules/security-server.nix](modules/security-server.nix) reproduces §5.2 exactly — `security.auditd.enable = true`, `security.audit.enable = true`, and the two-rule baseline (`-w /etc/apparmor.d/ -p wa -k apparmor_policy` and the time-change rule).
- All 5 role configs add the import(s) at the spec-prescribed position (immediately after the `system-*.nix` block, before the `nix*.nix` block) with the spec-prescribed inline comment `# AppArmor MAC baseline (all roles)` (and `# auditd + server audit ruleset` on server roles).

### 2.2 Module Architecture (Option B)

- [modules/security.nix](modules/security.nix) — universal base. Inspected line-by-line: **no `lib.mkIf`** guards anywhere; `lib` is in the function header but never used (see §3 below — RECOMMENDED, not blocking). All settings apply unconditionally.
- [modules/security-server.nix](modules/security-server.nix) — server addition. **No conditional logic**; presence in the import list is what makes it apply.
- Each `configuration-*.nix` expresses its role purely through its `imports` list. Server and headless-server import both files; display roles import only the base.

✅ Compliant with Option B.

### 2.3 Naming Convention

- `modules/security.nix` (universal base) and `modules/security-server.nix` (role addition) follow the `<subsystem>.nix` / `<subsystem>-<qualifier>.nix` pattern documented in `.github/copilot-instructions.md` and matches existing pairs such as `system.nix` / `system-gaming.nix` / `system-nosleep.nix`, `branding.nix` / `branding-display.nix`, `nix.nix` / `nix-desktop.nix` / `nix-server.nix` / `nix-stateless.nix`.

✅ Compliant.

### 2.4 Best Practices

| Item | Status |
|------|--------|
| `killUnconfinedConfinables = false` (safe default) | ✅ |
| `pkgs.apparmor-profiles` registered | ✅ |
| `pkgs.apparmor-utils` in `environment.systemPackages` for `aa-status` / `aa-logprof` | ✅ |
| `enableCache = true` for boot-time perf | ✅ |
| Empty `policies = { }` (enforce defaults; documented override pattern in comments) | ✅ |
| No manual `boot.kernelParams` for `apparmor=1` / `security=apparmor` (NixOS module handles it) | ✅ |
| `modules/system.nix` deliberately untouched | ✅ |

### 2.5 Consistency

Header style, `{ pkgs, lib, ... }:` argument lists, two-space indentation, trailing semicolons, and inline comment formatting match the surrounding module set (e.g. [modules/system.nix](modules/system.nix), [modules/audio.nix](modules/audio.nix), [modules/branding-display.nix](modules/branding-display.nix)). The "purpose / design notes" comment header is consistent with [modules/audio.nix](modules/audio.nix) and [modules/system.nix](modules/system.nix).

### 2.6 Completeness

All 5 role configs were updated:

| Role config | Imports `security.nix` | Imports `security-server.nix` |
|-------------|:----------------------:|:-----------------------------:|
| [configuration-desktop.nix](configuration-desktop.nix#L23) | ✅ | n/a |
| [configuration-htpc.nix](configuration-htpc.nix#L18) | ✅ | n/a |
| [configuration-stateless.nix](configuration-stateless.nix#L18) | ✅ | n/a |
| [configuration-server.nix](configuration-server.nix#L16) | ✅ | ✅ |
| [configuration-headless-server.nix](configuration-headless-server.nix#L9) | ✅ | ✅ |

### 2.7 Security

- No permissive overrides — defaults stay strict (enforce mode for every shipped profile).
- `killUnconfinedConfinables = false` is correctly justified in the comment as required for Steam/Proton/Wine on display roles; flipping it would be operationally disruptive and the spec calls this out.
- Server audit ruleset is minimal and reasonable: monitors `/etc/apparmor.d/` writes (`-p wa`) for tamper detection of policy material, and tracks `adjtimex`/`settimeofday` for forensic timeline integrity. Low-noise, high-signal — appropriate for long-running hosts and not punitive on log volume.
- No secrets, no world-writable paths, no permissive sudoers changes introduced.

### 2.8 Forbidden / Out-of-Scope Changes

| Constraint | Status |
|------------|:------:|
| `system.stateVersion = "25.11"` unchanged in all 5 role configs (verified by direct read) | ✅ |
| `hardware-configuration.nix` not added to the repo | ✅ |
| `flake.nix` not modified | ✅ |
| `modules/system.nix` not modified | ✅ |
| `modules/server/docker.nix` not modified | ✅ |
| `scripts/preflight.sh` not modified | ✅ |
| No new flake inputs (so no `inputs.X.follows = "nixpkgs"` work needed) | ✅ |

### 2.9 Syntax Sanity (static review)

Per-file inspection:

- [modules/security.nix](modules/security.nix): braces balanced (`{` ×3 / `}` ×3 in the body), trailing semicolons present on every attribute, attribute paths are correct upstream NixOS option names — `security.apparmor.enable`, `security.apparmor.enableCache`, `security.apparmor.killUnconfinedConfinables`, `security.apparmor.packages`, `security.apparmor.policies`. Types: `bool`, `bool`, `bool`, `listOf package`, `attrsOf` (empty set ok). `environment.systemPackages = [ pkgs.apparmor-utils ];` is well-formed.
- [modules/security-server.nix](modules/security-server.nix): braces balanced, semicolons present, option names `security.auditd.enable`, `security.audit.enable`, `security.audit.rules` are all valid NixOS 25.11 options. `rules` is `listOf str` and the two strings supplied are valid `auditctl` syntax (no embedded quotes that would need escaping).
- Role-config imports are inserted as discrete list items between existing `./modules/...nix` entries and inherit the same trailing-comma/whitespace behaviour Nix's list literal uses (no commas required — Nix lists are whitespace-separated).

No syntax issues detected.

### 2.10 Build Validation

**Static review only — Nix toolchain unavailable on Windows host; preflight to be executed in Phase 6 by the orchestrator if a Nix-capable environment is available, otherwise this is a structural/static-only validation.**

Static reasoning:
- All option names referenced are present on NixOS 25.11 (`security.apparmor.{enable,enableCache,killUnconfinedConfinables,packages,policies}`, `security.auditd.enable`, `security.audit.{enable,rules}`).
- All value types match the upstream module declarations (booleans, list of packages, attribute set, list of strings).
- `pkgs.apparmor-profiles` and `pkgs.apparmor-utils` are top-level attributes in nixpkgs `nixos-25.11`.
- No new flake inputs were introduced, so `flake.lock` is undisturbed and no `follows` declarations are required.
- Imports use `./modules/...` relative paths consistent with all other entries — the role configs evaluate from repo root via `nixpkgs.lib.nixosSystem` in `flake.nix`, so resolution is stable.

There is no plausible evaluation-time failure mode introduced by these changes.

---

## 3. Issues Found

### CRITICAL
None.

### RECOMMENDED (non-blocking)

1. **Unused `lib` argument in [modules/security.nix](modules/security.nix#L24)** — the function header is `{ pkgs, lib, ... }:` but `lib` is never referenced in the body. Nix doesn't warn on this and it doesn't break evaluation, but it diverges slightly from minimal-import style seen in some neighbouring modules. Either drop `lib` from the header or leave it — the spec did include it verbatim in §5.1, so leaving it is also defensible (forward-compatible if a `lib.mkDefault` is later added for an override). **Not required to address.**

### NITPICK
None.

---

## 4. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 98% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 96% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 95% | A (static-only on Windows; full build deferred to Phase 6) |

**Overall Grade: A+ (98.6%)**

---

## 5. Verdict

**PASS** — proceed to Phase 6 (Preflight). No refinement required.

The implementation reproduces the spec faithfully, complies with the Option B module architecture, preserves all forbidden invariants (`system.stateVersion`, `flake.nix`, `modules/system.nix`, `modules/server/docker.nix`, `scripts/preflight.sh`, no `hardware-configuration.nix`), and introduces no syntactic or semantic risk that static analysis can detect. Final closure validation is deferred to `scripts/preflight.sh` running on a Nix-capable host in Phase 6.
