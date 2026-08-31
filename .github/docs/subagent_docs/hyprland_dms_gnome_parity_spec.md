# Hyprland + DMS GNOME-Parity Spec

## Current State Analysis

`vexos.desktop.environment` supports `"gnome" | "cosmic" | "hyprland"`
(modules/desktop-environment.nix). GNOME sets a large set of behavioral
defaults through the system dconf database (modules/gnome.nix,
modules/gnome-desktop.nix) plus GDM `autoLogin`. The Hyprland role
(modules/hyprland-desktop.nix + home/dank-material-shell.nix) currently ships
DankMaterialShell (DMS) at stock/unconfigured defaults — no wallpaper, no
dock, default (auto/24h-locale) clock, no auto-login, no mic-mute keybind
equivalent.

DMS's user-facing state is **not** a gschema — it is two flat JSON files
written by the Home Manager module (`inputs.dms.homeModules.dank-material-shell`,
read from the flake input at `distro/nix/home.nix`):

- `programs.dank-material-shell.settings` → `~/.config/DankMaterialShell/settings.json`
  (persistent user preferences — dock, clock format, lock timeouts, theming)
- `programs.dank-material-shell.session` → `~/.local/state/DankMaterialShell/session.json`
  (session/runtime state — wallpaper path, light/dark mode, pinned apps)

Both are freeform `pkgs.formats.json` attrsets (no NixOS option schema to
validate against), so field names/defaults were confirmed by reading the
shipped QML source directly at the pinned input's store path
(`quickshell/Common/settings/SettingsSpec.js` and `SessionSpec.js`, which list
every key's default) rather than guessed. Source pin: `AvengeMedia/DankMaterialShell`
rev `069ddab041c738236a8910e4c39b65d9628d3018` (flake.lock, matches the current
`inputs.dms`).

## Problem Definition

Port the GNOME defaults that have a real DMS/Hyprland equivalent, so a fresh
Hyprland install looks and behaves consistently with the GNOME role instead of
booting to a stock, unthemed DMS session. Explicitly do **not** invent
functionality DMS doesn't have.

## Mapping: GNOME dconf key → Hyprland/DMS equivalent

| GNOME (modules/gnome.nix / gnome-desktop.nix) | Hyprland/DMS equivalent | File |
|---|---|---|
| `org/gnome/desktop/background` picture-uri(-dark) | DMS `session.json`: `wallpaperPath`/`wallpaperPathLight`/`wallpaperPathDark` + `perModeWallpaper: true` | home/dank-material-shell.nix (session) |
| `org/gnome/desktop/interface` color-scheme=prefer-dark | DMS `session.json`: `isLightMode: false` | home/dank-material-shell.nix (session) |
| `org/gnome/desktop/interface` clock-format=12h | DMS `settings.json`: `clockFormat: "12h"` (default `"auto"`) | home/dank-material-shell.nix (settings) |
| `org/gnome/desktop/interface` cursor-theme/icon-theme | Already DE-agnostic via `home/gnome-common.nix` (`gtk.cursorTheme`/`gtk.iconTheme`/`home.pointerCursor`), imported unconditionally by home-desktop.nix. **No change needed.** | — |
| `org/gnome/desktop/interface` accent-color=blue | **Skip.** DMS already runs `enableDynamicTheming = true` (matugen extracts a Material-You palette from the wallpaper) — a static accent contradicts that existing design choice. | — |
| `org/gnome/shell/extensions/dash-to-dock` position=LEFT, autohide, intellihide | DMS `settings.json`: `showDock: true`, `dockPosition: 2` (enum `Position.Left`; Top=0/Bottom=1/Left=2/Right=3 — confirmed in `SettingsData.qml`), `dockAutoHide: true`, `dockSmartAutoHide: true` (closest match to intellihide) | home/dank-material-shell.nix (settings) |
| `org/gnome/shell` favorite-apps | DMS `session.json`: `pinnedApps` / `barPinnedApps` (array of desktop-file IDs *without* the `.desktop` suffix, per `Paths.moddedAppId` / `DesktopEntries` convention used elsewhere in the shell) | home/dank-material-shell.nix (session) |
| `org/gnome/desktop/screensaver` lock-enabled=false | DMS `settings.json`: `acLockTimeout`/`batteryLockTimeout` already default to `0` (disabled) in `SettingsSpec.js` — matches GNOME's intent with **no config needed**. | — |
| `org/gnome/session` idle-delay=300 | No direct DMS equivalent found (DPMS fade timing is a separate, unrelated setting: `fadeToDpmsGracePeriod`). **Skip** — do not guess a mapping. | — |
| `org/gnome/settings-daemon/.../mute-mic` custom keybinding (`<Super>backslash`) | Hyprland keybind → `dms ipc call mic mute` (native DMS IPC target, confirmed in `DMSShellIPC.qml`: `target: "mic"`, `function mute()`). Simpler than GNOME's flock/wpctl script since DMS owns mic state + OSD (`osdMicMuteEnabled` already defaults true). | files/hypr/hyprland.conf |
| `modules/gnome-desktop.nix` `mute-mic-on-login` systemd service | Same pattern, ported verbatim (wpctl, not `dms ipc`, so it works even before `dms.service` is up) | home/dank-material-shell.nix |
| GDM `services.displayManager.autoLogin` | Same NixOS option — DMS's greeter module (`distro/nix/greeter.nix`) reads `config.services.displayManager.autoLogin` directly and wires it into greetd's `initial_session`, resolving the command via `config.services.displayManager.sessionData.autologinSession`. That resolves from `services.displayManager.defaultSession`, which must be set to `"hyprland-uwsm"` (the UWSM-registered session — see the existing warning comment in modules/hyprland-desktop.nix about the two Hyprland session entries). | modules/hyprland-desktop.nix |
| `security.pam.services.gdm-autologin.enableGnomeKeyring` | Best-effort mirror: `security.pam.services.greetd.enableGnomeKeyring = true` (same rationale — no-op for the actual autologin bypass, kept for interactive re-logins) | modules/hyprland-desktop.nix |
| `org/gnome/system/dns-sd` display-local=merged | Still applicable — Nautilus/GVfs is installed under Hyprland too (modules/hyprland-desktop.nix already lists `nautilus`), and this key is read by GVfs, not GNOME Shell. Needs its own `programs.dconf.profiles.user` declaration since Hyprland doesn't import modules/gnome.nix. `programs.dconf.enable` is already `true` there. | modules/hyprland-desktop.nix |
| `org/fedorahosted/background-logo-extension` | GNOME Shell extension — no DMS equivalent exists. **Skip.** | — |
| `org/gnome/settings-daemon/plugins/housekeeping` donation-reminder | GNOME-Software-specific. **Skip.** | — |
| `org/gnome/desktop/app-folders` (Games/Office/Utilities/System folders) | No DMS category/folder feature found in the settings schema. **Skip** — do not fabricate one. | — |
| `org/gnome/desktop/wm/preferences` button-layout | Hyprland has no server-side window decorations in the GNOME sense; DMS doesn't manage per-window titlebar buttons. **Not applicable.** | — |

## Implementation Steps

1. **modules/hyprland-desktop.nix**
   - Add `services.displayManager.autoLogin = { enable = true; user = config.vexos.user.name; };` and `services.displayManager.defaultSession = "hyprland-uwsm";`.
   - Add `security.pam.services.greetd.enableGnomeKeyring = true;`.
   - Add a `programs.dconf.profiles.user` declaration (mirrors the shape in modules/gnome.nix) carrying only the `org/gnome/system/dns-sd` `display-local = "merged"` key.

2. **home/dank-material-shell.nix** (inside the existing `isHyprland` mkIf block)
   - Populate `programs.dank-material-shell.settings` with: `clockFormat`, `showDock`, `dockPosition`, `dockAutoHide`, `dockSmartAutoHide`.
   - Populate `programs.dank-material-shell.session` with: `isLightMode`, `perModeWallpaper`, `wallpaperPath`, `wallpaperPathLight`, `wallpaperPathDark` (pointing at the same `~/Pictures/Wallpapers/vex-bb-{light,dark}.jxl` paths home-desktop.nix already deploys), `pinnedApps`/`barPinnedApps` (same app set as `modules/gnome-desktop.nix` favorite-apps, translated to bare IDs).
   - Add the `mute-mic-on-login` systemd user service (ported from modules/gnome-desktop.nix, unchanged logic).

3. **files/hypr/hyprland.conf**
   - Add `bind = $mod, backslash, exec, dms ipc call mic mute` next to the existing DMS keybind block.

## Dependencies

No new flake inputs. `inputs.dms` is already pinned; no version bump needed —
all fields used exist at the currently locked rev (verified directly against
the store path, not assumed from memory/training data).

## Risks and Mitigations

- **`pinnedApps` ID format is inferred, not exhaustively proven** for
  arbitrary non-core apps (confirmed convention via `Paths.moddedAppId`/
  `DesktopEntries` usage elsewhere, but no single code path was found that
  definitively resolves a *non-core* pinned app string end-to-end). Low risk:
  if wrong, the dock/bar simply shows no pinned icons for those entries — it
  degrades gracefully, doesn't break the build or session.
- **`dockSmartAutoHide` vs `dockAutoHide`+`intellihide` is an approximation**,
  not an exact behavioral match — documented as the closest available option.
- **`idle-delay` (screen blank timing) has no mapping** — left alone rather
  than guessing; DMS's DPMS fade grace period is a materially different knob.
- All values are static home-manager-managed JSON going through the existing,
  already-proven `programs.dank-material-shell.settings`/`session` → `xdg.configFile`/`xdg.stateFile` mechanism (home.nix in the DMS flake, already reviewed above) — no new activation scripts, no risk to the seeded-once `hyprland.conf` pattern.
- `services.displayManager.defaultSession = "hyprland-uwsm"` is a new
  assertion-relevant value — Phase 3 build validation must run
  `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` (Hyprland-capable
  variant) to catch any assertion failure from the greeter module
  (`cfgAutoLogin.enable -> sessionData.autologinSession != null`) at eval time
  rather than at boot.
