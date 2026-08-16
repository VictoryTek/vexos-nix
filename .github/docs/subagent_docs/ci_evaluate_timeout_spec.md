# CI "evaluate" job intermittent 20-minute timeout

## Current state analysis

`.github/workflows/ci.yml` — `evaluate` job (line 69):

- `timeout-minutes: 20` at the job level (line 73).
- Matrix of 6 groups, 5 `nixosConfigurations` each (30 total).
- Per-config eval step (lines 187-210) wraps each config in `timeout 12m nix eval --impure
  ...drvPath`, looping through all 5 configs in the group sequentially within the same job.
- Comment at line 64-66 states the design intent: "6 groups × ~5 min each" — implying an
  assumed ~4 min/config average, giving headroom under the 20-minute job ceiling.
- Comment at line 190-192 already documents one adjustment: the per-config timeout was
  raised from 8m to 12m specifically because `nvidia-legacy535` configs evaluate slower
  (larger NVIDIA driver closure).
- Repo has an automated daily `chore: update flake inputs (daily)` commit (visible in git
  log), which bumps `flake.lock` — this changes the Nix store cache's `primary-key` (line
  145, `hashFiles('flake.lock')`), guaranteeing a cache-key miss on the primary key for
  every group on the day of a bump. The `restore-prefixes-first-match` fallback (line 146)
  restores an older, now-partially-stale cache, so at least some fetching/re-evaluation
  against the new nixpkgs revision happens cold that day.

## Problem definition

Job-level ceiling (20 min) doesn't have headroom for the per-config allowance actually
budgeted (12 min × 5 configs = up to 60 min worst case), plus fixed per-job overhead
(disk cleanup, Nix install, cache restore/save — several minutes before any `nix eval`
even starts). On days where eval runs colder than the ~4min/config design assumption
(most visibly right after the daily automated flake-input bump), whichever group happens
to draw the slower runner/network that day exceeds the 20-minute job ceiling — even though
no single config hits its own 12-minute per-config cap. This presents as an intermittent,
seemingly random failure across different role groups rather than a consistent one.

## Proposed solution architecture

Raise `timeout-minutes` on the `evaluate` job from `20` to `35`. This directly closes the
gap between the job ceiling and the actual worst-case per-config budget already coded into
the workflow (5 × 12m = 60m theoretical max; 35m gives comfortable real-world headroom over
the ~20-25m typical warm-cache case while still bounding runaway jobs well under the
worst-case ceiling). Chosen over restructuring the matrix (splitting into smaller groups)
per user preference — smaller groups would also fix this but add more concurrent runner
jobs/overhead; a timeout bump is the minimal, lowest-risk change that matches the existing
design intent instead of restructuring it.

## Implementation steps

1. `.github/workflows/ci.yml` line 73: change `timeout-minutes: 20` to `timeout-minutes: 35`
   under the `evaluate` job.
2. Update the explanatory comment at lines 64-66 to reflect the new ceiling and why (avoid
   leaving a stale "~5 min each" rationale that no longer matches the configured timeout).

No other files need to change. No new dependencies; this is a CI workflow config change
only, not a Nix/NixOS module change — Context7 lookup not applicable (no external library
API involved).

## Configuration changes

`timeout-minutes: 20` → `timeout-minutes: 35` on the `evaluate` job in
`.github/workflows/ci.yml`. No changes to any `.nix` file, no changes to `flake.lock`.

## Risks and mitigations

- **Risk**: A job that's genuinely hung (not just slow) now takes up to 35 minutes to be
  killed instead of 20, costing more CI minutes on true failures.
  **Mitigation**: The per-config `timeout 12m` (line 197) already bounds any single hung
  `nix eval` invocation; the loop still fails fast (`exit 1` after the first failed config,
  line 207-210) rather than continuing to try all 5 — a genuinely hung single config is
  still caught and reported within ~12 minutes, not 35. The 35m job ceiling mainly protects
  against the *cumulative* slow-but-not-hung case, not a true hang.
- **Risk**: Masking a real, worsening performance regression instead of investigating it.
  **Mitigation**: This is a budget-headroom fix for the documented, already-accepted
  per-config variance (nvidia-legacy535 already needed a bump for the same reason); it does
  not change what's being validated, only how much time the CI infrastructure allows for a
  correctly-designed-but-tightly-budgeted job. No `.nix` build/eval commands validated as
  part of this change since none are affected — this is purely a workflow YAML edit.
