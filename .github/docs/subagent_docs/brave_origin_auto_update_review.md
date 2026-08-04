# Brave Origin Auto-Update — Review & QA

**Feature name:** `brave_origin_auto_update`
**Spec:** `.github/docs/subagent_docs/brave_origin_auto_update_spec.md`
**Date:** 2026-08-04
**Result:** **PASS**

---

## 1. Files Reviewed

| File | Change |
|------|--------|
| `.github/workflows/update-brave-origin-weekly-thursday.yml` | new — 5-step scheduled updater |
| `pkgs/brave-origin/default.nix` | header comment only: `nix hash to-sri` → `nix hash convert`, plus pointer to the workflow |

No other file was touched. `git diff --stat -- 'configuration-*.nix'` is empty.

---

## 2. Specification Compliance

| Spec section | Implemented | Notes |
|---|---|---|
| §3.1 stable-only discovery, 2 pages, `GITHUB_TOKEN` | ✅ | regex anchored on a digit after `brave-origin-` |
| §3.2 `nix-prefetch-url --unpack` + `nix hash convert` | ✅ | deprecated `to-sri` avoided |
| §3.3 anchored in-place `sed` of `version` + `hash` | ✅ | plus a post-rewrite grep guard not in the spec — a strict improvement |
| §3.4 build-verify before commit | ✅ | `nix build --impure --no-link` via overlay + `builtins.getFlake` |
| §3.5 direct commit to `main`, bot identity, scoped `git add` | ✅ | matches the three existing update workflows |
| §4 Thursday 05:00 UTC, naming convention | ✅ | `0 5 * * 4` |
| §8 no `packages` flake output added; no version bump in this change | ✅ | pin still 1.91.171; first workflow run performs the bump |

No deviations.

---

## 3. Build & Command Validation

Executed in order. **No FORBIDDEN COMMAND was run** — no `nix flake check`, no
`nixos-rebuild switch`, no `nixos-rebuild boot`, and no git write operation.

| # | Check | Result |
|---|---|---|
| 1 | `nix flake show --impure` | ✅ exit 0, all outputs enumerated through `nixosModules.vanillaBase` |
| 2 | `sudo nixos-rebuild dry-build --flake .#vexos-desktop-{amd,nvidia,vm}` | ⚠️ **not runnable in this environment** — `sudo` refuses under the `no_new_privileges` flag (not a repo fault; reproduced with sandboxing disabled) |
| 3 | Fallback per CLAUDE.md Test Commands: `nix eval --impure ".#nixosConfigurations.<v>.config.system.build.toplevel.drvPath"` for `vexos-desktop-amd`, `-nvidia`, `-vm` | ✅ all exit 0, three distinct `.drv` paths produced |
| 4 | Workflow YAML parses; step names / cron / permissions as intended (`yq -e`) | ✅ |
| 5 | `sed` rewrite logic dry-run on a scratch copy of the package | ✅ `version` line rewritten, `url` line correctly untouched (interpolates `${version}`), header comment untouched, guard did not trip |
| 6 | Prefetch chain against the real 1.93.129 asset | ✅ `sha256-BjFZ2bcjuY7AjX20FKp4nnUlNun0zhcVnT8WQRZuB2o=` |
| 7 | Workflow's build-verify expression run verbatim | ✅ → `/nix/store/bj2c51d2yyli37h3d9150njn3p3ccvc8-brave-origin-1.91.171` |
| 8 | `git ls-files hardware-configuration.nix` | ✅ empty |
| 9 | `system.stateVersion` in all `configuration-*.nix` | ✅ all six still `"25.11"`, no diff |
| 10 | New flake inputs / `follows` | ✅ N/A — `flake.nix` unmodified |

On check 2: the mandated `dry-build` is environmentally unavailable, not failing.
Check 3 is the substitute CLAUDE.md itself designates ("forces full evaluation without
building; used in CI; equivalent to `nix flake check --no-build` for a single target"),
and it exercises the same evaluation path. Check 7 additionally builds the affected
package for real, which `dry-build` would not have done.

Server / stateless / htpc variants were not additionally evaluated: the change touches no
module under `modules/server/`, no stateless or htpc module, and the only `pkgs/` edit is
a comment. `vexos.brave-origin` is installed solely by `modules/packages-desktop.nix`.

---

## 4. Findings

### CRITICAL
None.

### RECOMMENDED
None outstanding — the two candidates found during review were addressed in Phase 2 as
written:

1. Post-`sed` verification guard, so a silently-missed substitution fails the job rather
   than committing a half-rewritten derivation.
2. `timeout-minutes: 30`, bounding a hung download (the other update workflows do not
   download ~200 MB and so do not need one).

### OBSERVATIONS (no action)

- **O-1 — `set -euo pipefail` interaction with `|| true`.** Verified reasoning: the
  discovery subshell inherits `-e`/`pipefail`, so a failed `curl`, or a `grep` matching
  nothing, makes the substitution empty rather than aborting the job; the explicit
  empty-string guard then exits 0 with a warning. Degradation is a clean no-op, matching
  the `warning: … skipping` idiom in `update-container-images-weekly-wednesday.yml`.
- **O-2 — concatenated JSON pages into one `jq`.** `jq` consumes a stream of JSON values,
  so two `[...]` documents piped together are handled correctly. Confirmed against live
  API data during Phase 1 (returned `1.93.129`).
- **O-3 — pre-existing dead code.** None found in the touched files. Not removing
  anything.

---

## 5. Best Practices, Consistency, Security

- **Consistency:** step naming, bot identity `github-actions[bot]`, `actions/checkout@v6`,
  `cachix/install-nix-action@v31`, `permissions: contents: write`, and the
  direct-commit-to-`main` model all mirror the three existing update workflows. Filename
  follows the established `update-<thing>-<cadence>-<day>.yml` convention.
- **Module Architecture Pattern (Option B):** not applicable — no NixOS module was added
  or modified. No new `lib.mkIf` guard was introduced anywhere.
- **Security:**
  - No hardcoded secrets; only the automatic `GITHUB_TOKEN`, used as a read-only API
    bearer and for `install-nix-action`.
  - No expression-injection surface: the one interpolated output,
    `steps.check.outputs.version`, is constrained by the discovery regex to
    `[0-9]+\.[0-9]+\.[0-9]+` before it ever reaches the commit message.
  - `permissions:` is minimal — `contents: write` only, no `pull-requests` or `packages`.
  - Supply-chain posture is *improved*: the fixed-output `hash` still pins the exact
    upstream artifact, and the build gate means an unverifiable or altered artifact fails
    the job instead of landing on `main`.
- **Performance:** one weekly job; `--no-link`, single package, single system. Weekly
  rather than daily because Brave's stable cadence is roughly weekly and the build step
  is not free (spec §4).
- **API currency:** `nix hash convert` replaces the form Nix 2.34 explicitly flags as
  deprecated; both Actions are already at the newest versions in use in this repo.
  Context7 not applicable — no new external library integration (CLAUDE.md exemption).

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 98% | A |
| Functionality | 100% | A |
| Code Quality | 97% | A |
| Security | 100% | A |
| Performance | 96% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

---

## 7. Verdict

**PASS** — no CRITICAL or outstanding RECOMMENDED issues. Phase 4 refinement is not
triggered. Proceed to Phase 6 preflight.
