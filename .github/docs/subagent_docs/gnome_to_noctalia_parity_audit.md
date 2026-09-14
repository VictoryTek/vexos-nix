# GNOME → Hyprland/Noctalia Parity Audit

Standing goal: the Hyprland/Noctalia variant should land as close to the GNOME
setup as possible, custom Noctalia plugins included. This is the punch list.

## Method

Compared key-by-key:

- **GNOME side:** `modules/gnome.nix` (universal dconf + extension list),
  `modules/gnome-desktop.nix` (role overlay: accent, favourites, app-folders,
  mic keybind), `home/gnome-common.nix` (cursor/icon/GTK).
- **Hyprland side:** `home/noctalia.nix`, `home/dank-material-shell.nix`,
  `modules/hyprland-desktop.nix`, `files/hypr/hyprland.conf`.
- **Capability surface:** the pinned Noctalia v5.1.0 source
  (`/nix/store/28k1r6zxsvqhdjrcvy3xhdyvszilv4wm-source`, flake.lock rev
  `c7b9197a`) — `config_schema.cpp`, `example.toml`, `docs/user/**`. Widget
  and setting names below were matched against real schema registrations or
  upstream docs, not recalled.

Verification status is marked per row. Anything marked **[verify]** needs a
live Hyprland session to settle and should not be treated as a finding yet.

Plugin feasibility note: `[plugins]` is declarative-friendly, and a source
with `kind = "path"` is described upstream as "an immutable local directory
Noctalia treats read-only … **Ideal for local development or Nix-managed
plugins**". So custom plugins can live in this repo (e.g.
`files/noctalia-plugins/`), deploy via home-manager, and be registered and
enabled entirely declaratively. Plugins are Luau scripts in isolated VMs and
can provide bar widgets, desktop widgets, panels, control-center shortcuts,
launcher providers, and headless services. `noctalia plugins` is the offline
author toolchain.

---

## A. Already at parity — do not re-litigate

| GNOME | Noctalia/Hyprland equivalent | Status |
|---|---|---|
| `background` picture-uri + picture-uri-dark | `wallpaper.default.path` + `hooks.theme_mode_changed` | ✅ shipped this session |
| `picture-options = "zoom"` | `wallpaper.fill_mode` default `"crop"` (same semantics: scale to fill, crop overflow) | ✅ by default, not explicitly declared |
| `interface icon-theme = kora` | `gtk.iconTheme` in `home/gnome-common.nix` — imported **unconditionally**, so Hyprland gets it too | ✅ |
| `interface clock-format = 12h` | `shell.time_format = "12h"` + `widget.clock.format` | ✅ |
| `interface color-scheme = prefer-dark` | `theme.mode = "dark"` | ✅ |
| `screensaver lock-enabled = false`, `lock-delay = 0` | hypridle with DPMS-off only, no `lock_cmd` | ✅ |
| `session idle-delay = 300` | hypridle `timeout = 300` | ✅ |
| `system/dns-sd display-local = merged` | same dconf key set in `modules/hyprland-desktop.nix` | ✅ |
| ext: appindicator (tray) | native `tray` bar widget | ✅ |
| ext: dash-to-dock (LEFT/autohide/intellihide) | `dock.position/auto_hide/smart_auto_hide` | ✅ |
| ext: tailscale-status | `tail-tray` service | ✅ shipped this session |
| ext: tiling-assistant | Hyprland tiles natively (different UX, same capability) | ✅ |
| `favorite-apps` (7 incl. conditional codium) | `dock.pinned` / `launcher.pinned` = `basePinnedApps`, same list incl. the same codium condition | ✅ |
| mute-mic-on-login service | same unit in `home/dank-material-shell.nix` | ✅ |
| GNOME default-app Flatpaks | `vexos.gnome.flatpakInstall.apps` set in `modules/hyprland-desktop.nix` | ✅ |
| Hot corner → Activities | `hot_corners.top_left` → `window-switcher` | ✅ |

---

## B. Native setting — config-only, no plugin needed

Cheapest wins. Each is a known key with a known value.

| # | Gap | Fix | Where | Verified |
|---|---|---|---|---|
| B1 | **Caffeine has no bar presence.** GNOME runs the caffeine extension; Noctalia ships a native `caffeine` bar widget but it is not in any lane. | add `"caffeine"` to `bar.default.end` | `home/noctalia.nix` | widget type confirmed in upstream widget list |
| B2 | **No notifications indicator.** GNOME shows one; here it is `$mod+N` only. | add `"notifications"` to `bar.default.end` (widget exists; `hide_when_no_unread` available) | `home/noctalia.nix` | confirmed (`[widget.notifications]`) |
| B3 | **No light/dark toggle affordance.** GNOME exposes one in quick settings. | add `"theme_mode"` bar widget (native type) | `home/noctalia.nix` | confirmed (`theme_mode_widget.cpp`) |
| B4 | **Control-center shortcuts unconfigured** — GNOME's quick-settings tile set has no counterpart; Noctalia's Home tab is on defaults. | declare `[[control_center.shortcuts]]` (wifi, bluetooth, nightlight, notification, wallpaper, session) | `home/noctalia.nix` | confirmed in `example.toml` |
| B5 | **Window button layout.** GNOME sets `appmenu:minimize,maximize,close`; Hyprland has no SSD, and GTK CSD apps read `gtk-decoration-layout`, which is unset here. | set GTK decoration layout to match | `home/gnome-common.nix` or a Hyprland-gated home module | GNOME key confirmed; GTK side **[verify]** |
| B6 | **Focus stealing.** GNOME runs steal-my-focus-window so activation raises the window; Hyprland's `focus_on_activate` is unset (default off). | `focus_on_activate = true` | `files/hypr/hyprland.conf` (seeded file — note it is user-owned after first boot) | Hyprland option name **[verify]** |
| B7 | **Screenshot affordance.** GNOME has a quick-settings screenshot entry; here it is Print-key only. | native `screenshot` bar widget and/or a control-center shortcut | `home/noctalia.nix` | widget type confirmed |

---

## C. Hook-able — use the `[hooks]` mechanism

Same pattern as the wallpaper fix just shipped.

| # | Gap | Approach | Verified |
|---|---|---|---|
| C1 | **Mic-mute has no audio feedback.** GNOME's `<Super>backslash` runs a flock-debounced wrapper that plays freedesktop `device-added`/`device-removed` on toggle. The Hyprland bind calls `noctalia msg mic-mute` with no sound and no debounce. | Keep Noctalia's IPC (so the OSD still shows) but restore the sound + flock debounce — either by pointing the keybind at a `writeShellScript` wrapper that calls both, or via a hook. Note `hooks` has no mic event, so **the keybind wrapper is the right vehicle**, not a hook. | GNOME script read in full; Noctalia hook list has no mic entry — confirmed |
| C2 | **Nothing-to-say parity (always-visible mic state).** GNOME shows mute state permanently. Noctalia's `privacy` widget shows *capture activity* (mic/cam in use), which is a different signal. | Either accept `privacy` as close-enough, or a `custom_button` bar widget bound to `wpctl` state. A `custom_button` can run commands but polling state for its glyph is the hard part → may slide to bucket D. | `privacy` widget + `custom_button` both confirmed; state-polling capability **[verify]** |

---

## D. Needs a custom Noctalia plugin

| # | Gap | Plugin shape | Notes |
|---|---|---|---|
| D1 | **Background logo.** `background-logo` extension paints the VexOS mark on the desktop (light/dark variants, always visible). `modules/branding-display.nix` already deploys the assets. No Noctalia equivalent exists. | **desktop widget** plugin (the desktop-widget schema has a `plugin_settings` key, so plugins can supply desktop widget types) | Highest-visibility branding gap. Needs a check for whether a native image/picture desktop-widget type already exists before writing one — the schema treats `type` as a runtime-resolved string, so this could not be settled statically. **[verify]** |
| D2 | **Custom app folders.** `modules/gnome-desktop.nix` defines 5 folders (Games, Game Utilities, Office, Utilities, System) with ~40 explicit app assignments. Noctalia's launcher `categories = true` gives *freedesktop* category chips only — no user-defined folders with hand-picked membership. | **launcher provider** plugin, or accept category chips as the substitute | Largest single behavioral gap. Worth confirming how much the folders are actually used before building this. |

---

## E. Deliberate divergences — confirm intent before "fixing"

These differ by design. Listing them so they are decided, not drifted into.

| # | GNOME | Noctalia | Question |
|---|---|---|---|
| E1 | `accent-color = "blue"` (fixed) | `theme.source = "wallpaper"` — Material-You palette derived from the wallpaper | Do you want the Hyprland accents pinned blue to match GNOME, or is wallpaper-derived theming the thing you actually prefer here? These are mutually exclusive. |
| E2 | AlphabeticalAppGrid extension (alphabetical app grid) | `launcher.sort_by_usage = true` (frequency-sorted) | GNOME sorts alphabetically; Noctalia is set to sort by usage. Flip to match, or keep? |
| E3 | blur-my-shell | `shell.panel.transparency_mode` (`solid`/`soft`/`glass`) + bar `background_opacity = 0.85` | Currently unset (`solid` default) while the bar is translucent. `glass`/`soft` would be the closer analogue — worth a look. |
| E4 | VRR off by default, opt-in via `vexos.gnome.variableRefreshRate.enable` | Hyprland VRR is a monitor/render setting | Only matters if you turn it on; no action while it stays off. |

---

## F. Needs live verification before classifying

| # | Item | Why it is open |
|---|---|---|
| F1 | **Compositor cursor theme.** `home/gnome-common.nix` sets `home.pointerCursor` + `gtk.cursorTheme` (Bibata, size 24) unconditionally, so GTK apps are covered. Whether Hyprland's *own* cursor (over the desktop, bar, and empty workspaces) picks it up depends on `XCURSOR_THEME`/hyprcursor wiring, which is not declared anywhere for this role. | Look at the actual cursor over the Hyprland desktop vs. inside a GTK app. If they differ, this becomes a bucket-B fix. |
| F2 | D1's native-widget question, F-flagged above. | Requires listing desktop widget types on a running shell. |
| F3 | Whether the app-folders (D2) are worth a plugin at all. | Usage question, only you can answer. |

---

## Recommended order

1. **Bucket B in one pass** (B1–B4, B7 are pure `home/noctalia.nix` settings; B5/B6 need their own verification). Cheapest visible progress, one commit.
2. **Settle bucket E** — these are decisions, not work, and E1/E2 change what "parity" even means for later items.
3. **C1** (mic-mute sound + debounce) — self-contained, restores a behavior you lost outright.
4. **F1** cursor check — one look, may add a B-item.
5. **D1 background logo plugin** — the branding gap, and a good first plugin to learn the Luau/manifest workflow on.
6. **D2 app folders** — largest effort, do last and only if the folders matter to you.
