# Review: Stateless Role Bug Fixes

**Feature name:** `stateless_fixes`  
**Date:** 2026-04-20  
**Reviewer:** Phase 3 Review Subagent  
**Spec:** `.github/docs/subagent_docs/stateless_fixes_spec.md`  
**Verdict:** **PASS**

---

## Files Reviewed

| File | Purpose |
|------|---------|
| `home-stateless.nix` | Modified — orphan cleanup activation + torbrowser dock entry |
| `home/photogimp.nix` | Reference — existing cleanup pattern and DAG entry point |

---

## Change 1 — PhotoGIMP Orphan Cleanup Activation

### DAG Entry Point

The implementation uses `lib.hm.dag.entryBefore [ "checkLinkTargets" ]`.

The review task instructions asserted that the correct entry point "should be
`hm.dag.entryAfter ["writeBoundary"]`". **This assertion is incorrect.** Verification
against both the spec and the existing codebase confirms the opposite:

- The spec (`stateless_fixes_spec.md`) explicitly calls for `entryBefore ["checkLinkTargets"]`
  and provides rationale: "Same ordering used by the photogimp.nix cleanup."
- `home/photogimp.nix` — the canonical reference — uses `entryBefore ["checkLinkTargets"]`
  for its own cleanup activation `cleanupPhotogimpOrphanFiles`, and `entryAfter ["writeBoundary"]`
  only for write-side operations (`installPhotoGIMP`, `refreshPhotoGIMPDesktopIntegration`).
- DAG evaluation confirmed: `{ after = []; before = ["checkLinkTargets"]; }` ✓

**`entryBefore ["checkLinkTargets"]` is correct** for a removal/cleanup activation in this
codebase. Using `entryAfter ["writeBoundary"]` for a cleanup would be an anti-pattern here —
it would run after all managed files have been written, which is the wrong phase for orphan
removal.

### `$DRY_RUN_CMD` and `$VERBOSE_ECHO` Usage

Both variables are used consistently throughout the script body. Every filesystem
mutation is prefixed with `$DRY_RUN_CMD`. Every user-facing message is sent via
`$VERBOSE_ECHO`. The pattern is identical to the existing activations in
`photogimp.nix`. ✓

### File Existence Conditions

```bash
if [ -e "$FILE" ] || [ -L "$FILE" ]; then
```

- `-e` — true for real files and valid symlinks (follows the symlink)
- `-L` — true for any symlink including broken ones

Together they cover all three cases: real file, live symlink, broken symlink.
This is wider coverage than the `photogimp.nix` cleanup (`[ -f ] && [ ! -L ]`)
which was intentionally narrower. For the stateless role, wider coverage is
correct — any remnant (regardless of type) should be removed. ✓

### Package Path References

Both package paths were evaluated against the pinned nixpkgs:

| Reference | Resolved Store Path |
|-----------|---------------------|
| `${pkgs.desktop-file-utils}/bin/update-desktop-database` | `/nix/store/dicy7kcw7gwz0cyy7jpw6azycv7c288n-desktop-file-utils-0.28/bin/update-desktop-database` |
| `${pkgs.gtk3}/bin/gtk-update-icon-cache` | `/nix/store/gkmyy8i5wgkpha1p0a9yvym86zpxn4jf-gtk+3-3.24.51/bin/gtk-update-icon-cache` |

Both resolve correctly. The `gtk3` reference matches photogimp.nix exactly. ✓

### Shell Script Correctness

The activation script body was extracted via `nix eval` and reviewed:

- All `if/fi` blocks are correctly paired ✓
- Both `for/do/done` loops are syntactically correct ✓
- The multi-line `for stray in \` loop with backslash continuation is valid bash ✓
- Nix string indentation stripping (6-space minimum) produces clean bash with
  proper 0/2/4-space indentation in the final script ✓
- No bare expansions; all variables are double-quoted ✓

### Placement in File

The activation block is placed after `home.file."justfile"` and before
`# ── Hidden app grid entries`, which matches the spec. ✓

### Comment Quality

The block comment accurately describes the purpose, the mechanism (both real
files AND symlinks), and why this differs from `photogimp.nix`'s cleanup. ✓

---

## Change 2 — `torbrowser.desktop` in Dock Favorites

The entry was added at position 3 (after `zen_browser`, before `Nautilus`),
which places it in the browser group consistent with its role as the primary
privacy browser on the stateless configuration. This matches the spec exactly.

Confirmed present in evaluated dconf:

```
[ "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "torbrowser.desktop"        ← ✓ correctly inserted
  "org.gnome.Nautilus.desktop"
  "com.mitchellh.ghostty.desktop"
  "io.github.up.desktop" ]
```
✓

---

## Build Validation

| Check | Command | Result |
|-------|---------|--------|
| Flake structure | `nix flake check` | ⚠ Expected failure — pure eval blocks `/etc` access for `hardware-configuration.nix`; unrelated to these changes |
| HM activation names | `nix eval ...home.activation --apply builtins.attrNames` | ✓ `cleanupPhotogimpOrphans` present |
| Activation script body | `nix eval ...cleanupPhotogimpOrphans --apply 'x: x.data'` | ✓ Valid bash, both store paths resolved |
| DAG deps | `nix eval ...cleanupPhotogimpOrphans --apply 'x: {before=x.before;after=x.after;}'` | ✓ `{ after=[]; before=["checkLinkTargets"]; }` |
| dconf favorite-apps | `nix eval ...dconf.settings."org/gnome/shell".favorite-apps` | ✓ `torbrowser.desktop` present at position 3 |

`nix flake check` failure is expected and pre-existing — the `/etc` path access
restriction in pure evaluation mode is caused by the `hardware-configuration.nix`
import, which is by design not tracked in this repository. It is not a regression
introduced by these changes.

---

## Issues Found

None.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 98% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 98% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (99.5%)**

Minor deduction: Best Practices and Code Quality reflect that the desktop
database and icon cache refreshes inside the cleanup activation run
unconditionally when the target directories exist — even when no orphans were
removed. In practice this is harmless (fast no-op), and the same pattern is
used in `photogimp.nix`, so no change is warranted.

---

## Final Verdict

**PASS**

Both fixes are correctly implemented, consistent with existing project patterns,
fully evaluated by Nix without errors, and conform precisely to the specification.
The implementation is ready to merge.
