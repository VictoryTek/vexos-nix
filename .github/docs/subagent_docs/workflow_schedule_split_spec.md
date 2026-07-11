# Spec: Split Scheduled Update Workflows into Daily / Weekly-Monday / Weekly-Wednesday

**Feature:** `workflow_schedule_split`
**Date:** 2026-07-11
**Status:** Ready for implementation

---

## 1. Current State Analysis

Two scheduled workflows exist today:

### 1.1 `update-flake-lock.yml`
- `name:` **"Update flake inputs"**
- Triggers:
  - `cron: '0 4 * * 0,2-6'` (Tue–Sun) — updates `nixpkgs up vexboard` only
  - `cron: '0 4 * * 1'` (Monday) — updates all other inputs (`nixpkgs-unstable home-manager impermanence sops-nix proxmox-nixos`) via a conditional step
  - `workflow_dispatch` — always takes the Monday/full path (the `if` condition matches on `workflow_dispatch` unconditionally)
- Single job, single file. Manually triggering this workflow always runs the full (unstable-inclusive) update — there is no way to manually run just the daily subset.

### 1.2 `update-container-images.yml`
- `name:` **"Update container image pins"**
- Trigger: `cron: '0 4 * * 3'` (Wednesday only) + `workflow_dispatch`
- Already single-purpose (weekly only), but its filename/name don't signal cadence at a glance, same as the other file.

### 1.3 Problem

The user wants to manually re-run the **daily** stable-only update (e.g. after landing a project change) to test it, without accidentally dragging in the Monday-only unstable bump. Because daily and weekly-Monday logic live in one workflow file with one `workflow_dispatch` entry point, there is no way to trigger "daily only" from the Actions UI/`gh workflow run` — it always runs both steps.

Additionally, none of the three schedules (daily, weekly-Monday, weekly-Wednesday) are identifiable by filename or workflow name without opening the file and reading the cron.

---

## 2. Proposed Solution

Split into **three** independent workflow files, each with its own schedule and its own `workflow_dispatch`, so a manual run only ever executes that one cadence's job. Each file gets a `name:` that states cadence and scope explicitly, so the Actions UI list is self-explanatory.

| File | `name:` | Cron | Scope |
|---|---|---|---|
| `update-flake-lock-daily.yml` | `Flake Update — Daily (stable inputs)` | `0 4 * * 2-6,0` (Tue–Sun) | `nixpkgs up vexboard` |
| `update-flake-lock-weekly-monday.yml` | `Flake Update — Weekly Monday (all inputs)` | `0 4 * * 1` | `nixpkgs-unstable home-manager impermanence sops-nix proxmox-nixos` (unstable-only inputs; does **not** re-touch `nixpkgs up vexboard` — those are covered by the daily workflow) |
| `update-container-images-weekly-wednesday.yml` | `Container Image Pins — Weekly Wednesday` | `0 4 * * 3` (unchanged) | OCI image pin bumps (logic unchanged) |

Rationale for the Monday workflow's scope: today's single-file version updates *all* inputs including `nixpkgs up vexboard` again on Monday, redundant with the same-day-if-Tue-Sun-ran daily job. Splitting into two independent triggers means Monday no longer needs to re-cover the daily-scoped inputs — the daily workflow already runs Mon–Sun with no gap (`2-6,0` = Tue,Wed,Thu,Fri,Sat,Sun; Monday's *daily* inputs are covered by explicitly adding Monday too, since removing Monday from the daily cron would create a gap). Correction: to avoid a gap in the stable-input update cadence, the daily cron must run **every day including Monday** (`0 4 * * *`), and the weekly-Monday workflow only adds the extra unstable-inclusive inputs on top, same as today's conditional-step behavior. This preserves current behavior exactly, just split into two files.

Each workflow keeps its own full step sequence (checkout, install Nix, update, conditional commit) — no shared/reusable workflow, since each is small (~25 lines) and self-contained clarity is the explicit goal here (avoids indirection through `workflow_call`).

No behavior change to *what* gets updated or *when* the scheduled runs fire — only:
1. Manual (`workflow_dispatch`) runs become scoped per-file (daily dispatch → daily-only; weekly-Monday dispatch → unstable-inclusive inputs only; weekly-Wednesday unchanged).
2. Filenames and `name:` fields make cadence unambiguous.

---

## 3. Implementation Steps

1. Create `.github/workflows/update-flake-lock-daily.yml`:
   - `cron: '0 4 * * *'` (every day) + `workflow_dispatch`
   - Single step: `nix flake update nixpkgs up vexboard`
   - Commit-if-changed step, same as today
2. Create `.github/workflows/update-flake-lock-weekly-monday.yml`:
   - `cron: '0 4 * * 1'` (Monday only) + `workflow_dispatch`
   - Single step: `nix flake update nixpkgs-unstable home-manager impermanence sops-nix proxmox-nixos`
   - Commit-if-changed step, same as today
3. Delete `.github/workflows/update-flake-lock.yml` (superseded by the two files above)
4. Rename `.github/workflows/update-container-images.yml` → `.github/workflows/update-container-images-weekly-wednesday.yml`, update its `name:` field to `Container Image Pins — Weekly Wednesday`. No logic changes.
5. Verify no other file references the old `update-flake-lock.yml` / `update-container-images.yml` filenames in a way that would break (checked: only historical docs under `.github/docs/subagent_docs/` reference them — informational, not functional; no `ci.yml`, script, or README dependency on these filenames).

---

## 4. Files Modified

| File | Change |
|---|---|
| `.github/workflows/update-flake-lock-daily.yml` | New |
| `.github/workflows/update-flake-lock-weekly-monday.yml` | New |
| `.github/workflows/update-flake-lock.yml` | Deleted (replaced by the two files above) |
| `.github/workflows/update-container-images.yml` → `.github/workflows/update-container-images-weekly-wednesday.yml` | Renamed, `name:` field updated |

---

## 5. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Renaming `update-container-images.yml` starts a "new" workflow in the Actions UI (old run history stays under the old, now-removed, workflow entry) | Cosmetic only — no functional impact; flagged here for visibility since it affects Actions UI history grouping |
| Duplicated boilerplate (checkout/install Nix/commit step) across the two new flake-lock files | Accepted tradeoff — each file stays small and independently readable per the user's stated goal (no guessing what a workflow does); a `workflow_call` shared workflow was considered and rejected as unnecessary indirection for two ~25-line files |
| Losing the previous single-file conditional logic that guaranteed exactly one commit per day | Each file independently checks `git diff --quiet flake.lock` before committing, same as today — no change in commit behavior |

---

## 6. Verification

- `nix flake show --impure` (workflow-only change; flake structure unaffected, run for sanity)
- YAML validity of new/changed workflow files
- `git ls-files hardware-configuration.nix` unaffected (no change)
- No `nixosConfigurations` or `configuration-*.nix` touched — Nix dry-build validation not applicable to this change (GitHub Actions YAML only)
