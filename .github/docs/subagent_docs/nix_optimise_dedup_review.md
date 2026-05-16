# Review: Remove Redundant `nix.optimise.automatic` from `modules/nix.nix`

**Feature name:** `nix_optimise_dedup`
**Review date:** 2026-05-15
**Reviewer:** Review subagent (Phase 3)
**Spec file:** `.github/docs/subagent_docs/nix_optimise_dedup_spec.md`
**Modified file:** `modules/nix.nix`

---

## 1. Change Summary

The `nix.optimise` block (comment + `automatic = true` + `dates = [ "weekly" ]`) was removed
from `modules/nix.nix`. The `nix.settings.auto-optimise-store = true` setting was retained.
The file shrank by 6 lines. No other settings were altered.

---

## 2. Checklist Results

| # | Check | Result |
|---|-------|--------|
| 1 | `nix.optimise` block is GONE from `modules/nix.nix` | ✅ PASS — block does not appear in the file |
| 2 | `nix.settings.auto-optimise-store = true` is still present | ✅ PASS — line 13, with comment, intact |
| 3 | No other settings accidentally changed | ✅ PASS — file structure matches spec exactly; all other settings verified present |
| 4 | File is syntactically valid Nix | ✅ PASS — all four `nix build --dry-run --impure` evaluations succeeded (Nix parsed the file) |
| 5 | No `nix.optimise` references remain anywhere in the repo (`grep -r "nix\.optimise" . --include="*.nix"`) | ✅ PASS — zero matches |
| 6 | `hardware-configuration.nix` NOT tracked in git | ✅ PASS |
| 7 | `system.stateVersion` unchanged | ✅ PASS — not part of this change; verified not touched |

---

## 3. Build Validation Results

| Command | Exit code | Result |
|---------|-----------|--------|
| `nix flake check --impure` | 0 | ✅ PASS |
| `nix build --dry-run --impure .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel` | 0 | ✅ PASS |
| `nix build --dry-run --impure .#nixosConfigurations.vexos-desktop-nvidia.config.system.build.toplevel` | 0 | ✅ PASS |
| `nix build --dry-run --impure .#nixosConfigurations.vexos-desktop-vm.config.system.build.toplevel` | 0 | ✅ PASS |

> Note: The review prompt specified `nix build --dry-run .#vexos-desktop-amd`, which is not a
> valid attribute reference for `nixosConfigurations` outputs. The correct attribute path
> `.#nixosConfigurations.<name>.config.system.build.toplevel` was used. This is consistent with
> how NixOS system closures are built and is aligned with the spec's own `nixos-rebuild dry-build`
> validation steps. All four variants evaluated and produced a valid store closure.

---

## 4. Code Review

### `modules/nix.nix` (final state)

The file is clean and correct:

- `nix.settings.auto-optimise-store = true` is on line 13, inside the `nix.settings` block, with
  the existing comment "Deduplicate identical files in the store (saves significant disk space)".
- The `nix.optimise` block (lines 49-55 in the pre-change file) is entirely absent.
- `nix.daemonCPUSchedPolicy = "idle"` and `nix.daemonIOSchedClass = "idle"` follow immediately
  after the `nix.settings` closing brace, matching the spec's expected final shape exactly.
- `nixpkgs.config.allowUnfree = true` is the last line before the closing `}`.
- No dangling comments, no orphaned semicolons, no whitespace anomalies.

### Spec alignment

The implementation strictly follows the spec's "Exact change" section. The spec's "Resulting file
after change" code block matches the actual file content verbatim.

### Module architecture compliance

- Change is confined to `modules/nix.nix` — the universal base module for Nix daemon config.
- No `lib.mkIf` guards introduced.
- No role-specific additions created (not needed — this is a universal cleanup).
- Fully consistent with the Option B: Common base + role additions architecture.

---

## 5. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 100% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 100% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (100%)**

---

## 6. Findings

### Critical Issues
None.

### Recommended Improvements
None. The change is minimal, precise, and complete.

### Observations
- The spec notes a potential philosophical inconsistency: the community consensus in NixOS/nix#6033
  favours `nix.optimise.automatic` (scheduled timer) over `auto-optimise-store` for desktop machines.
  The spec explicitly follows the directive from `full_code_analysis.md` to keep `auto-optimise-store`
  instead. This decision is documented in the spec and is intentional. No action required.
- The preflight script (`scripts/preflight.sh`) passed independently (confirmed from terminal context).

---

## 7. Verdict

**PASS**

All checklist items satisfied. All four build targets evaluate successfully. The implementation
matches the spec exactly. No issues found.
