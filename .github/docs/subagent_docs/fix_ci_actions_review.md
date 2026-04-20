# Review: Fix GitHub Actions CI Failures

**Feature:** `fix_ci_actions`  
**Date:** 2026-04-19  
**Reviewer:** Review Subagent  
**Status:** NEEDS_REFINEMENT

---

## 1. Specification Compliance

The spec defined three changes to `.github/workflows/ci.yml`:

| Change | Label | Status |
|--------|-------|--------|
| Upgrade `cache-nix-action@v6` → `@v7` | REQUIRED | ✅ Done |
| Change `gc-max-store-size-linux` to `8G` notation | RECOMMENDED | ❌ Not done |
| Add stale cache purge configuration | RECOMMENDED | ❌ Not done |

The spec's Section 4 provides a "Final Cache Nix store step (complete replacement)" showing the target configuration with all three changes applied. The implementation only applied the version bump and did not match the final form specified.

**Actual `Cache Nix store` step in the implemented file:**

```yaml
- name: Cache Nix store
  uses: nix-community/cache-nix-action@v7
  with:
    primary-key: nix-${{ runner.os }}-${{ matrix.group }}-${{ hashFiles('flake.lock') }}
    restore-prefixes-first-match: nix-${{ runner.os }}-
    gc-max-store-size-linux: 8589934592  # 8 GiB
```

**Expected final form per spec:**

```yaml
- name: Cache Nix store
  uses: nix-community/cache-nix-action@v7
  with:
    primary-key: nix-${{ runner.os }}-${{ matrix.group }}-${{ hashFiles('flake.lock') }}
    restore-prefixes-first-match: nix-${{ runner.os }}-
    gc-max-store-size-linux: 8G
    purge: true
    purge-prefixes: nix-${{ runner.os }}-
    purge-last-accessed: P7D
    purge-primary-key: never
```

---

## 2. Correctness

| Check | Result |
|-------|--------|
| `cache-nix-action` at `@v7` | ✅ Correct |
| Node.js 24 readiness via v7 native `node24` runtime | ✅ Correct |
| Tar exit code 2 fix addressed (v7 fixes zstd threading + SQLite WAL checkpoint) | ✅ Addressed by v7 upgrade |
| `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` absent (correctly NOT added) | ✅ Correct |
| No unintended changes to other workflow files | ✅ Correct — only `ci.yml` modified |
| No changes to Nix modules, `flake.nix`, or `flake.lock` | ✅ Correct |

---

## 3. Scope

No changes were made outside `.github/workflows/ci.yml`. The other workflow files (`update-flake-lock.yml`, `gitlab-mirror.yml`) were correctly left untouched. No Nix configuration files were altered.

One pre-existing concern noted (out of scope for this fix): Both `actions/checkout` steps use `@v6`, which does not appear to be a released version of that action (latest stable is v4). This is a pre-existing issue not introduced by this change and is outside the scope of this fix.

---

## 4. Node.js 24 Readiness

`cache-nix-action@v7` uses `runs: using: "node24"` natively — confirmed per spec research. This resolves the Node.js 20 deprecation warning without requiring the `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` environment variable workaround.

---

## 5. Tar Exit Code 2 Fix

Upgrading to v7 addresses all three root causes identified in the spec:

- **zstd multi-threading:** v7 runs zstd in multi-threaded mode (resolves race condition under 4-group matrix parallelism)
- **SQLite WAL checkpoint:** v7 explicitly checkpoints the Nix store SQLite WAL before saving
- **Stale cache invalidation:** v7's updated default `paths` (only `/nix`) invalidates all v6 caches, forcing a clean save on first run

---

## 6. Preflight Validation

**Result: ENVIRONMENT-CONSTRAINED — Pre-existing failures, not caused by this change**

The preflight script was run and produced failures:

1. **`nix flake check` failure** — `boot.loader.grub.devices` assertion fires because the review environment lacks a proper `hardware-configuration.nix`. This is a pre-existing constraint of the sandboxed review environment, not caused by the CI YAML change.

2. **`nixos-rebuild dry-build` failures** — All 8 dry-build steps failed with `sudo: The "no new privileges" flag is set`. The review environment is a sandboxed container that prevents privilege escalation. These failures are entirely environmental and unrelated to the workflow YAML change.

3. **`hardware-configuration.nix` not tracked** — ✅ PASS
4. **`system.stateVersion` present** — ✅ PASS

**Assessment:** The GitHub Actions YAML change (a version string only) cannot cause any Nix evaluation or build failures. The preflight failures are pre-existing environmental constraints present regardless of this change. The CI workflow itself will be verified by GitHub's own runner when pushed.

---

## 7. Issues Found

### Critical Issues: None

### Notable Gap: Incomplete Implementation of Spec's Final Form

The spec's Section 4 defines a "Final Cache Nix store step (complete replacement)" that serves as the target configuration. The implementation applied only the REQUIRED version bump and omitted both RECOMMENDED changes:

**Missing: `gc-max-store-size-linux` readability update**  
- Current: `gc-max-store-size-linux: 8589934592  # 8 GiB`
- Spec target: `gc-max-store-size-linux: 8G`
- Both values are functionally identical; this is a readability improvement supported since v6.1.0

**Missing: Stale cache purge configuration**  
- The spec explicitly recommends adding purge settings to prevent future tar failures from stale caches
- Four purge keys are missing: `purge`, `purge-prefixes`, `purge-last-accessed`, `purge-primary-key`
- The `actions: write` permission required by purging is already present in the workflow
- Without purge configuration, stale v6 caches may still persist in GitHub's cache storage and could interfere with future runs until they expire naturally

---

## 8. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 60% | D |
| Best Practices | 70% | C |
| Functionality | 95% | A |
| Code Quality | 80% | B |
| Security | 100% | A |
| Performance | 75% | C |
| Consistency | 95% | A |
| Build Success | N/A* | — |

**Overall Grade: C+ (79%)**

> *Build Success is not gradeable for this change: the modification is a GitHub Actions YAML file. It cannot be tested locally, and preflight failures are pre-existing environmental constraints unrelated to this change.

---

## 9. Required Refinements

To fully implement the spec's intended final configuration, the following must be applied to the `Cache Nix store` step in `.github/workflows/ci.yml`:

1. Change `gc-max-store-size-linux: 8589934592  # 8 GiB` → `gc-max-store-size-linux: 8G`
2. Add after `gc-max-store-size-linux`:
   ```yaml
   purge: true
   purge-prefixes: nix-${{ runner.os }}-
   purge-last-accessed: P7D
   purge-primary-key: never
   ```

---

## Verdict: NEEDS_REFINEMENT

The REQUIRED change was correctly applied. However, the implementation does not match the spec's specified final form — two RECOMMENDED changes documented as part of the complete replacement were omitted.
