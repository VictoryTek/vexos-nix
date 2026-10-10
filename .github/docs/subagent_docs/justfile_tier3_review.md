# Justfile Tier 3 (Structure) — Review

Phase 3 review of Tier 3 from `justfile_review_spec.md` (D1–D5 + preflight; see "Tier 3 —
decisions"). Baseline: HEAD `ce977fa` (Tier 2).

Modified: `justfile`, `CLAUDE.md`, `modules/packages-common.nix`, `modules/impermanence.nix`,
`scripts/preflight.sh`, spec. New: `just/{system,admin,vpn,features,ai,storage,cache,server,server-enable}.just`,
`just/lib.sh`.

## Specification compliance

| Item | Status | Evidence |
|---|---|---|
| D5 `just_executable()` | Done | 37 call sites via `_just`; a renamed justfile run from another cwd works (HEAD: "no justfile found") |
| D4 quoting + `[arg]` | Done | 0 raw parameter interpolations remain; `$(touch …)` payload executed on HEAD, inert now; 25 recipes patterned; multi-word args reach storage scripts intact |
| D2 recipe helpers | Done | 8 AI guards → `_require-ai`; `_require-nixos`; 4 → `_require-known-service`; 2 → `_confirm-typed`; 2 pickers → `_pick-target` (tested: headless/legacy NVIDIA, names, partial input, EOF) |
| D2 `just/lib.sh` | Done | 14 sed blocks + 3 template copies replaced; sandbox harness: 12 service enables + feature enable + plex-pass/service disable evaluate identically to HEAD; special-character repo path now works (HEAD: `sed: unknown option to 's'`, half-written file) |
| D3 `import` split | Done | full `--dump` (recipes, assignments, settings) and `--list --unsorted` identical before/after the move; no original line lost (9 section dividers dropped by design) |
| D3 deployment | Done | `/etc/nixos/just` via `environment.etc`; stateless relink; a simulated store-symlinked `/etc/nixos` runs list, menus and all 93 recipes |
| D1 tables | Done (scoped) | `_service_runtime` generated from the old cases; units + URLs identical for all 56 names + unknown fallback |
| Preflight stage 11 | Done | passes on repo; injected drift (extra name, missing runtime row) fails with readable diffs |

## Contract (VexPortal)
- Signatures and visibility vs HEAD: only five new **private** helpers.
- `_feature_names` and `_service_catalog`: identical values.
- VexPortal drift rule against its `catalog.toml`: 0 Unlisted, 0 Missing, 0 parameter-order mismatches.
- `[arg]` patterns are supersets of VexPortal's `slug`/`hostname`/`ssh-target`/`nixos-version` validators and choice lists.

## Quality
- Shellcheck `-S warning`: all 55 shebang recipes + `just/lib.sh` + `scripts/preflight.sh` clean.
  This surfaced and fixed a comment in `deploy` that was parsed as a malformed shellcheck
  directive, which had silently disabled linting of that recipe.
- No new `lib.mkIf`; module edits are additive (`environment.etc` entry, activation relink).

## Build validation
| Check | Result |
|---|---|
| eval desktop-amd / -nvidia / -vm | PASS |
| eval stateless-amd / htpc-amd (impermanence + packages-common touched) | PASS |
| eval server-amd / headless-server-amd | pre-existing host-specific ZFS `networking.hostId` assertion only (identical at HEAD); the new `etc."nixos/just"` evaluates there |
| `sudo nixos-rebuild dry-build` | not runnable here (no non-interactive sudo) |
| `scripts/preflight.sh` | **requires `just/` to be staged**: the flake is `git+file`, which cannot see untracked files |

## Scores

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 92% | A- |
| Best Practices | 94% | A |
| Functionality | 96% | A |
| Code Quality | 94% | A |
| Security | 98% | A+ |
| Performance | 100% | A+ |
| Consistency | 95% | A |
| Build Success | 95% | A |

**Overall Grade: A (95%)**

**Result: PASS** (pending preflight after staging)
