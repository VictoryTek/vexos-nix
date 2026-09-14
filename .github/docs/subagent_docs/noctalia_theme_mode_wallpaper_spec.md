# Noctalia Light/Dark Wallpaper Switching — Specification

## Current State Analysis

GNOME switches the wallpaper with the color scheme natively: `modules/gnome.nix`
sets both `picture-uri` (light) and `picture-uri-dark` under
`org/gnome/desktop/background`, and gnome-settings-daemon swaps between them
whenever `color-scheme` changes. The Hyprland/Noctalia variant has no
equivalent, so switching to light mode restyles the shell but leaves the dark
wallpaper in place.

Verified against the pinned Noctalia source
(`/nix/store/28k1r6zxsvqhdjrcvy3xhdyvszilv4wm-source`, v5.1.0, flake.lock rev
`c7b9197a`) — schema, `docs/user/**`, and the shell sources — not inferred:

- **There is no native mode → wallpaper binding.** `wallpaper.directory_light`
  / `directory_dark` only choose which folder the *picker panel* and
  *automatic rotation* browse (`docs/user/desktop/wallpaper.mdx`: "Theme-aware
  directories … are used when the shell is in Light or Dark mode; Auto mode
  falls back to `directory`"), not which wallpaper is applied.
- `[[wallpaper.favorite]]`'s `theme_mode` field runs the *opposite*
  direction: `wallpaper_panel.cpp`'s `wallpaperFavoriteFromTheme()` captures
  the current theme into the favorite, and `applyWallpaperSelection()` applies
  a favorite's stored theme when that wallpaper is picked. Wallpaper → mode,
  not mode → wallpaper.
- **The `theme_mode_changed` hook is the intended mechanism.** Per
  `docs/user/automation/hooks.mdx` it fires "after theme templates are
  applied, when the resolved `[theme].mode` changes between `light` and
  `dark`", and sets `NOCTALIA_THEME_MODE` (`light` or `dark` — `auto` only
  ever appears in `NOCTALIA_THEME_MODE_CONFIGURED`). Hook values are shell
  command strings.
- `noctalia msg wallpaper-set <path>` sets every connected monitor and is
  "persisted to `settings.toml` (per-monitor entries plus
  `wallpaper.default.path`)" (`docs/user/ipc/media-and-ui.mdx`), so the
  correct wallpaper is restored on the next boot without a startup hook.
- Runtime mode changes persist: the config stack loads
  `~/.local/state/noctalia/settings.toml` last and it "wins when it contains
  the same setting as your hand-written config layer"
  (`docs/user/configuration/index.mdx`) — that file lives outside `~/.config`
  specifically so the GUI can save "when your config directory is read-only,
  for example on NixOS". So the declarative `theme.mode = "dark"` in
  `home/noctalia.nix` does not block toggling.
- Both wallpapers are already deployed to
  `~/Pictures/Wallpapers/vex-bb-{light,dark}.jxl` (home-manager symlinks,
  verified on the live host), and Noctalia decodes `.jxl` natively
  (`src/render/core/image_decoder.cpp` links libjxl; `.jxl` is in
  `directory_scanner.cpp`'s extension list).
- The `vex-bb-{light,dark}.jxl` naming is already load-bearing repo-wide —
  `modules/branding-display.nix` copies those exact two filenames per role.

## Problem Definition

Switching the Hyprland/Noctalia variant to light mode does not switch the
wallpaper, unlike GNOME. Close the gap, per the standing goal of keeping the
Hyprland variant as close to the GNOME setup as possible.

## Proposed Solution

Add a `hooks.theme_mode_changed` entry to `programs.noctalia.settings` in
`home/noctalia.nix` that calls `noctalia msg wallpaper-set` with the
mode-matching wallpaper.

Because `NOCTALIA_THEME_MODE` is exactly `light` or `dark` and the deployed
files are exactly `vex-bb-light.jxl` / `vex-bb-dark.jxl`, the hook needs no
shell conditional — the env var interpolates directly into the filename:

```nix
hooks.theme_mode_changed =
  "${noctaliaBin} msg wallpaper-set ${wallpaperDir}/vex-bb-$NOCTALIA_THEME_MODE.jxl";
```

This is deliberately the whole implementation: no wrapper script, no
derivation, no conditional. The env-var-to-filename coupling is the one
non-obvious part and gets a comment naming it.

`theme.source = "wallpaper"` (already set) means the palette regenerates from
whichever image is applied, so the accent colors follow the mode too — the
same end result GNOME produces. No hook loop is possible: setting a wallpaper
does not change the mode, so `theme_mode_changed` cannot re-fire.

The binary is referenced by absolute store path
(`config.programs.noctalia.package`) rather than bare `noctalia`, matching how
`home/dank-material-shell.nix` references `${pkgs.wireplumber}/bin/wpctl` and
`${pkgs.tail-tray}/bin/tail-tray` — hooks are spawned by the shell process and
should not depend on session `PATH`.

### Implementation Steps

1. `home/noctalia.nix` — add a `hooks` block to `programs.noctalia.settings`
   with `theme_mode_changed` as above, commented to explain the
   env-var/filename coupling and why `directory_light`/`directory_dark` are
   *not* what drives this.

### Dependencies

None. No new package, no new flake input — `noctalia msg` is the shell's own
CLI, already installed by the existing Home Manager module.

### Configuration Changes

None outside `home/noctalia.nix`. No new `vexos.*` options.

### Risks and Mitigations

- **Risk:** The hook only fires on *change*, not at startup, so a first boot
  whose persisted mode disagrees with the persisted wallpaper would show a
  mismatch. **Mitigation:** `wallpaper-set` persists the applied wallpaper to
  `settings.toml`, so mode and wallpaper are written together and stay in
  sync across reboots. A `started` hook would only be needed if something
  changed the mode while Noctalia was not running, which cannot happen (the
  mode lives in Noctalia's own state file).
- **Risk:** A renamed or missing wallpaper file makes `wallpaper-set` fail
  silently. **Mitigation:** the `vex-bb-{light,dark}.jxl` names are already
  enforced repo-wide by `modules/branding-display.nix`, which would fail to
  build if a role's pair were renamed.
- **Risk:** Noctalia's `checkConfig` validator only warns on an unknown key,
  so a typo'd hook name would silently no-op. **Mitigation:** `hooks` and
  `theme_mode_changed` were both matched against
  `src/config/config_types.h:1396`
  (`{HookKind::ThemeModeChanged, "theme_mode_changed", ""}`), and the
  rendered TOML is inspected directly in Phase 3.
