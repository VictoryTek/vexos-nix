# Specification: Fix GitHub Actions CI Failures

**Feature:** `fix_ci_actions`  
**Date:** 2026-04-19  
**Status:** Draft

---

## 1. Current State Analysis

### Workflow Files in Repository

| File | Purpose | Uses `cache-nix-action`? |
|------|---------|--------------------------|
| `.github/workflows/ci.yml` | Nix flake validation — lint + 4-group matrix evaluate | **Yes — v6** |
| `.github/workflows/update-flake-lock.yml` | Daily `nix flake update` + commit | No |
| `.github/workflows/gitlab-mirror.yml` | Mirror main branch to GitLab | No |

### `ci.yml` Summary

- **Trigger:** `push` to `main`, pull requests to `main` (excluding docs/wallpapers/files)
- **Jobs:**
  - `lint` — static checks (no Nix): verifies `hardware-configuration.nix` not tracked, verifies `system.stateVersion` present
  - `evaluate` — 4-group matrix (`desktop`, `stateless`, `server`, `htpc`), each evaluating 4–6 NixOS configs using `nix eval ... .drvPath`; each matrix job uses `cachix/install-nix-action@v31` then `nix-community/cache-nix-action@v6`

### Current `cache-nix-action` Configuration (per matrix job)

```yaml
- name: Cache Nix store
  uses: nix-community/cache-nix-action@v6
  with:
    primary-key: nix-${{ runner.os }}-${{ matrix.group }}-${{ hashFiles('flake.lock') }}
    restore-prefixes-first-match: nix-${{ runner.os }}-
    gc-max-store-size-linux: 8589934592  # 8 GiB
```

---

## 2. Problem Definition

### Issue 1: Node.js 20 Deprecation

**Symptom:** GitHub Actions emits deprecation warnings on every run:
```
Node.js 20 actions are deprecated. Please update the following actions to use
Node.js 24: nix-community/cache-nix-action@v6
```

**Root Cause:**
- `cache-nix-action@v6` was built against `actions/cache@v4`, which uses the Node.js 20 runtime (`runs: using: "node20"`).
- GitHub Actions deprecated Node.js 20 for actions; Node.js 24 becomes the default on **June 2, 2026**.
- Node.js 20 will be **removed from runners on September 16, 2026**.

**Impact:** Currently warnings only, but will become hard failures on September 16, 2026.

---

### Issue 2: `Failed to restore: "/usr/bin/tar" failed with exit code 2`

**Symptom:** Cache restore step fails with:
```
Failed to restore: "/usr/bin/tar" failed with exit code 2
```

**Root Cause (researched):** This is a known failure pattern in `actions/cache`-based actions on Ubuntu runners with several contributing factors:

1. **Stale/corrupted cache entry:** A cache was saved with a version that mismatches the current `paths` configuration. The tar archive is valid but the extracted content is either corrupt or the restore path has changed.

2. **zstd multi-threading bug (v6):** `cache-nix-action@v6` ran `zstd` in single-threaded mode. Under concurrency (4 matrix jobs running simultaneously), this could cause race conditions or partial writes to the cache artifact, resulting in a corrupt tar archive that fails to extract.

3. **SQLite WAL not checkpointed (v6):** Before v7, the Nix store SQLite database was not explicitly checkpointed before being packed into the cache. If the WAL file was mid-transaction, the restored database could be inconsistent, causing tar extraction recovery attempts to exit with code 2.

4. **Cache version mismatch:** The `cache-nix-action` computes a cache version from the combination of compression tool and `paths`. In v6, the default `paths` included more than just `/nix`. Any prior cache saved with v6's old default paths would conflict with a current restore.

---

## 3. Proposed Solution

### 3a. Upgrade `cache-nix-action` from `v6` to `v7`

**Confirmed via research:**
- Latest release: **`v7.0.2`** (January 30, 2026), latest tag: **`v7`**
- `action.yml` in v7 declares: `runs: using: "node24"` — confirmed Node.js 24 runtime
- v7 is based on `actions/cache@v5`, which also uses Node.js 24

**This single change resolves both issues:**

| Issue | How v7 Fixes It |
|-------|----------------|
| Node.js 20 deprecation | v7 uses `node24` runtime natively |
| tar exit code 2 (zstd) | v7 runs zstd in multi-threaded mode (#243) |
| tar exit code 2 (SQLite) | v7 checkpoints SQLite WAL before saving (#278, #279) |
| Stale cache conflicts | v7's default `paths` change (to `/nix` only) invalidates old caches, forcing a clean save on first run |

**`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` is NOT needed** since v7 natively targets Node.js 24.

### 3b. Breaking Change Compatibility: `paths` Default

`cache-nix-action@v7` changes the default `paths` to cache **only `/nix`** (previously included additional directories).

**Impact on this repo:** The current `ci.yml` does not set `paths` explicitly — it relies on action defaults. This means:
- On first run after upgrade, all existing v6 caches become invalidated (cache version mismatch due to changed paths)
- v7 will save a fresh cache covering only `/nix`, which is exactly what is needed for NixOS CI
- No explicit `paths` configuration change is needed

### 3c. Optional Enhancement: Cache Size Notation

The current setting `gc-max-store-size-linux: 8589934592` (8 GiB in raw bytes) can optionally be updated to the human-readable form `8G`, which has been supported since v6.1.0. This is purely aesthetic; both forms are valid in v7.

**Recommendation:** Update to `8G` for readability.

### 3d. Optional Enhancement: Stale Cache Purging

To prevent future tar failures from stale caches, adding purge configuration is recommended:

```yaml
purge: true
purge-prefixes: nix-${{ runner.os }}-
purge-last-accessed: P7D
purge-primary-key: never
```

This will purge caches matching `nix-Linux-` that have not been accessed in 7 days, keeping the cache storage clean. The `purge-primary-key: never` prevents the current run's cache from being purged.

**Note:** This requires `actions: write` permission, which is already set in `ci.yml`:
```yaml
permissions:
  contents: read
  actions: write   # Required by cache-nix-action to save Nix store cache
```

---

## 4. Implementation Steps

### File: `.github/workflows/ci.yml`

**Only this file requires changes.** `update-flake-lock.yml` and `gitlab-mirror.yml` do not use `cache-nix-action`.

#### Change 1 (REQUIRED): Upgrade action version

```yaml
# Before:
uses: nix-community/cache-nix-action@v6

# After:
uses: nix-community/cache-nix-action@v7
```

#### Change 2 (RECOMMENDED): Update gc-max-store-size-linux notation

```yaml
# Before:
gc-max-store-size-linux: 8589934592  # 8 GiB

# After:
gc-max-store-size-linux: 8G
```

#### Change 3 (RECOMMENDED): Add stale cache purging

Add the following inputs to the `Cache Nix store` step:

```yaml
purge: true
purge-prefixes: nix-${{ runner.os }}-
purge-last-accessed: P7D
purge-primary-key: never
```

#### Final `Cache Nix store` step (complete replacement):

```yaml
- name: Cache Nix store
  uses: nix-community/cache-nix-action@v7
  with:
    # Per-group primary key; restore-prefix falls back to any warmed cache
    # from a prior run of any group — nixpkgs store paths are shared.
    primary-key: nix-${{ runner.os }}-${{ matrix.group }}-${{ hashFiles('flake.lock') }}
    restore-prefixes-first-match: nix-${{ runner.os }}-
    gc-max-store-size-linux: 8G
    purge: true
    purge-prefixes: nix-${{ runner.os }}-
    purge-last-accessed: P7D
    purge-primary-key: never
```

---

## 5. Dependencies

| Dependency | Current | Target | Source |
|------------|---------|--------|--------|
| `nix-community/cache-nix-action` | `v6` | `v7` | https://github.com/nix-community/cache-nix-action/releases/tag/v7 |
| Node.js runtime (action) | `node20` | `node24` | Automatic — bundled in v7 action |

No new flake inputs. No changes to `flake.lock`. No changes to Nix modules.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Cache miss on first run after upgrade (due to path default change) | **Certain** | Expected and acceptable; Nix will re-evaluate and build, then save a fresh v7 cache. Adds ~10–15 min to first post-upgrade run. |
| v7 breaking change (cache only `/nix`) misses needed paths | Low | vexos-nix only needs `/nix` cached; no other paths are used in CI |
| Purge configuration deletes a valid cache that another job needs | Low | `purge-primary-key: never` ensures the current run's cache is never purged; `P7D` window is conservative |
| v7 incompatibility with `cachix/install-nix-action@v31` | Low | v7 release notes explicitly list `cachix/install-nix-action` as a supported compatible installer |
| Stale v6 caches causing tar failures during transition | Possible (first run) | After upgrade, v7 cannot restore v6 caches (version mismatch), so it will skip restore and save fresh — tar error cannot occur on a fresh save |

---

## 7. Files to Modify

| File | Change Type |
|------|------------|
| `.github/workflows/ci.yml` | Modify — upgrade cache-nix-action version + update inputs |

No other files require changes.
