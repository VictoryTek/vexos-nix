# Review: install.sh sudo Wrapper Fix

**Feature:** `install_sudo_fix`  
**Date:** 2026-04-08  
**Reviewer:** Review Subagent (Phase 3)  
**File Reviewed:** `scripts/install.sh`  
**Spec:** `.github/docs/subagent_docs/install_sudo_fix_spec.md`

---

## Summary

The implementation correctly resolves the sudo setuid regression introduced by
the PATH export that prepended `/run/current-system/sw/bin`. The fix captures the
setuid sudo path into `_SUDO` before the PATH is mutated, then substitutes
`"$_SUDO"` for every real `sudo` invocation that follows. All review checklist
items pass. Build validation confirms both bash syntax and the full flake
evaluation are clean.

---

## Checklist Verification

| # | Check | Line(s) | Result |
|---|-------|---------|--------|
| 1 | `_SUDO="$(command -v sudo)"` appears BEFORE `export PATH=...` | L105 (capture) vs L109 (export) | ✅ PASS |
| 2 | `"$_SUDO" systemctl set-environment PATH="$PATH"` used | L110 | ✅ PASS |
| 3 | `"$_SUDO" nixos-rebuild switch` used | L112 | ✅ PASS |
| 4 | `"$_SUDO" reboot` used | L121 | ✅ PASS |
| 5 | `"$_SUDO" systemctl unset-environment PATH` used | L138 | ✅ PASS |
| 6 | No bare `sudo` calls after `export PATH=...` (only in echo literal) | L133 — inside `echo "..."` | ✅ PASS |
| 7 | Script is syntactically valid (`bash -n`) | — | ✅ PASS |
| 8 | No unrelated changes made | — | ✅ PASS |

---

## Detailed Findings

### Check 1 — `_SUDO` Capture Order

`_SUDO="$(command -v sudo)"` is placed at line 105, six lines before the
`export PATH=...` at line 109. At capture time, the shell's `$PATH` still
contains `/run/wrappers/bin` ahead of `/run/current-system/sw/bin`, so
`command -v sudo` correctly resolves to `/run/wrappers/bin/sudo` — the setuid
wrapper. This is exactly correct and matches the spec's intent.

### Check 6 — Lone `sudo` Keyword at Line 133

The only occurrence of the bare word `sudo` after the PATH export is inside a
double-quoted echo string:

```bash
echo "    sudo nixos-rebuild switch --flake /etc/nixos#${FLAKE_TARGET}"
```

This is a user-facing hint in the failure block. It is not a shell command
invocation and does not undergo command resolution. No issue.

### No Unrelated Changes

A line-by-line comparison against the spec's change table confirms that only
the specified modifications were applied:

- `_SUDO="$(command -v sudo)"` insertion before the comment block  
- `sudo` → `"$_SUDO"` substitution on lines 108, 110, 119, 136 (as renumbered
  after insertion)

No other lines were touched.

---

## Build Validation

### Bash Syntax Check

```
bash -n scripts/install.sh
# → SYNTAX OK (exit code 0)
```

### Nix Flake Check

```
nix flake check --impure
# → exit code 0
# Warnings present (Git uncommitted changes; builtins.derivation context) —
# these are pre-existing informational warnings, not errors.
```

Both validations passed cleanly.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

---

## Verdict

**PASS**

All checklist items verified. Bash syntax clean. Flake evaluation succeeds
(exit 0). The fix is minimal, targeted, and correct. No rework required.
