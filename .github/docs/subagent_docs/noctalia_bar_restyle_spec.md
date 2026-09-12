# Noctalia bar restyle — spec

## Current state analysis

`home/noctalia.nix:159-219` (`bar.default`) configures the Hyprland role's status
bar via Noctalia v5's Home Manager module (`inputs.noctalia.homeModules.default`,
pinned `v5.1.0`). The bar currently:

- Groups every widget into rounded "capsule" pills (`capsule = true`,
  `capsule_fill = "surface_variant"`, `radius = 12`, `capsule_thickness = 0.76`)
  via a `capsule_group` list (`nav`, `clock`, `media`, `status`).
- Only exposes 4 widgets total: `workspaces`, `clock`, `media`, `tray` + `session`.
  No `network`, `bluetooth`, `volume`, or `battery` widgets are configured.
- `thickness = 34`, `padding = 14`, `widget_spacing = 6`, no `background_opacity`
  set (defaults to fully opaque).

This produces a bar of large, high-contrast rounded-pill segments — visually
heavier and more grouped than the reference screenshot, which shows a flatter,
slimmer, more translucent bar with individual icons (not pill-grouped) and a
richer end-of-bar widget set (network interface name, bluetooth, volume %,
battery %).

## Problem definition

Restyle the Hyprland bar to match the reference screenshot's flatter, slimmer,
more translucent look, and add the missing system-status widgets (network,
bluetooth, volume, battery) that the screenshot shows but the current config
lacks.

## Research (upstream schema verification)

Verified directly against the pinned `noctalia-shell v5.1.0` source
(`/nix/store/28k1r6zxsvqhdjrcvy3xhdyvszilv4wm-source`, fetched via
`nix flake prefetch github:noctalia-dev/noctalia-shell/v5.1.0`), specifically
`example.toml` and `docs/user/bar/widgets/{network,bluetooth,volume,battery}.mdx`
(no separate JSON schema file exists; `home-module.nix` accepts `settings` as
freeform TOML, validated at build time by `noctalia config validate`, per the
existing top-of-file comment in `home/noctalia.nix`):

- Top-level bar style defaults upstream: `capsule = false`,
  `background_opacity = 1.0`, `shadow = true`, confirming a flat (non-pill)
  bar is the upstream-normal look, not a departure requiring extra config.
- Widget names for the missing widgets: `"network"`, `"bluetooth"`, `"volume"`,
  `"battery"` — all valid bare tokens in a bar lane (`end` list), same as the
  existing `"media"`, `"tray"`, `"session"` tokens.
- Per-widget label defaults already match the screenshot with **no overrides
  needed**:
  - `network`: `show_label = true` (default) → shows SSID/interface name, e.g.
    `enp2s0`.
  - `battery`: `show_label = true`, `label_content = "percent"` (defaults) →
    shows e.g. `21%`.
  - `volume`: `show_label = true` (default) → shows e.g. `45%`.
  - `bluetooth`: `show_label = false` (default) → icon only, matching the
    screenshot (no device name shown next to the Bluetooth glyph).

No Context7 lookup applies here — this is a Nix/TOML config edit against an
existing, already-verified flake input, not a new dependency or library
integration.

## Proposed solution

Edit only `home/noctalia.nix`'s `bar.default` block (`home/noctalia.nix:159-219`):

1. Turn off capsule grouping: `capsule = false`, and delete the `capsule_group`
   list entirely (no groups needed once nothing is pilled).
2. Replace the `group:*` lane tokens with plain widget tokens:
   - `start = [ "workspaces" ]`
   - `center = [ "clock" ]`
   - `end = [ "media" "tray" "network" "bluetooth" "volume" "battery" "session" ]`
3. Slim the bar to read closer to the screenshot: reduce `thickness` (34 → 30)
   and `padding` (14 → 10); keep `widget_spacing = 6`.
4. Add `background_opacity = 0.85` for the translucent look visible in the
   screenshot (wallpaper showing through). Theme itself stays
   `theme.source = "wallpaper"` / `mode = "dark"` (per user's answer: keep the
   automatic Material-You palette rather than hardcoding hex colors — this is
   what "look nice with the theming" means here, since the palette already
   adapts to the wallpaper).
5. Keep `concave_edge_corners = true`, `margin_edge = 0`, `margin_ends = 0`,
   `radius = 12` unchanged — those govern the edge shape, not the pill/flat
   question, and the screenshot's bar still meets the screen edge.

No other files change. No new flake inputs. No `system.stateVersion` changes.
Module Architecture Pattern is unaffected — this is a single home-manager leaf
module edit, not a role-conditional addition.

## Risks and mitigations

- **Risk:** `noctalia config validate` flags an unknown/misspelled key only as
  a warning, not a build failure (documented already at the top of the file).
  **Mitigation:** every key used here is copied verbatim from the upstream
  `example.toml`/docs above; still re-run
  `noctalia config validate ~/.config/noctalia/config.toml` after building, per
  the file's existing standing instruction, and treat any warning as a defect.
- **Risk:** removing `capsule_group` while widgets are still declared as bare
  tokens (not `group:` tokens) could error if Noctalia expects every `end`
  entry to resolve to either a widget id or a group id.
  **Mitigation:** this is exactly the upstream default shape (`example.toml`'s
  own `end` list uses bare widget tokens with no groups at all), so it's a
  verified-safe pattern, not a guess.
- **Risk:** none of the new widgets (`network`, `bluetooth`, `volume`,
  `battery`) were present before — first activation could surface a NetworkManager/
  UPower/PipeWire dependency issue.
  **Mitigation:** all three backends (NetworkManager, upower, pipewire) are
  already enabled elsewhere in this repo for the desktop role (per the Issue 1
  research pass), so no new system service needs enabling.

## Implementation steps

1. Edit `home/noctalia.nix` `bar.default` per the Proposed Solution above.
2. Build-validate via `nix flake show --impure` and
   `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` (and
   `-nvidia`, `-vm` variants per the repo's standard review checklist).
3. Confirm `hardware-configuration.nix` still untracked and `stateVersion`
   unchanged (neither is touched by this edit, but checked per standard
   Phase 3 checklist).
