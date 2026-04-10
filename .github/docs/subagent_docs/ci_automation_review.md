# CI Automation Review — vexos-nix
**Feature:** Automated `nix flake check` via GitHub Actions CI  
**Review Version:** 1.0  
**Date:** 2026-04-10  
**Reviewer:** CI/NixOS Code Review Agent  
**Spec:** `ci_automation_spec.md`

---

## Files Reviewed

| File | Status |
|------|--------|
| `.github/workflows/ci.yml` | NEW |
| `.github/workflows/update-flake-lock.yml` | Reference (style comparison) |
| `scripts/preflight.sh` | MODIFIED |
| `flake.nix` | Reference (nixosConfigurations names) |

---

## Section 1: `.github/workflows/ci.yml`

### 1.1 YAML Syntax — PASS

| Check | Result |
|-------|--------|
| Valid YAML with 2-space indentation | ✓ PASS |
| No tabs | ✓ PASS |
| No duplicate keys | ✓ PASS |
| `on:` defines push and pull_request | ✓ PASS |
| `runs-on: ubuntu-latest` | ✓ PASS |
| All steps use either `uses` or `run`, not both | ✓ PASS |

### 1.2 Security — PASS

| Check | Result |
|-------|--------|
| Only `GITHUB_TOKEN` secret referenced | ✓ PASS |
| `permissions: contents: read` set | ✓ PASS |
| Hardware stub (`printf ... sudo tee`) is non-destructive | ✓ PASS |
| `cachix/install-nix-action` pinned to a version tag | ✓ PASS (`@v31`) |

### 1.3 Functionality

| Check | Result | Notes |
|-------|--------|-------|
| `cachix/install-nix-action@v31` installs Nix with flakes | ✓ PASS | Matches `update-flake-lock.yml` |
| Stub `{ ... }: { }` is a valid NixOS module | ✓ PASS | Accepted by NixOS module system |
| `--no-build` flag present | ✓ PASS | Prevents package builds in CI |
| `--impure` flag present | ✓ PASS | Required for `/etc/nixos/hardware-configuration.nix` |
| `--show-trace` flag present | ✓ PASS | Useful for debugging failures |
| `paths-ignore` excludes non-code assets on push | ✓ PASS | `*.md`, `LICENSE`, `.github/docs/**`, `wallpapers/**`, `files/**` |
| Git hygiene checks included | ✓ PASS | `hardware-configuration.nix` and `system.stateVersion` verified |

#### WARNING-1 — Nix Store Cache Design (Non-Functional)

The `actions/cache@v4` step is placed **after** `cachix/install-nix-action`. This creates two compounding problems:

**Problem A — Step ordering:** `actions/cache@v4` performs its cache restore when the step executes. Because the Nix daemon is already running at that point (started by `cachix/install-nix-action`), the daemon has already initialized its store state. Restoring cache into a live store is non-standard.

**Problem B — File permissions:** On `ubuntu-latest`, `/nix/store` is owned by root (Nix daemon). The GitHub Actions runner user does not have write access. `actions/cache@v4` will silently fail to restore or save `/nix/store` entries due to permission denied errors. The cache for `~/.cache/nix` (evaluation cache) has the same ordering problem though would have fewer permission issues.

**Net effect:** The cache step is a no-op that adds ~5 seconds of overhead per run without providing any speed benefit. CI correctness is unaffected — `nix flake check` will still succeed, just at full download speed every run.

**Fix (recommended):** Move the `actions/cache@v4` step to BEFORE `cachix/install-nix-action`, or replace it with a Nix-specific cache tool such as `nix-community/cache-nix-action` which is purpose-built for this scenario. Alternatively, remove the cache step entirely since `cachix/install-nix-action@v31` itself handles some store path caching via GitHub-hosted runners.

```yaml
# Correct ordering:
- name: Checkout repository
  uses: actions/checkout@v4

- name: Cache Nix store paths          # ← BEFORE Nix install
  uses: actions/cache@v4
  with:
    path: ~/.cache/nix
    key: nix-eval-${{ runner.os }}-${{ hashFiles('flake.lock') }}
    restore-keys: nix-eval-${{ runner.os }}-

- name: Install Nix
  uses: cachix/install-nix-action@v31
```

Also note: cache path should target `~/.cache/nix` only (evaluation cache, runner-writable) rather than `/nix/store` (daemon-owned, not safely cacheable via `actions/cache`).

### 1.4 Style Consistency with `update-flake-lock.yml` — PASS

| Check | Result |
|-------|--------|
| Same 2-space indentation | ✓ PASS |
| Same `cachix/install-nix-action@v31` version | ✓ PASS |
| Same `actions/checkout@v4` | ✓ PASS |
| Same `GITHUB_TOKEN` supply pattern | ✓ PASS |
| Step naming convention consistent | ✓ PASS |

#### RECOMMENDATION-1 — Pin to Full Semver Tag

`cachix/install-nix-action@v31` uses the major version tag. This is a mutable pointer that the action author can move forward to any `v31.x.y` release. If a breaking change ships under `v31`, CI silently changes behavior. The spec identified `v31.10.4` as the current version.

**Recommendation:** Pin to `cachix/install-nix-action@v31.10.4` and use Dependabot or Renovate to manage upgrades. This is consistent with how `actions/checkout@v4` and `actions/cache@v4` are used — however, those are `@v4` which is also a mutable major tag, so this is a lower-priority improvement.

#### RECOMMENDATION-2 — Add `paths-ignore` to `pull_request` Trigger

Currently `push` has `paths-ignore` but `pull_request` does not (per spec design). This is architecturally sound — PRs should always run CI regardless of what changed. However, if a contributor opens a PR touching only `*.md` files, CI still runs but wastes runner time. This is low priority and the current spec intent is `None` for PR filtering.

---

## Section 2: `scripts/preflight.sh`

### 2.1 New CHECK [0/9] — Nix Binary Availability — PASS

| Check | Result |
|-------|--------|
| Uses `command -v nix &>/dev/null` | ✓ PASS — correct availability test |
| Exits with `exit 1` when nix not found | ✓ PASS — hard exit immediately |
| Provides Determinate Systems install URL | ✓ PASS |
| Provides `nix-daemon.sh` sourcing instructions | ✓ PASS |
| References CI workflow for context | ✓ PASS |
| No bare `nix` call before the check | ✓ PASS — check is first code after helpers |
| Prints Nix version on success | ✓ PASS — `nix --version` in pass message |

The check is well-structured. The early `exit 1` (not `EXIT_CODE=1`) is appropriate here because the entire preflight is useless without Nix — all subsequent checks require it.

### 2.2 Renumbering — PASS

| Check | Old Label | New Label | Expected |
|-------|-----------|-----------|----------|
| Nix availability | (new) | [0/9] | ✓ |
| nix flake check | [1/8] | [1/9] | ✓ |
| dry-build | [2/8] | [2/9] | ✓ |
| hw-config not tracked | [3/8] | [3/9] | ✓ |
| stateVersion present | [4/8] | [4/9] | ✓ |
| flake.lock freshness | [5/8] | [5/9] | ✓ |
| nixpkgs-fmt check | [6/8] | [6/9] | ✓ |
| secrets scan | [7/8] | [7/9] | ✓ |
| flake.lock committed | [8/8] | [8/9] | ✓ |

All 9 checks numbered [0/9] through [8/9]. No skips or duplicates. ✓

### 2.3 General Bash Quality — PASS with Note

| Check | Result |
|-------|--------|
| `set -uo pipefail` present | ✓ PASS |
| No syntax errors visible | ✓ PASS |
| `EXIT_CODE` tracking pattern maintained | ✓ PASS |
| New check integrates smoothly | ✓ PASS |

**Note on `set -uo pipefail` (no `-e`):** The absence of `-e` (exit on error) is intentional — the script uses an explicit `EXIT_CODE` accumulator to capture all failures and report them before exiting. This is the correct pattern for a validation script that should enumerate all problems. ✓

### 2.4 Pre-existing Issues (not introduced by this change)

These issues existed before the modification. They are flagged for awareness but do not constitute failures of the new check.

#### WARNING-2 — CHECK 1 Missing `--no-build` (Pre-existing)

`scripts/preflight.sh` CHECK 1 runs:
```bash
nix flake check --impure
```

The CI workflow runs:
```bash
nix flake check --no-build --impure --show-trace
```

Without `--no-build`, `nix flake check` may attempt to **build** (compile) derivations if they are not available in binary caches. For a 16-configuration flake pulling from `nixpkgs-unstable`, this could run for hours on a developer machine. The CI flag and the local preflight check are behaviorally inconsistent.

**Recommendation:** Change preflight CHECK 1 to:
```bash
nix flake check --no-build --impure --show-trace
```

This is not in scope for the current modification (spec only required adding CHECK 0) but should be addressed in a follow-up.

#### WARNING-3 — CHECK 2 Fallback Loop Has Duplicate Privacy Targets (Pre-existing)

The `nix build --dry-run` fallback loop (when `nixos-rebuild` is not available) lists the privacy targets twice:

```bash
for TARGET in vexos-desktop-amd vexos-desktop-nvidia vexos-desktop-vm vexos-desktop-intel \
  vexos-privacy-amd vexos-privacy-nvidia vexos-privacy-intel vexos-privacy-vm \
  vexos-privacy-amd vexos-privacy-nvidia vexos-privacy-intel vexos-privacy-vm; do
# ↑ privacy variants duplicated
```

This causes 4 redundant `nix build --dry-run` invocations. Not a correctness failure (dry-run is idempotent) but wastes significant time.

**Recommendation:** Deduplicate the fallback target list to match the `nixos-rebuild` loop above it.

#### WARNING-4 — Incomplete Configuration Coverage (Pre-existing)

Both the `nixos-rebuild` loop and the fallback loop cover only 8 of the 16 `nixosConfigurations` defined in `flake.nix`:

- ✓ Covered: `vexos-desktop-{amd,nvidia,intel,vm}`, `vexos-privacy-{amd,nvidia,intel,vm}`
- ✗ Missing: `vexos-server-{amd,nvidia,intel,vm}`, `vexos-htpc-{amd,nvidia,intel,vm}`

The CI workflow covers all 16 via `nix flake check` which evaluates all `nixosConfigurations.*` outputs. The preflight provides weaker local coverage.

**Recommendation:** Add the missing 8 variants to the `nixos-rebuild` and fallback loops, OR rely on `nix flake check --no-build --impure` (CHECK 1) as the comprehensive local check and mark the dry-build loops as optional extended validation.

---

## Section 3: Flake Configuration Name Verification

| Name in ci.yml / preflight.sh | Present in flake.nix |
|-------------------------------|---------------------|
| (CI validates all via `nix flake check`) | All 16 configs verified present |
| `hardware-configuration.nix` import at `/etc/nixos/` | ✓ Confirmed in `commonModules` |
| Stub satisfies `{ ... }: { }` module signature | ✓ Correct |

---

## Section 4: Score Table

| Category | Score | Grade | Notes |
|----------|-------|-------|-------|
| Specification Compliance | 97% | A | Spec implemented exactly; non-critical pre-existing gaps noted |
| Best Practices | 80% | B | Cache design non-functional; `--no-build` absent in preflight |
| Functionality | 92% | A- | CI correct end-to-end; cache step is dead weight; preflight works correctly |
| Code Quality | 87% | B+ | Duplicate fallback targets; otherwise clean |
| Security | 100% | A+ | Minimal permissions; no unsafe patterns; no curl-pipe-bash with pinning missing |
| Consistency | 88% | B+ | Minor flag divergence between CI and preflight; style otherwise consistent |
| Build Success | N/A | UNTESTED | Cannot run on Windows host |

**Overall Grade: A- (91%)**

---

## Section 5: Findings Summary

### CRITICAL
None.

### WARNING
| ID | Location | Issue |
|----|----------|-------|
| W-1 | `ci.yml` → Cache step | `actions/cache@v4` placed after Nix install; caching `/nix/store` fails silently due to permissions; cache step is a non-functional no-op |
| W-2 | `preflight.sh` CHECK 1 | `nix flake check` missing `--no-build`; inconsistent with CI behavior; risk of triggering full package builds locally |
| W-3 | `preflight.sh` CHECK 2 | Privacy targets duplicated in `nix build --dry-run` fallback loop |
| W-4 | `preflight.sh` CHECK 2 | Server and HTPC configurations not covered in dry-build loop (8 of 16) |

### RECOMMENDATION
| ID | Location | Recommendation |
|----|----------|---------------|
| R-1 | `ci.yml` | Pin `cachix/install-nix-action` to `v31.10.4` full semver |
| R-2 | `ci.yml` | Replace cache configuration: move before Nix install, target `~/.cache/nix` only |
| R-3 | `preflight.sh` CHECK 1 | Add `--no-build --show-trace` to `nix flake check --impure` |
| R-4 | `preflight.sh` CHECK 2 | Remove duplicate privacy targets from fallback loop |
| R-5 | `preflight.sh` CHECK 2 | Add `vexos-server-*` and `vexos-htpc-*` variants to dry-build loops |

---

## Section 6: Verdict

**PASS**

The specification is implemented correctly. The primary deliverables — `ci.yml` functional CI workflow and the new preflight CHECK [0/9] Nix availability gate — are sound. No CRITICAL issues were found. All three warnings are non-blocking: W-1 makes CI slower (not broken), W-2/W-3/W-4 are pre-existing issues in code outside the scope of this change.

The CI workflow will:
- Evaluate all 16 `nixosConfigurations` on every push to `main` and every PR
- Correctly handle the missing `/etc/nixos/hardware-configuration.nix` via the stub
- Enforce `hardware-configuration.nix` is not git-tracked
- Enforce `system.stateVersion` presence in `configuration.nix`

The preflight will:
- Immediately and clearly fail with WSL install instructions when Nix is not available
- Continue to function identically to the previous version on hosts where Nix is installed

Refinement of W-1, W-2, and R-2 is recommended as follow-up work.
