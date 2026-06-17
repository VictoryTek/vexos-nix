# Review: Split Flake Update Schedule

**Feature:** `flake_update_split_schedule`
**Date:** 2026-06-16
**Verdict:** PASS

---

## Files Reviewed

- `.github/workflows/update-flake-lock.yml`
- `scripts/install.sh`

---

## Checklist

| # | Check | Result |
|---|-------|--------|
| 1 | Push trigger removed | ✅ PASS |
| 2 | Daily cron scoped to Tue–Sun (`2-7`) | ✅ PASS |
| 3 | Weekly cron on Monday (`1`) | ✅ PASS |
| 4 | `github.event.schedule` string matches Monday cron exactly | ✅ PASS |
| 5 | `workflow_dispatch` triggers all-inputs update | ✅ PASS |
| 6 | Stable nixpkgs updated in both daily and weekly runs | ✅ PASS |
| 7 | All other inputs listed explicitly in weekly step | ✅ PASS |
| 8 | No empty commit risk (diff guard present) | ✅ PASS |
| 9 | installer pin-age hint guarded by `command -v python3` | ✅ PASS |
| 10 | installer pin-age hint guarded by `[ -f /etc/nixos/flake.lock ]` | ✅ PASS |
| 11 | Python block uses stdlib only (json, time) | ✅ PASS |
| 12 | Hint only shown when age < 48h | ✅ PASS |
| 13 | `nix flake show --impure` passes | ✅ PASS |
| 14 | `bash scripts/preflight.sh` passes | ✅ PASS |
| 15 | `hardware-configuration.nix` not tracked | ✅ PASS |
| 16 | `system.stateVersion` unchanged in all configs | ✅ PASS |

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 100% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 100% | A+ |
| Security | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (100%)**

---

## Summary

Both changes are correct and minimal. The workflow restructure eliminates the push
trigger and splits stable/unstable update cadence as specced. The installer hint
is fully defensive (guarded, optional, stdlib-only) and degrades silently if
python3 or flake.lock is absent.
