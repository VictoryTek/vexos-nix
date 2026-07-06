# L-11 — programs.git ships user.email = "" — Review

Status: Phase 3 (Review & Quality Assurance)
Spec: `.github/docs/subagent_docs/L-11_git_empty_email_spec.md`

## Modified Files

- `home/bash-common.nix`

## Review Against Spec

1. **Specification Compliance** — matches the spec exactly: the
   `email = lib.mkDefault "";` line was removed from
   `programs.git.settings.user`, leaving `name` untouched; the header
   comment was updated to reflect that email is left *unset* (not
   blank) so git's own fallback/warning applies.

2. **Best Practices** — corrected the plan's literal premise before
   acting on it: directly tested `git commit` with a real `user.name`
   and empty `user.email` (this repo's exact combination) — the commit
   succeeds (records `Name <>`), it does not refuse, since git's hard
   "empty ident" failure triggers on an empty *name*, not email. The
   underlying problem (malformed blank-email authorship, and
   suppressing git's own configure-your-identity fallback) is real and
   still worth fixing; the fix applied is the same one the plan
   proposed regardless of the corrected premise.

3. **Consistency** — no style change beyond the one line removed and
   the comment reword; `name` formatting matches the rest of the
   `settings` block.

4. **Maintainability** — comment now accurately describes the
   *mechanism* (unset → git's own fallback/warning) rather than an
   inaccurate "intentionally left blank" framing that implied the empty
   string itself was the intended state.

5. **Completeness** — confirmed via grep this is the only
   `user.email`/`userEmail` reference in the repo; confirmed via grep
   that none of this repo's own automated git commits
   (`scripts/install.sh:403-404`, `pkgs/vexos-update/default.nix:48-49,
   105-106`) depend on this home-manager value at all — they already
   pass their own explicit `-c user.email="vexos@localhost" -c
   user.name="VexOS"`, entirely independent of the interactive user's
   git config. `stateless-setup.sh`/`migrate-to-stateless.sh` perform no
   `git commit` at all (only `add`/`init`). Zero interaction risk,
   confirmed rather than assumed.

6. **Performance** — no impact.

7. **Security** — no new vulnerabilities; strictly improves commit
   authorship data quality for the interactive user's own repos.

8. **API Currency** — n/a, no external dependency; `programs.git.settings`
   is home-manager's current freeform ini-generator option, used
   correctly (removing an attrset key is sufficient to omit it from the
   generated `~/.config/git/config`).

9. **Build Validation** — via WSL2 Ubuntu (Nix 2.34.1, mounted repo at
   `/mnt/c/Projects/vexos-nix`). This file is imported by every role's
   `home-*.nix` (`home-desktop`, `home-headless-server`, `home-htpc`,
   `home-server`, `home-stateless`, `home-vanilla`), so validated
   broadly rather than just the minimum required set:
   - `nix flake show --impure` → PASS, no errors across all 30
     `nixosConfigurations`.
   - `vexos-desktop-amd` → PASS
   - `vexos-desktop-nvidia` → PASS
   - `vexos-desktop-vm` → PASS
   - `vexos-stateless-amd` → PASS
   - `vexos-htpc-amd` → PASS
   - `vexos-server-amd` (via `extendModules`-injected throwaway
     `hostId`, same as prior reviews this session, since
     `zfs-server.nix`'s placeholder-rejection assertion is unrelated to
     this change but still applies to any server-role eval) → PASS
   - `vexos-headless-server-amd` (same hostId workaround) → PASS
   - Ran the full `bash scripts/preflight.sh` → **exit 0, "Preflight
     PASSED — safe to push."** Same pre-existing, expected WARNs as
     every prior review this session. Stage `[8/8]` passed.
   - `git ls-files hardware-configuration.nix` → empty, unaffected.
   - No `system.stateVersion` change; no new flake inputs.
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
| Build Success | 100% — `nix flake show`, 7 target evaluations, and full `preflight.sh` all passed via WSL2 | A |

**Overall Grade: A (100%)**

## Result

**PASS.** Phase 6 (Preflight) has genuinely run and passed for this
change, validated across every role that imports this file. Safe to
commit and push.
