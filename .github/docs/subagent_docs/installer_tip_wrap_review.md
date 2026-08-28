# Review — Tip Line Wrap-Residue Fix

## Scope

Single-file change: `scripts/install.sh`, inside `run_live_build()`. No
`.nix` files touched.

## Specification Compliance

Matches `installer_tip_wrap_spec.md`: nested `_truncate_to_width` helper
added, `recompute_layout()`'s tip-building loop now truncates
`"Tip: ${VEXOS_TIPS[$i]}"` to `cols - 2` chars before centering, cleanup
extended to `unset -f redraw_frame recompute_layout _truncate_to_width`.

## Best Practices / Consistency

- Follows the existing nested-function pattern already used for
  `recompute_layout`/`redraw_frame` in this same function.
- Truncation is recomputed on every `recompute_layout()` call, including
  the resize-triggered one added by `installer_live_build_resize_spec.md`
  — a mid-build resize also gets a correctly re-truncated tip width, not
  just the initial one.

## Correctness notes

- Verified directly: truncating the longest tip (87 chars) at `cols-2` for
  cols ∈ {40, 60, 80, 120} always produces output of length ≤ `cols-2`,
  with a trailing `…` only when truncation actually occurred (cols=120
  case returns the full untouched string, since it fits).
- Bash's `${#text}`/`${text:0:N}` are character-based (not byte-based)
  under UTF-8 locale, so the em dash in tip #3 doesn't throw off the
  truncation point.

## Security

No changes to command execution or external input handling — pure local
string truncation.

## Build validation

- `bash -n scripts/install.sh` → syntax OK.
- `shellcheck -x scripts/install.sh` (nixpkgs#shellcheck 0.11.0, WSL) →
  clean; only the same pre-existing unrelated SC2024 warning remains.
- No `.nix` files touched — NixOS build steps not applicable.

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
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Result: PASS
