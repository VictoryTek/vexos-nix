# Hyprland Omarchy-Style Keybinds Review

## Spec Reference
`.github/docs/subagent_docs/hyprland_omarchy_keybinds_spec.md`

## Files Reviewed
- `files/hypr/hyprland.conf`
- `modules/hyprland-desktop.nix`

## Findings

One CRITICAL issue was found and fixed during implementation (documented for
traceability, not a residual defect): the first draft ported Omarchy's
`clipboard.conf` (`SUPER,C`/`SUPER,V`/`SUPER,X` → `sendshortcut` universal
copy/paste/cut) verbatim. `SUPER,V` and `SUPER,X` directly collide with
pre-existing DMS bindings already in the file (`$mod,V` → clipboard-history
viewer, `$mod,X` → dash toggle). Hyprland fires every `bind` line registered
on a matching combo, so both actions would have fired on every keypress of
those two combos — e.g. `$mod,V` would open the DMS clipboard viewer *and*
send a paste shortcut to the active window simultaneously. Caught by an
automated duplicate-combo scan across the whole file (not just eyeballing),
and fixed by dropping the `clipboard.conf` section entirely (documented in
the spec's "not ported" section) rather than porting only the one
non-conflicting key.

A second automated pass after the fix (`grep` + `sort | uniq -c` over every
`MODS|KEY` pair across all `bind*` lines) found no further collisions except
the two intentional dual-action chains copied verbatim from Omarchy itself
(`ALT,TAB` → `cyclenext` + `bringactivetotop`; `ALT SHIFT,TAB` → `cyclenext
prev` + `bringactivetotop`).

No other issues found.

## Review Checklist

1. **Specification Compliance** — every binding in the implementation traces
   to a row in the spec's mapping tables; nothing was added that isn't
   documented there, and everything the spec marked "not ported" stayed
   unported. ✅
2. **Best Practices** — Only real, verified DMS ipc functions and
   already-installed CLI tools are called (see spec's "Grounding" column);
   nothing points at a nonexistent command. The one place an assumption
   needed correcting mid-implementation (`gnome-calculator` bare binary vs.
   the actually-installed Flatpak, requiring `gtk-launch
   org.gnome.Calculator`) was caught by checking, not assumed. ✅
3. **Consistency** — All changes stay inside `files/hypr/hyprland.conf`
   (user-space, not a NixOS module) and the existing
   `environment.systemPackages` list in `modules/hyprland-desktop.nix`'s
   `isHyprland` block; no `lib.mkIf` was added to a shared/universal module.
   Bind syntax (`bind`/`bindel`/`bindl`/`bindm`) matches the file's
   pre-existing convention throughout — the first draft introduced Omarchy's
   `bindd`-with-description variant for the media section only, which was
   caught as a self-inconsistency (some sections would have descriptions,
   others wouldn't) and reverted to match the rest of the file. ✅
4. **Maintainability** — Every deviation from a literal 1:1 Omarchy port
   (moved keys, repurposed slots, dropped sections) is commented at the
   point of use in the `.conf` file itself, not just in the spec, so a
   future reader diffing against upstream Omarchy understands why without
   cross-referencing docs. The PTT binding carries an explicit "DO NOT
   reassign" comment per the task's constraint. ✅
5. **Completeness** — Window/workspace management (`tiling-v2.conf`) ported
   in full per spec scope; utility/media bindings ported wherever a real
   equivalent exists, explicitly skipped elsewhere with reasons recorded. ✅
6. **Performance** — No regressions; `hyprland.conf` is a static, once-seeded
   user file (unchanged deployment mechanism), and the two new system
   packages (`jq`, `upower`) are small CLI tools with no runtime service
   attached. ✅
7. **Security** — No secrets, no world-writable files. All `exec` commands
   are static strings (no user-controlled input interpolated), matching the
   file's existing risk profile. ✅
8. **API Currency** — DMS ipc targets/functions (`powermenu`, `notifications
   dismissAllPopups`, `audio`/`brightness` step and `set` args) were
   re-verified against the pinned `inputs.dms` source for *this* task, not
   carried over by assumption from the earlier GNOME-parity work. ✅
9. **Build Validation** — see below.

## Build Validation

Same constraint as the prior GNOME-parity change: this sandbox blocks `sudo`
outright, and this host's own `/etc/nixos/features.nix` defaults to
`vexos.desktop.environment = "gnome"`, so a plain build of this host's own
config wouldn't exercise the Hyprland module at all. Used the same
CLAUDE.md-sanctioned substitute as before: `nix eval --impure` on
`system.build.toplevel.drvPath`, forcing `vexos.desktop.environment =
"hyprland"` via `extendModules` (pure, in-memory, touches no tracked or host
file).

| Target | Env forced to `hyprland` | Result |
|---|---|---|
| `vexos-desktop-nvidia` | yes | ✅ eval succeeds, drvPath produced |
| `vexos-desktop-amd` | yes | ✅ eval succeeds, drvPath produced |
| `vexos-desktop-vm` | yes | ✅ eval succeeds, drvPath produced |
| `vexos-desktop-nvidia` | no (default `gnome`, regression check) | ✅ eval succeeds, unaffected |

Note on scope: `files/hypr/hyprland.conf` is a plain file copied by a
home-manager activation script (`home.activation.seedHyprlandConf` in
`home/dank-material-shell.nix`), not evaluated by Nix — so the toplevel
build above validates the *module* changes (`jq`/`upower` package additions)
but cannot itself catch a Hyprland keybind-syntax error inside the `.conf`
file. Mitigated by: (a) every dispatcher/syntax pattern used was either
copied verbatim from Omarchy's own working upstream config or matches this
project's own pre-existing, already-working bind lines: (b) an automated
duplicate-combo scan (`grep` + `sort | uniq -c` across every `bind*` line's
mod+key pair) to catch collisions a visual read would miss — this is what
caught the clipboard-section bug above; (c) nested shell-quoting in the two
new `notify-send`/`$(...)` one-liners was traced through bash's actual
quoting rules (nested `$(...)` opens a fresh quote scope) rather than
assumed correct. Actual runtime keybind behavior (does pressing the key
combo do the right thing in a live Hyprland session) cannot be verified in
this headless environment and should be spot-checked by the user after their
next `nixos-rebuild switch` + relogin.

`nix flake show --impure` — all outputs list cleanly. ✅

`git ls-files hardware-configuration.nix` — empty (not tracked). ✅

`system.stateVersion` — no diff in any `configuration-*.nix`. ✅

No new flake inputs added; `follows` check not applicable.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95%* | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100%† | A |

\* Static/structural verification (no duplicate binds, verified DMS
functions, correct shell quoting) is complete; live in-session keybind
behavior is unverified in this headless environment — see Build Validation.

† Full evaluation (`nix eval` toplevel drvPath) passed for every required
target; the harness-level `sudo` block prevented the literal `dry-build`
command, but no reachable functional check was skipped as a result.

**Overall Grade: A (99%)**

## Result: PASS
