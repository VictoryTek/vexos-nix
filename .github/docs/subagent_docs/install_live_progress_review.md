# install_live_progress_review.md

## Scope

Reviewed: `scripts/install.sh` against `install_live_progress_spec.md`.

## Specification Compliance

- `progress_bar()` extracted as a standalone helper (percent/width), reused
  by both the existing `render_progress` (phases 1-3/4, unchanged behavior)
  and the new `run_live_build`. ✅
- `VEXOS_TIPS` array added with vexos-nix-specific tips (not copied from
  Omarchy's Hyprland-specific ones). ✅
- `run_live_build()` implemented matching the traced Omarchy mechanism:
  cursor-addressed redraw of a fixed row (`\033[10;1H\033[J`) rather than a
  full clear per frame, logo drawn once beforehand and never touched again,
  `sudo -v` before backgrounding, real command output redirected to a temp
  log rather than shown live. ✅
- Call site converted: `render_progress "Building system configuration..." 4 4`
  + bare `if sudo nixos-rebuild ...` replaced with `render_header` +
  `if run_live_build "Building ${FLAKE_TARGET}..." sudo nixos-rebuild ...`. ✅
- Failure branch now prints `tail -n 60 "$BUILD_LOG_PATH"` before the existing
  guidance — paying back the transparency traded away by not streaming
  `nixos-rebuild` output live, exactly as the spec's risk section committed
  to. ✅
- The 3 earlier `render_progress` calls (phases 1-3/4: preparing, refreshing
  flake inputs, checking build cache) are untouched — confirmed via diff,
  only phase 4/4's call site changed. ✅

## Functionality — verified by actual execution, not just reading

- `bash -n scripts/install.sh` — syntax OK.
- Extracted `run_live_build` + its dependencies into an isolated harness and
  ran it twice through a real pty (`script -qec ... TERM=xterm-256color`):
  - **Success case** (`bash -c 'sleep 3; exit 0'`): confirmed the bar
    animates upward frame-by-frame via repeated `\033[10;1H\033[J` (not a
    full-screen clear — everything above row 10, i.e. the logo, is written
    exactly once), the tip line rotates, and on completion the bar jumps to
    a clean 100% with the log path printed and cursor restored
    (`\033[?25h`).
  - **Failure case** (`bash -c 'echo "fake nix error" >&2; exit 1'`):
    confirmed `run_live_build` returns the child's real exit code (1, not
    masked by the `local exit_code=0; ... || exit_code=$?` idiom — verified
    this specific idiom is necessary: a bare `wait "$build_pid"` would trip
    `set -e` and abort the whole script before the failure branch could run),
    and the captured stderr line was recoverable via `tail` on
    `$BUILD_LOG_PATH` afterward — confirming no output is lost on failure,
    only deferred.
- `nix flake show --impure`, and `nix eval --impure` full-evaluation
  equivalent for `vexos-desktop-{amd,nvidia,vm}` (same sandbox limitation on
  literal `sudo nixos-rebuild dry-build` as prior reviews) — all pass.
- `bash scripts/preflight.sh` → **PASSED** (exit 0), pre-existing warnings
  only, none touching `scripts/install.sh`.

## Design Notes / Judgment Calls

- Progress in `run_live_build` is purely time-based (asymptotic curve
  approaching 92%, jumping to 100% on actual completion) rather than
  Omarchy's real step-count signal, because there's no equivalent to
  "grep completed pacman hook scripts" for a single `nixos-rebuild`
  invocation — this is disclosed in the spec, not presented as identical
  fidelity to the source. It is an honest "still working" indicator, not a
  fabricated percentage of real work.
- `sudo -v` is a new bare statement under `set -euo pipefail`; if it fails
  (e.g. sudoers policy blocks credential caching), the script now stops
  there instead of silently hanging on the backgrounded job's un-promptable
  `sudo`. This is a deliberate, disclosed trade — failing loudly beats
  hanging silently — and is consistent with every other bare `sudo` call
  already present in this script that assumes interactive tty access.

## Security

No new trust boundary. `$build_log` uses `mktemp` (no predictable path);
temp file is world-readable by default `mktemp` permissions like other temp
usage already in this script (`_DRY_OUT_FILE`), not a new pattern.

## Build Validation

- `git ls-files hardware-configuration.nix` → empty. ✅
- `system.stateVersion` unaffected (no `.nix` changes in this diff). ✅
- `nix flake show --impure` → completes, no errors. ✅
- Full-evaluation equivalent for `vexos-desktop-{amd,nvidia,vm}` → pass.
- `bash scripts/preflight.sh` → PASSED (exit 0).

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A (verified via actual pty execution of both success and failure paths) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A (dry-build unavailable in sandbox; full-eval + preflight both passed) |

**Overall Grade: A (99.4%)**

## Follow-up fix (post-PASS, user-reported)

User reported visible screen blinking during the live build screen. Root
cause: each 0.5s frame used `\033[J` (clear-to-end-of-screen) from the
dynamic row down, plus recomputed `tput cols` and re-ran `center_block`
(each forking `tput`/`sed`/a read loop) for the title and tip every single
frame — the full-region erase plus the visible latency of that repeated
subprocess work is what read as flicker.

Fix: replaced the single `\033[J` with a per-line `\033[2K` (clear just that
line) immediately before each line's content is written, so there's never a
moment where the whole region is blank — only ever one line at a time, right
before it's overwritten. Also moved `tput cols`, the centered title, and all
centered tip strings out of the loop entirely (computed once up front into
`cols`, `bar_pad`, `centered_title`, `centered_tips[]`), so the loop body now
does effectively no subprocess forking except `progress_bar`'s own internal
`seq` calls to build the bar string.

Verified via the same pty-capture technique as the original review: the
escape sequence stream now shows `\033[10;1H` once per frame followed by five
`\033[2K<content>` lines, with no `\033[J` present in the animation loop
(only used once, in the failure branch, to clear the dead animation before
falling through to the log-tail message).

Re-ran full Phase 3 validation after the fix: `nix flake show --impure`,
full-eval equivalent for `vexos-desktop-{amd,nvidia,vm}`, and
`bash scripts/preflight.sh` all pass (exit 0), no regressions.

## Result

**PASS**
