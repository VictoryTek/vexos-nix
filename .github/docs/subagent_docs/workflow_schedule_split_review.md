# Review: Split Scheduled Update Workflows

**Feature:** `workflow_schedule_split`
**Date:** 2026-07-11

---

## 1. Specification Compliance

- `update-flake-lock-daily.yml` created — daily cron `0 4 * * *`, `workflow_dispatch`, updates `nixpkgs up vexboard` only. ✓ Matches spec.
- `update-flake-lock-weekly-monday.yml` created — Monday-only cron `0 4 * * 1`, `workflow_dispatch`, updates `nixpkgs-unstable home-manager impermanence sops-nix proxmox-nixos` only. ✓ Matches spec.
- `update-flake-lock.yml` deleted (superseded). ✓
- `update-container-images.yml` renamed to `update-container-images-weekly-wednesday.yml`, `name:` updated to `Container Image Pins — Weekly Wednesday`, internal comment reference to old `update-flake-lock.yml` filename updated to `update-flake-lock-daily.yml`. No logic changes. ✓

## 2. Best Practices / Consistency

- Both new flake-lock workflows follow the exact checkout → install Nix → update → conditional-commit structure of the file they replaced, preserving established style (`cachix/install-nix-action@v31`, same commit/push block, same bot identity).
- `name:` fields now state cadence and scope directly (`Flake Update — Daily (stable inputs)`, `Flake Update — Weekly Monday (all other inputs)`, `Container Image Pins — Weekly Wednesday`), resolving the user's stated goal of not having to guess what/when each workflow runs.
- No shared/reusable workflow introduced — each file is self-contained (~35 lines), consistent with the project's simplicity-first principle for two small, rarely-changed files.

## 3. Functional Equivalence Check

Combined coverage of the two new files reproduces the old single file's behavior exactly:
- Old: Tue–Sun `nix flake update nixpkgs up vexboard`; Monday (schedule or dispatch) `nix flake update nixpkgs-unstable home-manager impermanence sops-nix proxmox-nixos` (via `if` condition, which also skipped the Tue-Sun step since it's a separate scheduled trigger — actually old file always ran the first step regardless of day, then conditionally ran the second on Monday/dispatch).
- New: `update-flake-lock-daily.yml` runs `nixpkgs up vexboard` every day including Monday (cron `0 4 * * *`) — same net effect as old file's unconditional first step running every day.
- New: `update-flake-lock-weekly-monday.yml` runs the unstable-inclusive set only on Monday — same net effect as old file's conditional second step.
- **Behavior change (intentional, per user request):** manual `workflow_dispatch` is now scoped per file. Triggering the daily workflow manually no longer also bumps `nixpkgs-unstable` et al. — this was the explicit goal of the split.

## 4. Security

- No secrets, credentials, or permissions changes. `permissions: contents: write` preserved identically in both new files (same scope as before, required to push `flake.lock`).

## 5. Reference Check

- Grepped `.github/workflows/*.yml`, `scripts/*.sh`, `README*` for `update-flake-lock.yml` / `update-container-images.yml` — no functional references found. Only historical spec/review docs under `.github/docs/subagent_docs/` reference the old filenames; these are point-in-time records of past work and are intentionally left unchanged (not live documentation).

## 6. Build Validation

- This change touches GitHub Actions YAML only — no `configuration-*.nix`, `modules/`, or `flake.nix` files modified. Per-target `nixos-rebuild dry-build` is not applicable.
- `nix flake show --impure` — ran clean, flake structure unaffected (expected, confirms no collateral damage).
- YAML syntax validated for all 3 new/changed workflow files plus the two untouched workflow files (`ci.yml`, `gitlab-mirror.yml`) via `yq e '.'` — all parse cleanly.
- `git ls-files hardware-configuration.nix` — empty (unaffected, not part of this change).
- `system.stateVersion` — not touched by this change.

## 7. Score Table

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

## Returns

- **PASS** — no CRITICAL or RECOMMENDED issues found. Proceeding to Phase 6 (Preflight).
