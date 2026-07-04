# M-26 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-26_vexos_update_package_spec.md`

## Modified Files

- `pkgs/vexos-update/default.nix` (new) — `writeShellApplication` package, script
  body moved verbatim.
- `pkgs/default.nix` — registered as `pkgs.vexos.vexos-update`.
- `modules/nix.nix` — replaced the ~230-line inline `pkgs.writeShellScriptBin` block
  with a reference to the new package.
- `scripts/preflight.sh` — renumbered checks from `/7` to `/8`; added
  `[8/8]` building `pkgs.vexos.vexos-update` directly, forcing the shellcheck to run
  independent of whether the full per-variant dry-build (`[2/8]`) can run at all.

## Review Findings

1. **Specification Compliance** — all four steps from the spec implemented.
2. **Best Practices** — used `writeShellApplication` (shellchecks automatically at
   build time) rather than `writeShellScriptBin` (no linting); no `runtimeInputs`
   added since the script already relied purely on ambient PATH and the wrapper only
   prepends to PATH, not replaces it.
3. **Consistency** — follows the exact existing `pkgs/<name>/default.nix` +
   `pkgs.vexos.<name>` registration convention used by every other custom package in
   this repo.
4. **Maintainability** — the new package file's header explains why it exists (moved
   out of the wrong module) and documents the same exit-code/stdout-protocol contract
   the original inline comment did.
5. **Completeness** — the entire script moved (nothing left behind in
   `modules/nix.nix`); the new preflight check gives the shellcheck coverage a
   standalone, fast way to run.
6. **Performance** — no runtime performance change; build-time cost is negligible
   (shellcheck on ~200 lines).
7. **Security** — no change in behavior; purely a structural move.
8. **API Currency** — n/a.
9. **Build Validation:**
   - **Verbatim-move verification**: diffed the old inline script against the new
     package's `text` with whitespace normalized on both sides — the only
     differences are the old file's `writeShellScriptBin` wrapper line and the new
     file's closing `'';` syntax; every command, comment, and control-flow line is
     identical and in the same order. This directly confirms "no logic changes",
     not just an assumption.
   - Caught and fixed a real mistake during the move: the `.gitignore` heredoc body
     and its `GITIGNORE` terminator had picked up extra leading whitespace from
     reformatting, which would have broken the heredoc's exact-match terminator
     requirement for plain `<<` (not `<<-`). Fixed before the diff check above, which
     is what caught it.
   - Built the actual package directly
     (`nix build --impure --no-link ".#nixosConfigurations.vexos-desktop-amd.pkgs.vexos.vexos-update"`)
     — succeeded, meaning `writeShellApplication`'s automatic shellcheck pass found
     zero findings in the moved script.
   - Inspected the built binary directly (`head`, `wc -l`) — confirms the expected
     `writeShellApplication` strict-mode wrapper (`set -o errexit/nounset/pipefail`)
     and the correct line count.
   - `pkgs/vexos-update/` was new and untracked; `nix build`/`nix eval` couldn't see
     it until staged (git-index visibility, not a code issue) — user staged it before
     validation continued.
   - `nix flake show --impure` — passed.
   - Required targets (`vexos-desktop-amd`, `-nvidia`, `-vm`) evaluated cleanly.
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `just --list` — parses without error (unaffected — no justfile changes this
     time).
   - `bash scripts/preflight.sh` — exit 0, PASSED, including the new `[8/8]` step
     actually running and passing. Same pre-existing WARNs as every prior review this
     session; nothing new.

No CRITICAL or RECOMMENDED issues found.

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
