# STATELESS_INSTALL_PROGRESS_BAR — Review & QA (Phase 3)

## Scope reviewed

- `scripts/migrate-to-stateless.sh` (+92 / -1)
- `scripts/stateless-setup.sh` (+94 / -1)
- Spec: `.github/docs/subagent_docs/STATELESS_INSTALL_PROGRESS_BAR_spec.md`

No `.nix` files, no flake inputs, no `configuration-*.nix`, no modules touched.

## 1. Specification compliance

| Spec item | Status |
|---|---|
| `VEXOS_TEAL` added to both colour-block branches of both scripts | ✅ |
| Self-contained progress block (no sourced lib) after colour block | ✅ both scripts, identical |
| `VEXOS_TIPS`, `progress_bar`, `run_build_progress` ported (trimmed, single `\r` line) | ✅ |
| `migrate-to-stateless.sh` `nixos-rebuild boot` wrapped + failure handler + `exit 1` | ✅ |
| `stateless-setup.sh` `sudo nixos-install` wrapped + failure handler + `exit 1` | ✅ |
| Existing "Running…/This may take a while" echo lines kept | ✅ |
| `install.sh` unchanged | ✅ |
| Header comment points back to `install.sh:124-263` as source of truth | ✅ |

**Deviation from spec (minor, accepted):** `run_build_progress` prints one extra
line up front — `<label> — live output: <logfile>` — so the user can `tail -f`
the real build during the run. The spec only required the log path on *failure*.
This strictly improves the transparency tradeoff called out in the spec's risk
table and adds no failure mode. Documented here rather than silently dropped.

## 2. Best practices (Bash)

- `local` for every function variable; `bar=""` initialised (guards `set -u`).
- Command substitution failures inside `printf` cannot abort under `set -e`
  (not simple commands in the tested position); real call sites are
  `if run_build_progress …; then`, which suppresses `set -e` correctly.
- `wait "$build_pid" || exit_code=$?` captures the child status without aborting.
- `mktemp "${TMPDIR:-/tmp}/…"` — portable, respects `$TMPDIR`.
- `tput cols` guarded with `|| echo 80`.
- Cursor always restored (`\033[?25h`) on the normal return path.
- `sudo -v 2>/dev/null || true` — no abort if sudo unavailable/declined.

## 3. Consistency

Matches `install.sh` conventions: same `92*elapsed/(elapsed+60)` asymptotic
curve, same 6-second tip rotation, same `progress_bar` implementation and
UTF-8/`printf %.0s` comment, same `BUILD_LOG_PATH` contract, same brand teal
escape. Duplication across the three scripts follows the project's established
`UNAVOIDABLE_REGEX` manual-sync-comment pattern (`install.sh:990-993`) —
mandated by the `curl | bash`, no-local-repo execution model.

Module Architecture Pattern (Option B): N/A — shell scripts only.

## 4. Maintainability

Block is ~55 lines, one responsibility, commented, and cross-referenced to the
canonical copy. `label` is consumed by the new intro line (no dead parameter).

## 5. Completeness

Both stateless install paths (in-place migration + fresh ISO) now show the
progress UI, per the user's confirmed "Both migrate + stateless-setup" scope.

## 6. Performance

0.5 s redraw cadence identical to `install.sh`. One `tput cols` + a handful of
`printf` subshells per frame — negligible against a multi-minute build.

## 7. Security

No secrets, no world-writable files, no privilege change. `mktemp` creates the
log 0600 by default. Log may contain build paths/store hashes only (same as the
`install.sh` build log). `sudo -v` refreshes an existing timestamp; grants
nothing new.

## 8. API currency

No external/versioned APIs. `EPOCHSECONDS` (bash ≥ 5) already relied on by
`install.sh`; NixOS ISO ships bash 5.x. Local check: `bash 5.3.9`.

## 9. Build validation

| Check | Result |
|---|---|
| `bash -n scripts/migrate-to-stateless.sh` | ✅ syntax OK |
| `bash -n scripts/stateless-setup.sh` | ✅ syntax OK |
| `shellcheck` (v0.11.0) both files | ✅ exit 0 — only the 2 pre-existing findings (`SC2001` migrate:184, `SC2059` stateless-setup:344); **no new findings** |
| Functional: `run_build_progress "ok" sleep 3` | ✅ redraws bar, returns 0, `BUILD_LOG_PATH` set |
| Functional: `run_build_progress "fail" 'exit 7'` | ✅ returns 7, stderr ("boom") captured in log |
| `nix flake show --impure` | ✅ completes; pre-existing `kernel-override` non-derivation warnings only |
| `git ls-files hardware-configuration.nix` | ✅ empty |
| `system.stateVersion` unchanged | ✅ no `.nix` files touched |
| New flake inputs `follows` | N/A — no flake changes |

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 98% | A |
| Best Practices | 96% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 97% | A |
| Build Success | 100% | A |

**Overall Grade: A (98%)**

## Result

**PASS** — proceed to Phase 6 (Preflight).
