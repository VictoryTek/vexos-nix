# Hyprland Noctalia Bar/Shell Tweaks — Specification

## Current State Analysis

`home/noctalia.nix` configures Noctalia v5.1.0 (pinned `flake.lock` rev
`c7b9197a`) via `programs.noctalia.settings`, a TOML-shaped Nix attrset.
Verified the *actual current* schema directly against the pinned source
(`/nix/store/28k1r6zxsvqhdjrcvy3xhdyvszilv4wm-source`: `example.toml`,
`src/config/schema/config_schema.cpp`, `docs/user/**`) rather than assuming
the existing file's shape is still accurate — this project's own methodology
per the file's header comment ("checked directly against noctalia 5.1.0's
validator"). Findings:

- `bar.default.{start,center,end}` are plain string arrays of widget tokens;
  `"launcher"` and `"session"` are confirmed valid tokens (used in upstream's
  own `example.toml`). The bar currently has **no launcher widget at all** —
  only reachable via a Super-key bind and a hot corner.
- No bar-level (or tray-level) pixel icon-size field exists anywhere in this
  schema — confirmed by grepping every `field(&...)` registration in
  `config_schema.cpp` and cross-checking `assets/translations/en.json`'s
  `settings.schema.bar` key list. The only literal pixel icon-size field in
  the whole schema is `dock.icon_size` (`DockConfig::iconSize`, default 48).
  **User confirmed** "icon size 35" meant the dock, not the bar.
- `widget.tray.hide_passive` (default `true`) hides any StatusNotifierItem
  reporting status `Passive` — apps "that always report Passive" need it set
  `false` (verbatim from `docs/user/bar/widgets/tray.mdx`). Sunshine ships
  its own StatusNotifierItem tray icon directly (no bridge needed, unlike
  GNOME Shell which requires the AppIndicator extension); this default is the
  most likely reason it isn't showing.
- Tailscale has **no tray-icon-capable process at all** under Hyprland:
  `tailscaled` is a headless daemon with no StatusNotifierItem of its own; the
  only tray presence in this repo is `gnomeExtensions.tailscale-status`
  (`modules/gnome.nix`), a GNOME Shell extension with no Hyprland equivalent.
  **User confirmed**: add `pkgs.tail-tray` (nixpkgs, GPL-3.0,
  `mainProgram = "tail-tray"`, Qt/KDE-based, registers a real
  StatusNotifierItem) as a new background tray helper, following the same
  pattern `home/dank-material-shell.nix` already uses for
  `services.hyprpolkitagent`/`services.udiskie` — session helpers GNOME
  provides implicitly that Hyprland needs installed explicitly.
- `shell.panel.session_placement` (default `"attached"`) + `session_position`
  exist (`ShellConfig::PanelConfig::sessionPlacement`/`sessionPosition` in
  `config_schema.cpp`, confirmed field-by-field). Per
  `docs/user/configuration/shell.mdx`: "`attached` ... anchors it to the host
  bar's inward edge" and centers along the *bar*, not the screen;
  `*_position` (`"center"` among other tokens) only takes effect when
  placement is `"floating"`, and then it's a fixed on-screen anchor "same
  vocabulary as notification/OSD position." To get the session/power buttons
  in the center of the *screen*, `session_placement` must be `"floating"`
  with `session_position = "center"`.
- `shell.panel.control_center_placement` (default `"attached"`) governs the
  panel that `network` and `notifications` bar widgets actually open —
  confirmed via `docs/user/bar/widgets/network.mdx` ("Left-click opens the
  Network tab in the control center") and `docs/user/control-center/index.mdx`
  (network/notifications are Control Center tabs, not standalone popups).
  `open_near_click_control_center` (default `false`) is documented verbatim:
  "position attached or floating panels near the click location on the bar
  instead of centering them along the bar." This is exactly the "opens in the
  middle" symptom — the fix is `open_near_click_control_center = true`.
- Autologin: `services.displayManager.autoLogin` + `defaultSession =
  "hyprland-uwsm"` (`modules/hyprland-desktop.nix`) is mechanically identical
  to the working GNOME setup and already GDM-backed after the prior greeter
  migration (`5d87840`). Traced the actual pinned nixpkgs GDM module
  (`nixos/modules/services/display-managers/{gdm,default}.nix`): a
  non-existent/mismatched `defaultSession` name is a **hard build assertion**
  (`cfg.defaultSession == null || lib.elem cfg.defaultSession
  cfg.sessionData.sessionNames`), not a silent failure — and the forced-branch
  `nix eval` in the prior review already built successfully, proving the name
  resolves correctly. **User confirmed** they have not re-tested Hyprland
  since the GDM switch (`display-manager.restartIfChanged = false` defers any
  new GDM config to the next boot, and this host is currently running the
  default `gnome` branch). **No code change proposed** — this needs a live
  retest first; treating an unreproduced report as a bug and guessing at a
  fix would be exactly the kind of unverified assertion the project's rules
  warn against.

## Problem Definition

Six Hyprland/Noctalia UX requests, five actionable now:
1. Add a launcher button to the bar's end lane.
2. Dock icon size → 35px (not bar — user-clarified).
3. *(Deferred — awaiting live retest, no fix proposed yet.)*
4. Sunshine and Tailscale tray icons are not visible.
5. Session (reboot/shutdown/logout) buttons should open centered on screen.
6. Network/notifications bar-widget clicks should open the popup at the
   widget, not centered on the bar.

## Proposed Solution

All changes are TOML-settings-only in `home/noctalia.nix` except the new
`tail-tray` package + systemd user service, added to
`home/dank-material-shell.nix` (the established home for Hyprland-only
session helpers GNOME provides implicitly — see its own header comment and
the existing `hyprpolkitagent`/`udiskie` precedent). No new flake input: both
`services.displayManager.gdm` (already used) and `pkgs.tail-tray` (plain
nixpkgs) are already available at the pinned `nixpkgs` input.

### Implementation Steps

1. **`home/noctalia.nix` — bar launcher** (item 1): add `"launcher"` to the
   front of `bar.default.end` (`end = [ "launcher" "tray" "network"
   "bluetooth" "volume" "battery" "session" ];`).
2. **`home/noctalia.nix` — dock icon size** (item 2): add `icon_size = 35;`
   to the existing `dock = { ... };` attrset.
3. **`home/noctalia.nix` — tray visibility** (item 4a): add a new top-level
   `widget.tray = { hide_passive = false; };` block.
4. **`home/dank-material-shell.nix` — Tailscale tray** (item 4b): add
   `home.packages = [ pkgs.tail-tray ];` and a
   `systemd.user.services.tail-tray` unit
   (`Unit.After/PartOf = [ "graphical-session.target" ]`,
   `Install.WantedBy = [ "graphical-session.target" ]`,
   `ExecStart = "${pkgs.tail-tray}/bin/tail-tray"`), matching the shape of
   the existing `mute-mic-on-login` unit in the same file. `tailscale` (the
   CLI `tail-tray` shells out to) is already on `PATH` system-wide via
   `services.tailscale` (`modules/network.nix`).
5. **`home/noctalia.nix` — session panel centered** (item 5): add
   `shell.panel = { session_placement = "floating"; session_position =
   "center"; };`.
6. **`home/noctalia.nix` — popups open at the widget** (item 6): add
   `open_near_click_control_center = true;` to the same new `shell.panel`
   block.

Item 3 (autologin): no change. Will re-open only if the user reproduces it
after a clean reboot into `vexos.desktop.environment = "hyprland"`.

### Dependencies

`pkgs.tail-tray` — already in the pinned `nixpkgs` input (`pkgs/by-name/ta/
tail-tray/package.nix`, version 0.2.34), no new flake input, verified via the
NixOS MCP package search and read directly from the pinned nixpkgs source
tree (Context7 is for library API docs; this is a plain nixpkgs package
addition, verified against the actual pinned derivation instead).

### Configuration Changes

None outside the two files above. No new `vexos.*` options.

### Risks and Mitigations

- **Risk:** `hide_passive = false` might surface tray icons the user doesn't
  want visible (any other app that intentionally reports Passive).
  **Mitigation:** none currently configured is expected to be Passive by
  design; this is a targeted, reversible one-line setting the user can flip
  back or refine with `widget.tray.hidden = [...]` per-item if needed.
- **Risk:** `tail-tray` is a small, single-maintainer project (GPL-3, no
  version-pin verification beyond nixpkgs' own).
  **Mitigation:** user explicitly chose this over a custom widget; it is
  nixpkgs-packaged and sandboxed the same as any other systemd user service
  in this repo — no elevated privileges, no root service.
- **Risk:** Noctalia's `checkConfig` validator only warns (doesn't fail) on
  ur an unknown key/enum — a typo in any of the new keys added here would
  silently no-op rather than break the build. **Mitigation:** every field
  name/value used above was matched against a live `field(&...)` registration
  in `config_schema.cpp` at the exact pinned commit, not inferred from memory
  or the existing file's (partially stale, per the launcher-provider-prefix
  drift noted in the review) conventions.
- Item 3 deliberately ships **no fix** — the alternative (guessing at a GDM
  autologin tweak with no reproduction) risks introducing a change that both
  doesn't fix the real issue and can't be verified in this sandboxed,
  non-rebooting environment.
