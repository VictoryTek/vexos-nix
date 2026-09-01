# Hyprland Neo-Cyberpunk Rice Spec

## Current State Analysis

The Hyprland role currently runs on stock visuals: `files/hypr/hyprland.conf`
has no `general{}`/`decoration{}`/`animations{}` blocks at all (default
Hyprland look — square corners, default green-ish border, no blur, snap
animations). DMS's Material-You theming (`enableDynamicTheming = true`) is
on but no theme is explicitly selected, so it runs on DMS's built-in default
(`currentThemeName: "purple"`). No terminal color scheme is configured.

## Style Analysis (grounded in the actual wallpaper pixels, not eyeballed)

Decoded both wallpapers (`wallpapers/desktop/vex-bb-{dark,light}.jxl` via
`djxl`) and extracted dominant colors via ImageMagick rather than guessing:

- **Dark wallpaper**: background `#050A14` (near-black navy); two glowing
  curved light-trails crossing each other — electric cyan (`#05F4FA` →
  `#0298BA` → `#016D8E`) and amber/ember (`#F9B62E` → `#DD4014` → `#9A1F0E`);
  a muted mauve blend (`#5E3E54`) where the streaks cross; neutral slate-blue
  (`#5D7190`).
- **Light wallpaper**: same duotone, restated on a teal-slate gradient
  background (`#1F2C3B` → `#295564` → `#3C7888`) with lighter cyan
  (`#2A99A9` → pale `#B2C7C8`) and warmer amber (`#A83B23` → `#C99B57`).

**Style verdict**: this is a minimal, elegant duotone-neon aesthetic — cyan +
amber light-trails on deep navy, no glitch/scanline/magenta-maximalism.
Closer to TRON / *Blade Runner 2049* tech-noir than loud Night-City
cyberpunk. "Neo-cyberpunk" / "tech-noir" is the more precise label than
plain "cyberpunk," and it's what the rice below targets: smooth, restrained,
deliberate — not busy.

## Proposed Solution

Three coordinated pieces, all scoped to the Hyprland role only (never
touches the GNOME role's look):

### 1. A custom DMS theme, hand-built from the extracted hex values

DMS supports `currentThemeName: "custom"` + `customThemeFile: <path>` in
`settings.json` (documented in the pinned `inputs.dms`'s
`docs/CUSTOM_THEMES.md`, which even ships its own generic "Cyberpunk
Electric" example theme as a format reference — not reused here since its
green/magenta palette has nothing to do with *our* wallpaper). Full MD3
role-color JSON, `dark` and `light` variants, every hex either taken
directly from the extracted palette above or a deliberately-designed
interpolation between two extracted values (documented per-key below, not
invented from nothing).

Confirmed (`distro/nix/common.nix`) that `enableDynamicTheming` only adds
`pkgs.matugen` as an available tool for per-app template export — it does
not force wallpaper-based auto-generation to override an explicitly selected
`currentThemeName: "custom"`, so the two settings don't fight each other.

`matugen_type: "scheme-expressive"` — a deliberately vivid derivation mode
for the per-app templates DMS/matugen generates (GTK, terminal, etc.),
matching the "elegant but not flat" brief.

### 2. Hyprland `general`/`decoration`/`animations` blocks

Added to `files/hypr/hyprland.conf` (a user-editable, once-seeded file —
same mechanism as the keybinds):

- **`general`**: 2px border, gradient active border running cyan → amber at
  45° (`rgba(05f4faee) rgba(f9b62eee) 45deg`) — this directly re-creates the
  wallpaper's own crossing light-trails as the window border, tying the rice
  to the art rather than picking an arbitrary accent. Inactive border: muted
  navy (`rgba(1c2e49aa)`). `resize_on_border = true` (modern QoL).
- **`decoration`**: 10px rounding, blur on (size 6, passes 3, vibrant) for
  a frosted-glass look under DMS's panels, soft shadow tinted navy
  (`rgba(050a14cc)`) instead of default black.
- **`animations`**: a single custom bezier (`smoothDecel, 0.05, 0.9, 0.1,
  1.0` — pure ease-out, deliberately **no overshoot/bounce**, since "smooth"
  was explicit in the brief) applied to windows/fade/border/workspaces/layers.
- **`misc`**: `disable_hyprland_logo`/`disable_splash_rendering` (stock
  Hyprland branding would undercut a deliberate custom look) and
  `background_color = 0x050a14` (fallback color matches the wallpaper's own
  background before it loads, instead of Hyprland's default black-with-logo).

### 3. Ghostty terminal color scheme (Hyprland role only)

Ghostty is currently installed as a bare package (`home.packages`) with no
`~/.config/ghostty/config` anywhere in the repo, across any role. Rather
than adopt the `programs.ghostty` home-manager module (which would
re-manage the package DMS/home-desktop.nix already installs — redundant),
deploy a plain `xdg.configFile."ghostty/config"` inside the Hyprland-gated
block of `home/dank-material-shell.nix`, matching the existing
`xdg.configFile."starship.toml"` pattern in `home-desktop.nix`. A 16-color
ANSI palette built from the same extracted hex values (background `#050A14`,
foreground near-white cool tint, cyan/amber as the bright-color slots) so
the terminal — the single most-used app, bound to `$mod,Return` — matches
the rest of the rice instead of running Ghostty's stock theme.

## Implementation Steps

1. **`files/dms/vexos-neo-cyberpunk.json`** (new) — the custom DMS theme
   file, `dark`+`light` MD3 roles per the palette above.
2. **`home/dank-material-shell.nix`** — deploy that file via
   `xdg.configFile."DankMaterialShell/themes/vexos-neo-cyberpunk.json"`;
   add `currentThemeName = "custom"`, `customThemeFile = <deployed path>`,
   `matugen_type` lives inside the theme file itself, to the existing
   `settings` attrset. Add a new `xdg.configFile."ghostty/config"` with the
   terminal palette, inside the same `isHyprland` block.
3. **`files/hypr/hyprland.conf`** — add `general`/`decoration`/`animations`
   blocks per above, placed after the existing `misc{}` block.

## Dependencies

None new. `matugen` is already conditionally installed
(`enableDynamicTheming = true`, already set). No new packages.

## Risks and Mitigations

- **`customThemeFile` path must exist before DMS reads it at session
  start**: deployed via `xdg.configFile` (home-manager activation, runs
  before `dms.service` starts per the existing `graphical-session.target`
  ordering already established for this role), so no race.
- **`settings.json` is Nix-managed (static, overwritten every activation)**
  — same precedent already established and accepted in the earlier
  GNOME-parity work for this same file; not a new risk introduced here.
- **Ghostty config is genuinely new territory** (no prior config file in
  this repo for it, in any role) — scoped strictly to the `isHyprland`
  block so the GNOME/COSMIC roles' Ghostty (wherever else it's installed)
  is completely unaffected.
- Visual/subjective correctness (does it actually look good) **cannot be
  verified in this headless environment** — same disclosed limitation as
  the keybind work; worth a screenshot-check by the user after
  `nixos-rebuild switch` + relogin.
