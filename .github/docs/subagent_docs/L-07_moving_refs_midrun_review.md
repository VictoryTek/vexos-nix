# L-07 — Install scripts fetch moving refs mid-run — Review

Status: Phase 3 (Review & Quality Assurance)
Spec: `.github/docs/subagent_docs/L-07_moving_refs_midrun_spec.md`

## Modified Files

- `scripts/install.sh`
- `scripts/stateless-setup.sh`

`scripts/migrate-to-stateless.sh` — no functional change (confirmed it
performs no further `raw.githubusercontent.com` downloads; only a static
header comment references `main`, which documents the user's own manual
fetch command and is unaffected by this fix).

## Review Against Spec

1. **Specification Compliance** — matches the spec's scope exactly, as
   narrowed by the user's decision to leave `disko/latest` untouched
   (confirmed upstream-recommended, not a repo-introduced defect —
   documented in the spec rather than "fixed").
   - `install.sh`: resolves `VEXOS_REV` once at the top (right after
     `set -euo pipefail`), before anything else runs; `SCRIPT_URL` and
     the "Verify:" line both use it; both mid-run curls (stateless-setup
     and migrate-to-stateless) use it.
   - `stateless-setup.sh`: resolves `VEXOS_REV` only if not already
     inherited; `REPO_RAW` (and therefore `TEMPLATE_URL`/
     `DISKO_TEMPLATE_URL`) derives from it.

2. **Best Practices** — reuses the exact `git`-missing → `nix build
   nixpkgs#git` fallback idiom already established in `install.sh:351-358`
   (now duplicated at the top of both scripts, matching this project's
   accepted precedent from M-30 of small ISO-bootstrap duplication being
   necessary across `curl | bash`-only scripts that can't source a
   shared fragment). `git ls-remote` avoids GitHub REST API rate limits
   and needs no `jq`.

3. **Consistency** — same comment style, same
   `command -v X || nix build nixpkgs#X` pattern already used for
   `openssl` (`stateless-setup.sh`) and `git` (`install.sh`, later in the
   same file) elsewhere in these two scripts.

4. **Maintainability** — the `${VEXOS_REV:-}` inheritance guard is the
   load-bearing mechanism that keeps the whole `install.sh` →
   `stateless-setup.sh`/`migrate-to-stateless.sh` chain pinned to one
   commit; documented inline with the *why* (sudo's `env_reset` strips
   plain `export`, so the migrate-to-stateless.sh hand-off explicitly
   sets `VEXOS_REV=` on the `sudo` command line rather than relying on
   inheritance — verified this distinction matters and is called out in
   a comment, not silently assumed).

5. **Completeness** — every `raw.githubusercontent.com/.../main/...`
   fetch URL in both files is now pinned; confirmed via grep no
   `/main/` fetch URL remains in either file (only the top-of-file usage
   comments, which describe the user's own initial one-liner and are
   correctly left alone per the spec).

6. **Performance** — adds one `git ls-remote` (a single lightweight
   smart-HTTP round trip, no clone) at the very start of whichever
   script the user invokes first; negligible relative to the rest of an
   install (disk formatting, closure build).

7. **Security** — net improvement: closes the window where a single
   install run could silently execute a mix of commits with no record
   of what actually ran; the "Verify:" URL now points at the exact
   commit that is genuinely executing, rather than a `main` link that
   may have already moved on by the time a user checks it.

8. **API Currency** — n/a, no external dependency added; `git
   ls-remote` and `nix build nixpkgs#git` are both pre-existing,
   already-used patterns in this codebase.

9. **Build Validation:**
   - `bash -n scripts/install.sh` → syntax OK
   - `bash -n scripts/stateless-setup.sh` → syntax OK
   - Live-ran the actual resolution line
     (`git ls-remote https://github.com/VictoryTek/vexos-nix main | cut -f1`)
     in this session's environment — returns a real 40-character SHA
     matching the repo's current pushed `main` HEAD.
   - Verified the `${VEXOS_REV:-}` inheritance short-circuit behaves
     correctly with a synthetic pre-set value (reuses it, does not
     re-resolve) — confirms the cross-process pinning mechanism the fix
     depends on actually works as designed.
   - No `.nix` files touched (confirmed via `git diff` file list), so
     the vexos-nix-specific `nix flake show --impure` /
     `nixos-rebuild dry-build` steps are not applicable; this session's
     environment also has no `nix` binary (Windows host), consistent
     with previous shell-script-only reviews this session (see L-06).
   - `git ls-files hardware-configuration.nix` → empty, unaffected.
   - No FORBIDDEN COMMANDS used.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A (no `.nix` files changed; syntax + live-logic validated) | A |

**Overall Grade: A (100%)**

## Result

**PASS** — no CRITICAL or RECOMMENDED issues found. Phase 6 (Preflight)
cannot run `nix`-dependent stages in this session's environment (no Nix
on this Windows host, per the same constraint noted in the L-06 review)
— deferred to the user's NixOS machine before push, per the established
pattern this session.
