# CI Automation Specification — vexos-nix
**Feature:** Automated `nix flake check` via GitHub Actions CI  
**Spec Version:** 1.0  
**Date:** 2026-04-10  
**Status:** READY FOR IMPLEMENTATION  

---

## 1. Current State Analysis

### 1.1 Existing Workflows

| File | Purpose | Uses Nix? |
|------|---------|-----------|
| `.github/workflows/update-flake-lock.yml` | Daily `nix flake update` + commit flake.lock | Yes — installs via `cachix/install-nix-action@v31` |
| `.github/workflows/gitlab-mirror.yml` | Push main branch to GitLab mirror | No |

**Notable:** `update-flake-lock.yml` already uses `cachix/install-nix-action@v31` and supplies `GITHUB_TOKEN` for rate limit avoidance. The CI workflow should match this pattern for consistency.

### 1.2 Flake Structure

The flake defines **16 `nixosConfigurations`** outputs across four roles × four GPU variants:

| Role | Variants |
|------|----------|
| `desktop` | amd, nvidia, intel, vm |
| `stateless` | amd, nvidia, intel, vm |
| `server` | amd, nvidia, intel, vm |
| `htpc` | amd, nvidia, intel, vm |

Additionally, the flake exports `nixosModules.base`, `nixosModules.stateless`, `nixosModules.server`, and `nixosModules.htpc`.

**Critical constraint:** ALL `nixosConfigurations` share `commonModules` which directly imports `/etc/nixos/hardware-configuration.nix` as an absolute filesystem path. This path is host-generated, never tracked in the repository, and will not exist on a GitHub Actions Ubuntu runner.

### 1.3 `scripts/preflight.sh` Current State

The script performs 8 checks in order:

1. `nix flake check --impure` (skips with WARN if `/etc/nixos/hardware-configuration.nix` absent)
2. `nixos-rebuild dry-build` or `nix build --dry-run` fallback (skips with WARN if no hw-config)
3. `hardware-configuration.nix` not tracked in git (HARD)
4. `system.stateVersion` present in `configuration.nix` (HARD)
5. `flake.lock` freshness (WARN)
6. `nixpkgs-fmt --check` formatting (WARN)
7. Hardcoded secrets scan (WARN)
8. `flake.lock` committed to git (WARN)

**Problem with current script:** When `nix` itself is not installed (Windows/WSL Ubuntu), checks 1 and 2 either emit a confusing error or silently fall through. The script does not detect a missing `nix` binary before attempting to use it.

### 1.4 Local Development Environment

- User OS: Windows, developing via WSL2 Ubuntu
- Nix status in WSL Ubuntu: **NOT INSTALLED**
- `nixos-rebuild` availability: **NEVER available** outside a NixOS host
- Result: The user currently has **zero automated Nix validation** before pushing

---

## 2. Problem Definition

### 2.1 Root Causes

| Problem | Impact |
|---------|--------|
| Nix not installed in WSL Ubuntu | Cannot run `nix flake check` locally |
| `nixos-rebuild` requires a NixOS host | Cannot run `dry-build` locally |
| `/etc/nixos/hardware-configuration.nix` is host-specific | Blocks evaluation on non-hosts |
| No CI validation workflow exists | Configuration errors only discovered at deploy time |

### 2.2 What We Need

1. **Automatic CI** that runs `nix flake check` on every push and PR — without a live NixOS host
2. An **improved `preflight.sh`** that clearly guides Windows/WSL users instead of silently failing
3. **Documentation** of the WSL local Nix setup path

---

## 3. Research Findings

### 3.1 Available GitHub Actions for Installing Nix

| Action | Latest Version | Notes |
|--------|---------------|-------|
| `cachix/install-nix-action` | **v31.10.4** (2026-04-08, Nix 2.34.5 SECURITY FIX) | Installs upstream Nix; already used in this repo |
| `DeterminateSystems/nix-installer-action` | **v22** (2026-03-25) | Installs Determinate Nix by default since v21; more features but heavier |

**Selected: `cachix/install-nix-action@v31`** — consistent with the existing `update-flake-lock.yml` workflow, lightweight, well-maintained, and supplies the latest security-patched upstream Nix.

### 3.2 Solving the `hardware-configuration.nix` Problem in CI

The cleanest solution for CI is to create a **minimal stub** at `/etc/nixos/hardware-configuration.nix` before running the check:

```nix
{ ... }: { }
```

This satisfies the Nix import statement without asserting any hardware configuration. The NixOS module system accepts an empty module. This is the standard technique used by NixOS flake CI pipelines without self-hosted NixOS runners.

### 3.3 `nix flake check` vs `nixos-rebuild dry-build` vs `nix build`

| Command | Runs On | What It Checks | CI Suitable? |
|---------|---------|----------------|--------------|
| `nix flake check --no-build --impure` | Any Linux with Nix | Evaluates ALL flake outputs; validates module system, option types, imports | **YES — primary gate** |
| `nixos-rebuild dry-build` | NixOS hosts ONLY | Fetches full closure from binary cache | No (needs NixOS) |
| `nix build .#...toplevel --dry-run` | Any Linux with Nix | Queries binary caches for full closure (~5–15 min/target × 16 targets) | Impractical for 16 targets |
| `nix eval .#...config.system.build.toplevel` | Any Linux with Nix | Shallow evaluation only | Optional supplemental check |

**Selection: `nix flake check --no-build --impure`**

What this evaluates:
- For every `nixosConfigurations.X`: evaluates `X.config.system.build.toplevel` as a derivation — this triggers the **full NixOS module system evaluation**
- Catches: import errors, option type mismatches, missing attributes, undefined variables, broken module references
- Does NOT catch: build failures (compilation errors in packages), runtime config issues
- With `--no-build`: derivations are created (Nix evaluates them) but no compilers are invoked and no packages are downloaded
- With `--impure`: allows access to `/etc/nixos/hardware-configuration.nix` outside the Nix store (required for our stub approach)

### 3.4 `nix flake check` Flag Availability

`--no-build` was added in Nix 2.15. `cachix/install-nix-action@v31` installs Nix 2.34.5. Flag is available.

### 3.5 Caching Strategy

For a `--no-build` evaluation-only check:
- Primary evaluation cost: fetching and parsing `nixpkgs` (NixOS 25.11) and `nixpkgs-unstable` flake trees
- These are fetched as tarballs, content-addressed by `flake.lock` hashes
- `cachix/install-nix-action` handles the Nix installer cache
- The Nix daemon's built-in evaluation cache (`~/.cache/nix/`) is not persistent across GitHub Actions jobs
- **Recommendation:** Add `actions/cache@v4` keyed on `flake.lock` hash to cache `/nix/store` fetched paths

This is optional but reduces the first-evaluation time from ~3–5 min to ~30 sec on repeated runs.

### 3.6 WSL Local Nix Installation

The Determinate Systems installer supports WSL2 Ubuntu:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

This installs Nix with flakes enabled by default. After installation:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
# Or restart the terminal
```

Then `scripts/preflight.sh` can be run locally.

**Alternative (upstream Nix):**
```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### 3.7 `magic-nix-cache-action` Status

As of 2025–2026, `magic-nix-cache-action` (latest v13) is being superseded by Determinate Nix's built-in FlakeHub Cache. Since we are using `cachix/install-nix-action` (not Determinate Nix), and our CI only does `--no-build` evaluation, `magic-nix-cache-action` brings no benefit here and is **excluded from the design**.

---

## 4. Solution Architecture

### 4.1 Files to Create

| File | Description |
|------|-------------|
| `.github/workflows/ci.yml` | New GitHub Actions CI workflow |

### 4.2 Files to Modify

| File | Change |
|------|--------|
| `scripts/preflight.sh` | Add Nix availability pre-check with actionable WSL install guidance |

### 4.3 Files NOT Changed

- `flake.nix` — No changes required
- `configuration.nix` and all module files — No changes required
- `.github/workflows/update-flake-lock.yml` — No changes (separate concern)

---

## 5. GitHub Actions Workflow Design

**File:** `.github/workflows/ci.yml`

### 5.1 Trigger Conditions

| Event | Branches | Path Filter |
|-------|---------|------------|
| `push` | `main` | Exclude: `*.md`, `LICENSE`, `.github/docs/**`, `wallpapers/**`, `files/**` |
| `pull_request` | `main` | None |

**Rationale for path filters:** Documentation, wallpapers, and background assets cannot affect Nix evaluation. Skipping CI for these reduces unnecessary wait time.

### 5.2 Permissions

```yaml
permissions:
  contents: read
```

The CI workflow only reads repository files and accesses `GITHUB_TOKEN` for GitHub API rate limiting on Nix fetches. No write access needed.

### 5.3 Job: `flake-check`

```yaml
name: CI — Nix Flake Validation

on:
  push:
    branches: [main]
    paths-ignore:
      - '*.md'
      - 'LICENSE'
      - '.github/docs/**'
      - 'wallpapers/**'
      - 'files/**'
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  flake-check:
    name: Evaluate all NixOS configurations
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install Nix
        uses: cachix/install-nix-action@v31
        with:
          # Supplies GITHUB_TOKEN to the Nix daemon to avoid API rate limits
          # when fetching flake inputs (nixpkgs, nix-gaming, home-manager, etc.)
          github_access_token: ${{ secrets.GITHUB_TOKEN }}

      - name: Cache Nix store paths
        uses: actions/cache@v4
        with:
          path: |
            ~/.cache/nix
            /nix/store
          key: nix-store-${{ runner.os }}-${{ hashFiles('flake.lock') }}
          restore-keys: |
            nix-store-${{ runner.os }}-

      - name: Create stub hardware-configuration.nix for CI
        run: |
          # This stub satisfies the flake's commonModules import of
          # /etc/nixos/hardware-configuration.nix without asserting any
          # hardware config.  It is NOT deployed to any host.
          sudo mkdir -p /etc/nixos
          printf '# CI stub — provides no real hardware config\n{ ... }: { }\n' \
            | sudo tee /etc/nixos/hardware-configuration.nix > /dev/null

      - name: nix flake check — evaluate all configurations (no build)
        # --no-build: evaluate derivations without building packages
        # --impure:   allow access to /etc/nixos/hardware-configuration.nix
        # --show-trace: print full Nix evaluation stack on failure
        run: nix flake check --no-build --impure --show-trace

      - name: Verify hardware-configuration.nix is not tracked in git
        run: |
          if git ls-files hardware-configuration.nix | grep -q .; then
            echo "FAIL: hardware-configuration.nix must not be tracked in git"
            exit 1
          fi
          echo "PASS: hardware-configuration.nix is not tracked"

      - name: Verify system.stateVersion present in configuration.nix
        run: |
          if ! grep -q 'system\.stateVersion' configuration.nix; then
            echo "FAIL: system.stateVersion missing from configuration.nix"
            exit 1
          fi
          echo "PASS: system.stateVersion is present"
```

### 5.4 Step-by-Step Rationale

| Step | Purpose | Failure Mode |
|------|---------|--------------|
| `actions/checkout@v4` | Standard repo checkout | Blocks all subsequent steps |
| `cachix/install-nix-action@v31` | Installs Nix 2.34.5 with flakes + daemon | Blocks all Nix steps |
| `actions/cache@v4` | Restores Nix store from previous runs (key = flake.lock hash) | Soft failure — cache miss falls through |
| Stub `hardware-configuration.nix` | Satisfies absolute path import without leaking host HW info | Must succeed — `sudo tee` is reliable on ubuntu-latest |
| `nix flake check --no-build --impure` | Evaluates all 16 NixOS configs + all nixosModules | Hard failure — exits non-zero on any module evaluation error |
| Git hygiene checks | Mirror critical preflight.sh checks | Hard failure — exit 1 on violation |

### 5.5 Cache Design

The `actions/cache@v4` step caches:
- `~/.cache/nix` — Nix evaluation cache (parsed flake trees)
- `/nix/store` — Downloaded store paths (fetched flake inputs)

**Cache key:** `nix-store-{os}-{sha256(flake.lock)}`  
When `flake.lock` changes (e.g., after `nix flake update`), the cache is invalidated and rebuilt automatically. The `restore-keys` fallback allows partial cache hits from previous flake.lock versions.

**Note on cache size:** nixpkgs tarballs and parsed inputs for a full NixOS flake are typically 1–3 GB in the Nix store. GitHub Actions provides 10 GB of cache space per repository. Monitor with `du -sh /nix/store` if space becomes a concern.

---

## 6. `scripts/preflight.sh` Update Design

### 6.1 Change: Add Nix Availability Pre-Check

Insert a new **CHECK 0** block immediately after the header section and before CHECK 1. This check runs **before** any Nix commands are attempted.

**Location:** After the `echo "======..."` header block, before `echo "[1/8] Validating flake structure..."`.

**Behavior:**
- If `nix` is not in `PATH`: print a clear error with the Determinate Systems install command and exit 1
- If `nix` is present: continue to CHECK 1 as before

**Purpose:** Replaces the current confusing "command not found" error with an actionable, user-friendly message that guides WSL/non-NixOS users to the correct installer.

### 6.2 New Code Block

```bash
# ---------- CHECK 0: Nix binary availability (HARD) -------------------------
echo "[0/9] Checking for Nix installation..."
if ! command -v nix &>/dev/null; then
  echo ""
  fail "nix is not installed or not in PATH"
  echo ""
  echo "  Nix is required to run this preflight script."
  echo "  On WSL2 Ubuntu (or any Linux), install Nix via Determinate Systems:"
  echo ""
  echo "    curl --proto '=https' --tlsv1.2 -sSf -L \\"
  echo "      https://install.determinate.systems/nix | sh -s -- install"
  echo ""
  echo "  After installation, restart your terminal or run:"
  echo "    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  echo ""
  echo "  GitHub Actions CI runs this check automatically via cachix/install-nix-action."
  echo "  See: .github/workflows/ci.yml"
  echo ""
  exit 1
fi
pass "nix $(nix --version 2>/dev/null | head -1 | sed 's/nix (Nix) //')"
echo ""
```

### 6.3 Check Numbering Update

After adding CHECK 0, all subsequent checks shift from `[1/8]`→`[1/9]` through `[8/8]`→`[8/9]`, and the early-exit message references `[4/9]` instead of `[3/8]`, etc.

**Required counter updates:**
- `[1/8]` → `[1/9]`
- `[2/8]` → `[2/9]`
- `[3/8]` → `[3/9]`
- `[4/8]` → `[4/9]`
- `[5/8]` → `[5/9]`
- `[6/8]` → `[6/9]`
- `[7/8]` → `[7/9]`
- `[8/8]` → `[8/9]`

---

## 7. Security Considerations

### 7.1 No Secrets Required

`nix flake check --no-build --impure` on a public repository requires no Cachix tokens, no FlakeHub accounts, and no private binary caches. All dependencies are fetched from:
- `cache.nixos.org` (public, unauthenticated)
- `github.com` (flake inputs via GitHub archive tarballs, rate-limited by `GITHUB_TOKEN`)

`GITHUB_TOKEN` is the standard automatic token GitHub injects into every Actions workflow (`secrets.GITHUB_TOKEN`). It is used only to avoid rate limiting for GitHub API calls made by the Nix daemon when fetching flake inputs. No special permissions or manual secret configuration is needed.

### 7.2 Stub File Safety

The stub `/etc/nixos/hardware-configuration.nix`:
- Contains only `{ ... }: { }` — no secrets, no real hardware identifiers
- Is created at runtime in the ephemeral GitHub Actions runner environment
- Is NOT committed to the repository
- Is different from any real host's hardware configuration — no deployment risk

### 7.3 Minimal Permissions

The CI workflow uses `permissions: contents: read` — the minimum required. It does NOT request `contents: write`, `id-token: write`, or any other elevated permissions.

### 7.4 Pinned Action Versions

All GitHub Actions must use pinned major version tags:
- `actions/checkout@v4`
- `cachix/install-nix-action@v31`
- `actions/cache@v4`

These are maintained tags that receive security patches automatically (the major tag is periodically updated to point to the latest patch). Pinning to major versions is the standard practice for GitHub Actions.

---

## 8. Implementation Checklist

### Phase 2 Implementation Tasks

- [ ] Create `.github/workflows/ci.yml` with exact YAML from Section 5.3
- [ ] Update `scripts/preflight.sh`:
  - [ ] Add CHECK 0 block from Section 6.2 after the header section
  - [ ] Update all check counters from `[N/8]` to `[N/9]` per Section 6.3
  - [ ] Verify the early-exit section after the hard checks still references correct check numbers

### Phase 3 Review Checklist

- [ ] `ci.yml` YAML is valid (no syntax errors)
- [ ] `ci.yml` triggers on `push` to `main` and on `pull_request`
- [ ] `ci.yml` uses `cachix/install-nix-action@v31` consistently with `update-flake-lock.yml`
- [ ] Stub `hardware-configuration.nix` creates a valid minimal Nix file
- [ ] `nix flake check --no-build --impure --show-trace` is the exact command used
- [ ] `hardware-configuration.nix` git-tracking check is present as HARD failure
- [ ] `system.stateVersion` check is present as HARD failure
- [ ] `preflight.sh` CHECK 0 exits with code 1 when Nix is absent
- [ ] `preflight.sh` provides Determinate Systems install command
- [ ] `preflight.sh` provides `nix-daemon.sh` sourcing instruction
- [ ] All preflight check counters updated from `[N/8]` to `[N/9]`
- [ ] No `hardware-configuration.nix` stub is committed to the repository

---

## 9. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| `nix flake check` timeout on first run (large nixpkgs fetch) | Medium | `actions/cache@v4` with flake.lock key reduces subsequent runs; 6-hour job timeout is sufficient |
| Stub hardware-configuration.nix causes false positive for some module option that REQUIRES hardware info | Low | The NixOS module system uses `lib.mkDefault` for hardware options; empty hardware config is a valid state |
| `--no-build` misses build-time errors (e.g., broken package in system packages) | Medium-Low | Accepted trade-off. Full closure validation requires a live NixOS host. CI catches evaluation errors; deploy-time catches build errors. Document this clearly. |
| Stateless configs (with disko) fail to evaluate with stub hardware config | Low | disko module defines its own `fileSystems` via disko options; it does not require hardware `fileSystems` from hardware-config. Stub is compatible. |
| GitHub Actions cache fills storage quota | Low | Monitor with first-run metrics. The 10 GB GitHub cache quota should be sufficient. Cache eviction is automatic after 7 days of no access. |

---

## 10. Summary

### What Gets Created

**`.github/workflows/ci.yml`** — A new GitHub Actions workflow that:
1. Triggers on every push to `main` and every pull request
2. Installs Nix 2.34.5 via `cachix/install-nix-action@v31`
3. Caches the Nix store keyed on `flake.lock` hash for fast subsequent runs
4. Creates a minimal stub `/etc/nixos/hardware-configuration.nix`
5. Runs `nix flake check --no-build --impure --show-trace` — evaluating all 16 NixOS configurations and all nixosModules outputs without building any packages
6. Enforces git hygiene: `hardware-configuration.nix` not tracked, `system.stateVersion` present

### What Gets Modified

**`scripts/preflight.sh`** — A new CHECK 0 block that:
1. Detects whether `nix` is installed before attempting any Nix commands
2. Provides a clear, actionable error message with the Determinate Systems install command for WSL2/Linux users
3. References the CI workflow as the automated alternative

### What Stays the Same

- All `flake.nix` configuration
- All NixOS module files
- `update-flake-lock.yml` (separate concern, no changes needed)
- The 8 existing preflight checks and their logic

### Automated Validation After This Change

| Trigger | What Runs | What It Catches |
|---------|-----------|----------------|
| Every `git push` to `main` | `ci.yml` via GitHub Actions | All Nix evaluation errors across all 16 configurations |
| Every pull request | `ci.yml` via GitHub Actions | Same as above |
| Manual preflight (with Nix installed) | `scripts/preflight.sh` | Same + formatting + secrets scan + flake.lock freshness |
| Deploy to live host | `nixos-rebuild switch` | Build errors + runtime config issues |

---

*Spec file:* `c:\Projects\vexos-nix\.github\docs\subagent_docs\ci_automation_spec.md`  
*Files to create:* `.github/workflows/ci.yml`  
*Files to modify:* `scripts/preflight.sh`
