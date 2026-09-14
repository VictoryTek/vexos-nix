# GNOME Parity Bucket B — Specification

## Current State Analysis

Per `gnome_to_noctalia_parity_audit.md`, bucket B is native-setting-only gaps
between the GNOME role and the Hyprland/Noctalia role. Re-verified every item
against live binaries at the pinned versions rather than trusting the audit's
first pass:

- **B1 caffeine, B2 notifications, B3 theme_mode, B7 screenshot** — confirmed
  as real bar widget tokens by grepping each `*_widget_definition.cpp`'s
  `.type = "..."` field directly in the pinned Noctalia source
  (`/nix/store/28k1r6zxsvqhdjrcvy3xhdyvszilv4wm-source`): `"caffeine"`,
  `"notifications"`, `"theme_mode"` (**underscore** — the docs directory is
  named `theme-mode.mdx` with a hyphen, which would have been a wrong TOML
  key if copied from the filename), `"screenshot"`. None are in
  `bar.default.end` today.
- **B4 control-center shortcuts** — re-read `docs/user/control-center/
  shortcuts.mdx` fully this pass (the original audit only skimmed it): "When
  no `[[control_center.shortcuts]]` entries are defined, the default set is:
  `wifi`, `bluetooth`, `caffeine`, `nightlight`, `notification`,
  `power_profile`" — already 6 of 6 (the documented max), already a
  reasonable GNOME-quick-settings equivalent. **No change needed. Dropped
  from this implementation** — declaring the same 6 explicitly would be
  redundant config with zero behavior change, which the project's Simplicity
  principle rules out.
- **B5 GTK window button layout** — verified with binary evidence, not
  inference: `strings` on the actual installed
  `libgtk-4.so` (`/nix/store/hjp25ksf3axb4czp7sllvzl1bkpfwsyg-gtk4-4.20.3`)
  contains literal `org.gnome.desktop.wm.preferences` and `button-layout`
  string references — GTK4 itself reads this GSettings key for its own CSD
  headerbar buttons, independent of window manager. The schema
  (`org.gnome.desktop.wm.preferences.gschema.xml`) ships in
  `gsettings-desktop-schemas`, already installed for the Hyprland role
  specifically for this class of GTK-outside-GNOME behavior (see that
  package's existing comment in `modules/hyprland-desktop.nix`). Setting the
  same dconf key GNOME sets closes this gap with no new package.
- **B6 focus-follows-activation** — verified with `Hyprland --verify-config`
  against the actual installed binary
  (`/nix/store/vrjgp472fp0crj02mflylcwg95pn4d6p-hyprland-0.55.4`):
  `misc { focus_on_activate = true }` parses as `config ok`; a deliberately
  misspelled key (`focus_on_activateXYZ`) is rejected with `config option
  <misc:focus_on_activateXYZ> does not exist` — proving the check actually
  discriminates, not just that the file parses.

`files/hypr/hyprland.conf` is the **one-time seed file**
(`home.activation.seedHyprlandConf` in `home/dank-material-shell.nix` only
copies it if `~/.config/hypr/hyprland.conf` does not already exist). This
host has already booted Hyprland during prior testing this session, so its
live config is very likely already user-owned and **will not** pick up B6
from a rebuild. This must be surfaced to the user, not silently assumed.

## Problem Definition

Close bucket B: 4 missing bar widgets, 1 GTK-decoration dconf key, 1 Hyprland
`misc` option. B4 is settled as "no work needed," not implemented.

## Proposed Solution

### Implementation Steps

1. **`home/noctalia.nix`** — extend `bar.default.end` with the four new
   widgets, grouped with the existing status icons:
   `end = [ "tray" "caffeine" "notifications" "network" "bluetooth" "volume"
   "battery" "theme_mode" "screenshot" "session" ]`. Notification/caffeine
   toggles sit with the other status-style icons; the mode toggle and
   screenshot action sit just before `session`, mirroring GNOME's rightmost
   power/session-menu convention. Add
   `widget.notifications.hide_when_no_unread = true` (confirmed field in
   `example.toml`) so it doesn't sit as a permanently-lit icon when there's
   nothing to show — closer to how GNOME's notification indicator behaves.
2. **`modules/hyprland-desktop.nix`** — add
   `"org/gnome/desktop/wm/preferences".button-layout =
   "appmenu:minimize,maximize,close";` to the existing
   `programs.dconf.profiles.user.databases` settings block (same block that
   already carries the `org/gnome/system/dns-sd` key), matching
   `modules/gnome.nix`'s value exactly.
3. **`files/hypr/hyprland.conf`** — add a `misc { focus_on_activate = true }`
   block. Placed near the top-level settings, not inside the Noctalia
   keybind section.

### Dependencies

None new — all four widgets, the dconf key, and the Hyprland option are
already available at the pinned versions in use.

### Configuration Changes

None outside the three files above.

### Risks and Mitigations

- **Risk:** B6 will not reach a host that already has a user-owned
  `~/.config/hypr/hyprland.conf`. **Mitigation:** call this out explicitly in
  the summary — the user needs to add the line by hand to their live file (or
  accept losing any of their own hand-edits by deleting it to force a
  reseed). Not silently assumed to "just work" on rebuild.
- **Risk:** `notifications` widget with `hide_when_no_unread = true` could
  make it look broken/absent if the user expects to always see a bell icon.
  **Mitigation:** this is the documented, intentional field for exactly this
  UX; easy to flip back to `false` if unwanted.
- **Risk:** Noctalia's validator only warns on unknown keys (does not fail
  the build) — verified again this pass with a negative control in the prior
  wallpaper-hook work. **Mitigation:** every new key here was checked against
  a live `.type = "..."` / field registration or `--verify-config`, not
  copied from a doc filename or recalled from memory.
