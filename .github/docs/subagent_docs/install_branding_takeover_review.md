# install_branding_takeover_review.md

## Scope

Reviewed: `scripts/install.sh` against `install_branding_takeover_spec.md`.

## Specification Compliance

- `VEXOS_TEAL` / `VEXOS_ORANGE` truecolor constants added, gated by the same
  existing `[ -t 1 ] && tput colors -ge 8` check; empty in the `else` branch
  alongside the other color vars. ✅
- `VEXOS_LOGO` (hardcoded `toilet -f mono12 "VEXOS"` output) and
  `render_header()` added exactly as specified. ✅
- One-time startup header replaced with `render_header` + Source/Verify lines. ✅
- `render_header` inserted before: role selection, server sub-type, GPU
  variant, NVIDIA branch, ASUS y/n, ASUS-laptop y/n, and the "Building
  ${FLAKE_TARGET}..." phase transition. ✅
- Fallback-branch retry loops (`while` loops with an `Invalid selection`
  case) re-run `render_header` before re-printing the question, so an
  incorrect entry redraws cleanly instead of stacking error text. ✅
- **Documented deviation** (verified against the actual diff, not just
  claimed): GRUB device input, EFI device input, and the final reboot
  confirmation do **not** call `render_header`. Confirmed by inspection —
  these three prompts are each the tail of a multi-line diagnostic block
  (`lsblk` output / build-success summary) that the user must keep reading
  while answering; clearing right before them would erase that context. This
  was corrected mid-implementation and the spec file was updated in place to
  match, with rationale. Judged a good call, not a shortcut: it directly
  serves the same goal (a coherent, non-confusing screen) that the rest of
  the feature is going for.
- Long-running/scrolling sections (UEFI/GRUB patch messages, `/boot` mount
  check, ASUS hardwareModule patch, hostId substitution, git-tracking,
  `gum spin`-wrapped flake update, dry-build cache report, live
  `nixos-rebuild` output) confirmed untouched — no `clear`/`render_header`
  calls were added inside any of them. ✅
- No `.nix` changes. ✅

## Best Practices / Consistency

- `clear 2>/dev/null || true` — never aborts the script under `set -e` if
  `$TERM` is missing/unsupported (e.g. a stripped serial console), matching
  how other cosmetic-only commands in this script are treated.
- Brand colors are truecolor (24-bit) escapes, consistent with the level of
  terminal capability already assumed by `gum` (which itself requires a
  reasonably capable terminal) — no new capability floor introduced beyond
  what `gum` already requires.
- Colors sourced from actual repo assets (`files/pixmaps/desktop/vex.png`,
  `files/pixmaps/server/vex.png`) via `magick -unique-colors`, not invented —
  traceable provenance documented in the spec.

## Functionality

- `bash -n scripts/install.sh` — syntax OK.
- Manually rendered `render_header` in isolation via `script -qec ... TERM=xterm-256color`
  to confirm: `clear` sequence fires, truecolor escape precedes the logo,
  logo glyphs are valid UTF-8 and render as the intended block-letter "VEXOS",
  orange bold tagline follows. Screenshot-equivalent text capture reviewed
  directly (see review session transcript).
- Traced every non-`render_header`-touched section against `git diff` to
  confirm no accidental `clear` insertion inside the build/dry-build tail.

## Security

No changes to trust boundaries, no new inputs, no secrets. Logo string is a
static literal, not user- or network-derived.

## Build Validation

- `git ls-files hardware-configuration.nix` → empty. ✅
- `nix flake show --impure` → completes, no errors. ✅
- `nix eval --impure` full-evaluation equivalent for
  `vexos-desktop-{amd,nvidia,vm}` → all three resolve to `.drv` paths, no
  errors (same sandbox limitation on literal `sudo nixos-rebuild dry-build`
  as the prior review — `sudo` is blocked by "no new privileges" in this
  session).
- `bash scripts/preflight.sh` → **PASSED** (exit 0). Pre-existing warnings only
  (nix formatting across 96 unrelated files, `flake.lock` input ages,
  `vexboard.nix` placeholder secret string, gitleaks not installed) — none
  introduced by this change, none touching `scripts/install.sh`.
- Change does not touch server/headless-server/stateless/htpc modules, so the
  conditional extra dry-build targets don't apply.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A (dry-build unavailable in sandbox; full-eval equivalent + preflight both passed) |

**Overall Grade: A (98.75%)**

## Result

**PASS**
