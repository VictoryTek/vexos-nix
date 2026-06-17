# Spec: Split Flake Update Schedule — Stable Daily / Unstable Weekly

**Feature:** `flake_update_split_schedule`
**Date:** 2026-06-16
**Status:** Ready for implementation

---

## 1. Current State Analysis

### 1.1 `update-flake-lock.yml` — current behaviour

- Triggers: **daily** at 04:00 UTC **and on every push to `main`**
- Command: `nix flake update` — updates **all inputs** unconditionally
- Inputs updated: `nixpkgs` (26.05 stable), `nixpkgs-unstable`, `home-manager`,
  `impermanence`, `sops-nix`, `up`, `proxmox-nixos`, `vexboard`

### 1.2 Packages that consume `nixpkgs-unstable`

Only three production packages draw from `pkgs.unstable.*`:
- `pkgs.unstable.vscode-fhs` — `home-desktop.nix`
- `pkgs.unstable.papermc` — `modules/server/papermc.nix`
- `pkgs.unstable.seerr` — `modules/server/seerr.nix`

### 1.3 Root cause of frequent cache misses

`nixpkgs-unstable` is bumped to HEAD daily by CI. Hydra lags 6–24 hours behind
nixpkgs-unstable HEAD. Because the installer runs `flake update` against
vexos-nix's latest commit — which inherits the just-bumped `flake.lock` —
users consistently land in the Hydra lag window.

The `push` trigger compounds this: every commit to `main` re-bumps all inputs,
meaning the lock can be refreshed multiple times per day.

### 1.4 Divergence from original spec

The original `flake_lock_autoupdate_spec.md` called for weekly schedule and
nixpkgs-only updates. The implementation drifted to daily all-inputs + push
trigger. This spec corrects that drift with a pragmatic split:
- Stable nixpkgs: daily (Hydra always keeps up with 26.05 stable)
- Unstable + all other inputs: weekly (reduces Hydra lag window by ~85%)

---

## 2. Problem Definition

With daily all-input updates and `nixpkgs-unstable` pinned to today's HEAD,
every package that bumped in the last 24 hours is potentially uncached. For
a repo that gets multiple commits per day, the push trigger means the window
is effectively always open.

By updating `nixpkgs-unstable` only weekly, the pin is at most 7 days old.
Hydra builds any given package within 6–24 hours. So outside a ~1-day window
per week, all unstable packages are guaranteed to be cached.

---

## 3. Proposed Solution

### 3.1 Workflow restructure

**Two schedule triggers in one workflow, one job with conditional step:**

| Trigger | Cron | What it updates |
|---------|------|-----------------|
| Daily (Tue–Sun) | `0 4 * * 2-7` | `nixpkgs` only (stable 26.05) |
| Weekly (Monday) | `0 4 * * 1` | All inputs (`nix flake update`) |
| `workflow_dispatch` | manual | All inputs |

On Mondays, only the weekly trigger fires (the daily trigger is scoped to
Tue–Sun). One run, one commit.

**Remove the `push` trigger entirely.** It serves no useful purpose: CI
(`ci.yml`) already validates every push. Re-bumping all flake inputs on every
push to `main` only increases churn and widens the Hydra lag window.

### 3.2 Installer improvement — pin age in cache miss message

When the cache check blocks, extract the `lastModified` Unix timestamp of the
`nixpkgs-unstable` node from `/etc/nixos/flake.lock` using `python3` (always
available on NixOS). Compute age in hours. If age < 48 hours, append a targeted
retry estimate to the abort message.

`python3` is used in preference to `jq` because `jq` is not guaranteed present
on a minimal NixOS install. `python3 -c` with stdlib `json` module is always
available.

---

## 4. Implementation

### 4.1 `.github/workflows/update-flake-lock.yml` — full replacement

```yaml
name: Update flake inputs

on:
  schedule:
    - cron: '0 4 * * 2-7'  # Tue–Sun: stable nixpkgs only
    - cron: '0 4 * * 1'    # Monday: all inputs (unstable + stable + others)
  workflow_dispatch:         # Manual: all inputs

permissions:
  contents: write

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 1

      - uses: cachix/install-nix-action@v31
        with:
          github_access_token: ${{ secrets.GITHUB_TOKEN }}

      - name: Update nixpkgs stable (daily)
        run: nix flake update nixpkgs

      - name: Update all other inputs (weekly / manual)
        if: github.event.schedule == '0 4 * * 1' || github.event_name == 'workflow_dispatch'
        run: nix flake update nixpkgs-unstable home-manager impermanence sops-nix up proxmox-nixos vexboard

      - name: Commit updated flake.lock
        run: |
          if git diff --quiet flake.lock; then
            echo "flake.lock unchanged — nothing to commit."
            exit 0
          fi
          git config user.name  "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add flake.lock
          git commit -m "chore: update flake inputs"
          git push
```

### 4.2 `scripts/install.sh` — pin age in cache miss message

After the `BLOCKING` check on line ~450, before the `exit 1`, insert a block
that reads `nixpkgs-unstable`'s `lastModified` from `/etc/nixos/flake.lock`
and computes age in hours. If age < 48 hours, print a targeted retry estimate.

```bash
# Compute nixpkgs-unstable pin age for a targeted retry hint
UNSTABLE_AGE_HINT=""
if command -v python3 >/dev/null 2>&1 && [ -f /etc/nixos/flake.lock ]; then
  UNSTABLE_AGE_HINT=$(python3 - <<'PYEOF'
import json, time, sys
try:
    with open("/etc/nixos/flake.lock") as f:
        lock = json.load(f)
    # nixpkgs-unstable may be nested under vexos-nix's inputs
    nodes = lock.get("nodes", {})
    ts = None
    for name, node in nodes.items():
        if "unstable" in name and "locked" in node:
            ts = node["locked"].get("lastModified")
            break
    if ts:
        age_h = (time.time() - ts) / 3600
        if age_h < 48:
            retry_h = max(1, int(24 - age_h + 0.5))
            print(f"nixpkgs-unstable was pinned {age_h:.0f}h ago — this is likely a Hydra cache lag.\nRetry in ~{retry_h}h once Hydra catches up.")
except Exception:
    pass
PYEOF
  )
fi

if [ -n "$UNSTABLE_AGE_HINT" ]; then
  echo ""
  echo -e "${CYAN}${UNSTABLE_AGE_HINT}${RESET}"
fi
```

---

## 5. Files Modified

| File | Change |
|------|--------|
| `.github/workflows/update-flake-lock.yml` | Replace entire file |
| `scripts/install.sh` | Add pin-age hint block after BLOCKING check |

---

## 6. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `github.event.schedule` string matching is fragile | Exact cron string must match; double-checked below |
| Stable nixpkgs skipped on Mondays | Not a risk — weekly run updates stable too |
| `python3` not available | Wrapped in `command -v` guard; hint is optional |
| `flake.lock` node name for unstable may vary | Loop searches for any node with "unstable" in name |

**Cron string verification:**
- `github.event.schedule` equals the exact cron string from the `schedule` block.
- The weekly step checks `github.event.schedule == '0 4 * * 1'` which matches
  the Monday cron exactly.

---

## 7. Implementation Steps

1. Replace `.github/workflows/update-flake-lock.yml`
2. Insert pin-age hint block in `scripts/install.sh` after the `BLOCKING` check
3. Run `nix flake show --impure` — validates flake structure unchanged
4. Run preflight
