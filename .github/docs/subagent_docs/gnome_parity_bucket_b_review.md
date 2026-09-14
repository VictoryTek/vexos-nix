# GNOME Parity Bucket B — Review

## Summary

Reviewed against `gnome_parity_bucket_b_spec.md`. All 3 implementation steps
completed as specified (B4 correctly implemented as "no change," per spec).

## Specification Compliance

1. `home/noctalia.nix` — `bar.default.end` now
   `["tray" "caffeine" "notifications" "network" "bluetooth" "volume"
   "battery" "theme_mode" "screenshot" "session"]` and
   `widget.notifications.hide_when_no_unread = true` — ✅ confirmed in
   rendered TOML, exact order as specified.
2. `modules/hyprland-desktop.nix` — `"org/gnome/desktop/wm/preferences".
   "button-layout" = "appmenu:minimize,maximize,close"` added alongside the
   existing dns-sd key in the same dconf database — ✅ confirmed resolved on
   the forced-hyprland branch (`{"button-layout":
   "appmenu:minimize,maximize,close"}`), exact value match to
   `modules/gnome.nix`.
3. `files/hypr/hyprland.conf` — `focus_on_activate = true` added inside the
   existing `misc { }` block — ✅ confirmed by running the actual edited file
   through `Hyprland --verify-config`, not just a synthetic snippet:
   `config ok`.

## Best Practices / Consistency

- No new `lib.mkIf` guards, no Module Architecture Pattern changes — all
  three edits land inside existing gated blocks (`hyprland-desktop.nix`'s
  existing `isHyprland` mkIf, `noctalia.nix`'s existing hyprland mkIf, and the
  Hyprland-only seed file).
- Widget ordering follows a stated rationale (status icons together, utility
  actions before session) rather than arbitrary placement, and that rationale
  is captured in a comment.
- B4 was **not** implemented — the spec explicitly found Noctalia's own
  default control-center shortcuts already satisfy the gap, and declaring the
  same 6 defaults explicitly would be redundant config with no behavior
  change. Correctly scoped down rather than padded out to "do all 7 audit
  items."

## Completeness

5 of 7 original bucket-B audit items closed as real changes (B1, B2, B3, B5,
B6, B7 — six items, since B1/B2/B3/B7 are separate widgets landed in one
edit); B4 closed as "no action needed" with the reasoning documented, not
silently dropped.

## Security

None applicable. No secrets, no privileged services, no new packages.

## Performance

Negligible — four additional lightweight bar widgets, one dconf key, one
compositor boolean.

## Build Validation

`sudo nixos-rebuild dry-build` remains unavailable in this sandbox; used the
established substitutes, plus tool-specific validators for the two
non-Noctalia formats touched this round (Hyprland's own config, not just the
Nix layer around it):

| Check | Command | Result |
|---|---|---|
| **Hyprland config, the actual edited file** | `Hyprland --verify-config -c files/hypr/hyprland.conf` (the real installed 0.55.4 binary, not a synthetic snippet) | ✅ `config ok` |
| Hyprland option negative control | same binary against `misc:focus_on_activateXYZ` | ✅ `config option <misc:focus_on_activateXYZ> does not exist` — confirms `--verify-config` discriminates |
| GTK reads the dconf key (binary evidence) | `strings libgtk-4.so` (installed 4.20.3) | ✅ contains literal `org.gnome.desktop.wm.preferences` / `button-layout` |
| Noctalia config validator | `noctalia config validate <generated config.toml>` | ✅ `✓ Config is valid`, zero warnings |
| Noctalia validator negative control (hook key) | established in the prior wallpaper-hook review | ✅ (re-confirmed the mechanism still holds; not re-run this pass since no hook changed) |
| **Noctalia validator does NOT catch bad array tokens** | validate a copy with `"theme_mode"` → `"theme_modeXYZ"` inside `bar.default.end` | ⚠️ still reports `✓ Config is valid` — **negative finding**: the validator does not resolve widget-array strings against the runtime registry. Documented here so this is never mistaken for proof of a widget name later. The actual verification for B1/B2/B3/B7's widget names came from grepping each `.type = "..."` registration directly in the pinned C++ source — the correct, stronger method, already used before this was discovered. |
| Rendered TOML inspection | `nix build` the generated `config.toml`, read `[bar.default]` / `[widget.notifications]` | ✅ exact expected content |
| dconf key resolution | `nix eval` filtering all `programs.dconf.profiles.user.databases` entries for the new key (the list is module-merged, so a single-index read was wrong on the first attempt — corrected to a filter) | ✅ resolves to the exact GNOME value |
| Forced hyprland branch, full closure | `nix eval --impure` via `extendModules` | ✅ toplevel drv produced |
| Default (gnome) branch unaffected | `nix eval --impure` toplevel drvPath | ✅ identical drvPath to session baseline |
| `scripts/preflight.sh` | full run | ✅ see Phase 6 |

**Caveat:** as with every prior change this session, this proves the
generated artifacts are correct — it cannot prove the *visual* result
(whether the new bar icons render where expected, whether GTK apps actually
pick up the new button order, whether activating a window actually steals
focus) without a live Hyprland session. The B6 caveat from the spec — that
this host's already-seeded `~/.config/hypr/hyprland.conf` will not pick up
`focus_on_activate` from a rebuild — is a real, structural limitation, not a
build gap, and must be surfaced to the user directly.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A (every new key/option verified against a live binary or negative-controlled validator; visual/runtime result unverified — sandbox limitation) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Result

**PASS.** No CRITICAL issues. No refinement cycle needed.
