# M-36 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-36_attic_push_recipe_spec.md`

**Process note:** the user's own follow-up question ("is the wiring correct,
or does it need work?") reshaped this item mid-investigation — verified both
the client and server Attic wiring directly against upstream `atticd`
module source before concluding neither needed changes, then scoped the
actual deliverable down from "CI + secret" to a local `just` recipe per the
user's confirmed preference.

## Modified Files

- `justfile` — new `[group('Binary Cache')]`, `attic-push [cache]` recipe.
- `modules/server/attic.nix` — one-line pointer comment to the new recipe.

## Review Findings

1. **Specification Compliance** — matches the user-confirmed scope: no CI
   workflow, no repo secret; a local recipe usable the moment any Attic
   cache is configured and logged into.
2. **Best Practices** — verified client (`modules/nix.nix`) and server
   (`modules/server/attic.nix`) Attic wiring directly against the upstream
   `atticd` NixOS module source (assertion placement, `StateDirectory`
   matching the default `dataDir`) rather than assuming correctness — both
   confirmed already correct, so zero functional changes were made there.
3. **Consistency** — the recipe follows the justfile's existing
   `#!/usr/bin/env bash` / `set -euo pipefail` inline-script convention and
   `[group(...)]` attribute style used throughout the file.
4. **Maintainability** — the recipe's per-package try/catch loop means a
   future 8th custom package just needs adding to the `PACKAGES` string, and
   a single broken package (like `kiji-proxy`'s pending-setup placeholder
   hash) can't silently corrupt or abort the rest of the run.
5. **Completeness** — covers all 7 packages currently in `pkgs/default.nix`.
6. **Performance** — n/a, on-demand manual recipe.
7. **Security** — no new secrets; relies entirely on the operator's own
   pre-existing `attic login` session (unchanged, pre-existing mechanism);
   the recipe itself never touches or stores a token.
8. **API Currency** — n/a, no new external dependency; `attic push`'s CLI
   interface (`attic push <cache> <path>`) already documented and relied on
   elsewhere in this repo (`justfile`'s existing `just enable attic` info
   text).
9. **Bug found and fixed during Phase 3 (not deferred):** the first version
   of the recipe merged the build's stderr into the captured `$out_path`
   (`2>&1` inside the command substitution) to support per-package error
   reporting — this corrupted the *successful* path capture too (the "Git
   tree is dirty" warning got concatenated onto the store path string,
   producing a broken multi-line argument to `attic push`). Caught via an
   actual dry run with a stub `attic` binary on `PATH` (not just a syntax
   check) — fixed by redirecting build stderr to a temp file instead of
   merging streams, tailing that file only on failure. Re-ran the dry run
   after the fix and confirmed every successful package now produces a
   clean single-line store path.
10. **Real pre-existing bug found (out of scope, but documented):**
    `pkgs/kiji-proxy/default.nix` uses `lib.fakeHash` as a deliberate
    placeholder, patched in-place by a *different* existing recipe
    (`just enable kiji-proxy`) — not a bug, by the file's own header
    comment, but it means `just attic-push` will always fail to build
    `kiji-proxy` on a machine that hasn't run that enable step first. The
    recipe now handles this gracefully (skips with a clear message,
    continues with the other 6, reports it in the final summary) rather
    than aborting the whole push or silently ignoring the fact that a
    package with a real hash-embedding step needs it run first.
11. **Build Validation:**
    - `just --list` — parses cleanly, `[Binary Cache]` group and
      `attic-push` recipe appear correctly.
    - **Guard check**: ran `just attic-push` with no `attic` binary on
      `PATH` — fails immediately with the expected clear error message,
      before attempting any build.
    - **Full dry run** with a stub `attic` binary on `PATH`: 6 of 7
      packages built and "pushed" (to the stub) with clean single-line
      store paths; `kiji-proxy` failed as expected with a clear,
      non-fatal message; final summary correctly listed it as the one
      failure and exited non-zero.
    - Verified each of the 6 successfully-building packages directly via
      `nix build --impure --no-link --print-out-paths` outside the recipe
      too, confirming the recipe's build command is correct.
    - `nix flake show --impure` — passed.
    - Per-target `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`
      for `vexos-desktop-amd`, `-nvidia`, `-vm` — evaluated cleanly (store
      hashes differ from earlier reviews this session due to an intervening
      `nix flake update` commit, unrelated to this change).
    - `vexos-server-amd` / `vexos-headless-server-amd` (server module
      touched, comment-only) — evaluated cleanly via `extendModules`.
    - `git ls-files hardware-configuration.nix` — empty. ✓
    - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs
      as every prior review this session — nothing new.

No CRITICAL issues remain (the one found was fixed within this same review
pass). No RECOMMENDED issues outstanding.

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

- Build result: PASS
- **PASS**
