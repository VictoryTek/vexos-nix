# Preflight Overhaul — Review & Quality Assurance

**Feature:** preflight_overhaul  
**Date:** 2026-04-26  
**Reviewer:** Review Subagent (Phase 3)  
**Verdict:** NEEDS_REFINEMENT  

---

## 1. Specification Compliance

All stages from spec §4 are implemented:

| Spec Stage | Implemented | Notes |
|------------|-------------|-------|
| 0 — Nix + jq availability | ✅ | jq sub-check with `HAS_JQ` flag |
| 1 — `nix flake check` | ✅ | Unchanged; WARN when hw-config missing |
| 2 — Dry-build all variants | ✅ | Dynamic enum + 30-name fallback |
| 3 — hw-config not tracked | ✅ | Unchanged |
| 4 — stateVersion (5 files) | ✅ | Loop over all 5 `configuration-*.nix` |
| 5a — flake.lock committed | ✅ | Moved from old CHECK 8 |
| 5b — flake.lock pinned inputs | ✅ | NEW — `jq` query for `locked.rev` |
| 5c — flake.lock freshness | ⚠️ **BUG** | Query non-functional (see CRITICAL #2) |
| 6 — Nix formatting | ✅ | Unchanged |
| 7 — Secret scan | ✅ | Unchanged |
| Stage numbering `[0/7]`–`[7/7]` | ✅ | Matches spec Step 5 |
| Early exit after stage 4 | ✅ | Advisory stages 5–7 skipped on hard failure |

---

## 2. Dynamic Output Enumeration

| Check | Result |
|-------|--------|
| Uses `nix eval --impure --json '.#nixosConfigurations' --apply builtins.attrNames` | ✅ Line 99 |
| Pipes through `jq -r '.[]'` | ✅ Line 100 |
| Falls back to hardcoded list when dynamic enum fails | ✅ Lines 104–110 |
| Hardcoded fallback contains exactly 30 names | ✅ Verified via `grep -c` |
| Dynamic enum failure is non-fatal (`|| true`) | ✅ |
| `TARGET_COUNT` printed for visibility | ✅ "Discovered 30 nixosConfigurations outputs" |

**Live test:** Dynamic enumeration returned 30 outputs successfully.

---

## 3. stateVersion Validation

All 5 files checked (lines 147–162):

- [x] `configuration-desktop.nix`
- [x] `configuration-htpc.nix`
- [x] `configuration-server.nix`
- [x] `configuration-headless-server.nix`
- [x] `configuration-stateless.nix`

Missing file is a HARD failure. Missing `system.stateVersion` line is a HARD failure. ✅

---

## 4. Flake.lock Checks

### 5a — Committed
- Checks `git ls-files flake.lock` ✅
- Gracefully handles missing file ✅

### 5b — Pinned Inputs
- Uses `jq` with `to_entries[]` (correct approach) ✅
- Filters non-root nodes where `locked.rev == null` ✅
- Gracefully degrades when `HAS_JQ=0` ✅
- Gracefully degrades when `flake.lock` missing ✅
- **Live test:** Query returned empty (all inputs pinned) ✅

### 5c — Freshness (CRITICAL BUG)
- Uses `lastModified` from lock content (not git mtime) ✅ — correct intent
- **BUG:** `jq -r '.nodes.root.inputs | values | if type == "array" then .[] else . end'` — `values` in jq 1.8.1 returns the input object unchanged, NOT a stream/array of its values. `DIRECT_INPUTS` receives garbage (the raw JSON object text `{`, `}`, `"key": "value",` fragments). The for-loop never matches any valid node name, so `LAST_MOD` is always empty, `continue` always fires, and the check unconditionally reports "All direct inputs updated within N days."
- **Fix:** Replace `values` with `to_entries[] | .value` or `.[]` in the jq query.
- Gracefully degrades when `HAS_JQ=0` ✅
- Configurable thresholds via env vars ✅

---

## 5. Backward Compatibility

| Scenario | Required Behavior | Actual Behavior | Status |
|----------|------------------|-----------------|--------|
| Without sudo | dry-build = WARNING, not exit-1 | `nixos-rebuild` detected → `sudo nixos-rebuild` attempted → sudo fails → all 30 FAILs → EXIT_CODE=1 | ❌ **CRITICAL** |
| Without `/etc/nixos/hardware-configuration.nix` | flake check + dry-build = WARNING | WARN + skip for both stages 1 and 2 | ✅ |
| Without `jq` | lock checks = WARNING | `HAS_JQ=0` → stages 5b/5c emit WARN and skip | ✅ |

**CRITICAL #1 — Sudo fallback not implemented:**  
When `nixos-rebuild` is in PATH but `sudo` is restricted (container, CI sandbox, non-root user without sudo group), the script tries `sudo nixos-rebuild` for all 30 targets, each fails, sets `DRY_FAIL=1`, then `EXIT_CODE=1`. The `nix build --dry-run` fallback branch only triggers when `nixos-rebuild` is NOT found in PATH.

The spec backward compatibility table promises "CI without sudo: Stage 2 falls back to `nix build --dry-run`" but the implementation only checks `command -v nixos-rebuild`, not whether `sudo` is functional.

**Suggested fix:** Before the `nixos-rebuild` branch, test `sudo -n true 2>/dev/null` to verify sudo access. If sudo is unavailable, fall through to the `nix build --dry-run` fallback.

---

## 6. Security Review

| Check | Status |
|-------|--------|
| `set -uo pipefail` at top | ✅ Line 29 |
| No `eval` of user/external input | ✅ |
| All `$VARIABLES` properly quoted where needed | ✅ |
| No hardcoded secrets or credentials | ✅ |
| No world-writable temp files | ✅ (no temp files created) |
| No command injection vectors | ✅ — target names from controlled sources |
| No network calls beyond Nix's own | ✅ |

---

## 7. Code Quality

| Check | Status | Notes |
|-------|--------|-------|
| Clear stage headers | ✅ | `[N/7]` consistent throughout |
| Consistent pass/fail/warn formatting | ✅ | Color-coded helpers |
| Variable quoting | ✅ | `"$VAR"` used throughout |
| Conditional tests | ⚠️ | Uses `[ ]` instead of `[[ ]]` — minor style inconsistency |
| Exit code handling | ✅ | `EXIT_CODE` accumulator pattern |
| Header comment accurate | ✅ | Stage list matches implementation |
| `shellcheck` | ⚠️ | Not available locally; manual review performed |

---

## 8. Build / Script-Run Validation

```
$ bash scripts/preflight.sh 2>&1 | tail -20
```

**Result:** Script runs to completion without crashing.  
**Exit code:** 1  

**Breakdown of failures in this environment:**
- Stage 1: FAIL — `nix flake check` assertion error (boot.loader.grub.devices not set in hw-config). This is an environment-specific issue (the hw-config exists but is incomplete), not a script bug.
- Stage 2: FAIL — All 30 `sudo nixos-rebuild` calls fail because the container restricts `sudo`. This IS a script bug (CRITICAL #1).
- Stages 3–4: PASS
- Stages 5–7: Not reached (early exit after stage 4 hard failures)

**Note:** On a real NixOS host with proper `hardware-configuration.nix` and sudo access, the script would function correctly for stages 0–4. The sudo fallback issue only manifests in restricted environments.

---

## 9. Out-of-Scope Verification

```
$ git diff --name-only HEAD
scripts/preflight.sh
```

Only `scripts/preflight.sh` was modified. ✅  
No changes to: `flake.nix`, `modules/`, `configuration-*.nix`, `hosts/`, `home-*.nix`, `README.md`, `justfile`.

---

## 10. Phase 6 Minimum Requirements (copilot-instructions.md)

| Requirement | Present | Location |
|-------------|---------|----------|
| `nix flake check` | ✅ | Stage 1 (line 87) |
| Dry-build of all variants | ✅ | Stage 2 — 30 outputs |
| `hardware-configuration.nix` not tracked | ✅ | Stage 3 (line 138) |
| `system.stateVersion` present | ✅ | Stage 4 — all 5 files |

---

## CRITICAL Findings

### CRITICAL #1: Sudo Fallback Not Implemented

**Location:** `scripts/preflight.sh` lines 113–128 (Stage 2)  
**Severity:** CRITICAL  
**Impact:** Script hard-fails (EXIT_CODE=1) in any environment where `nixos-rebuild` is available but `sudo` is restricted. This includes containers, CI sandboxes, and non-root users without sudo group membership.

**Root cause:** The fallback logic checks `command -v nixos-rebuild` but does not verify `sudo` works. The `nix build --dry-run` fallback only triggers when `nixos-rebuild` is absent from PATH.

**Fix:** Add a `sudo -n true 2>/dev/null` guard before the `sudo nixos-rebuild` branch:
```bash
elif command -v nixos-rebuild &>/dev/null && sudo -n true 2>/dev/null; then
  # sudo nixos-rebuild path...
else
  # nix build --dry-run fallback...
fi
```

### CRITICAL #2: Freshness Check (5c) Non-Functional

**Location:** `scripts/preflight.sh` line ~238 (Stage 5c)  
**Severity:** CRITICAL  
**Impact:** The freshness check always reports "All direct inputs updated within N days" regardless of actual input ages. Stale inputs go undetected.

**Root cause:** The jq query uses `values` which in jq 1.8.1 returns the object itself, not a stream of its values. `DIRECT_INPUTS` receives the raw JSON text of the object (lines with `{`, `}`, `"key": "value",`). The for-loop never matches any valid node name → `LAST_MOD` always empty → `continue` always fires.

**Fix:** Replace the `values` filter with `to_entries[] | .value` or `.[]`:
```bash
# Before (broken):
DIRECT_INPUTS=$(jq -r '.nodes.root.inputs | values | if type == "array" then .[] else . end' ...)

# After (fixed):
DIRECT_INPUTS=$(jq -r '.nodes.root.inputs | to_entries[] | .value | if type == "array" then .[] else . end' ...)
```

---

## RECOMMENDED Improvements

1. **Use `[[ ]]` conditionals** — Replace `[ ]` with `[[ ]]` throughout for bash best practices (prevents word-splitting issues, supports regex matching).
2. **Add shellcheck to CI** — `shellcheck scripts/preflight.sh` could not be run locally (not installed). Adding it as a CI step would catch shell pitfalls automatically.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 90% | A- |
| Best Practices | 82% | B |
| Functionality | 70% | C+ |
| Code Quality | 88% | B+ |
| Security | 98% | A+ |
| Performance | 95% | A |
| Consistency | 90% | A- |
| Build Success | 55% | D |

**Overall Grade: B- (78%)**

---

## Verdict: **NEEDS_REFINEMENT**

Two CRITICAL issues must be resolved before PASS:

1. **Sudo fallback** — `sudo` availability must be tested before using `sudo nixos-rebuild`. When sudo is unavailable, fall back to `nix build --dry-run`.
2. **Freshness jq query** — Replace `values` with `to_entries[] | .value` in the stage 5c `DIRECT_INPUTS` query to produce valid node names.
