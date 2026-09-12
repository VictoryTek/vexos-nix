# home/noctalia.nix
# Noctalia v5 desktop shell (user layer) — bar, dock, launcher, control center,
# lock screen, OSDs and hot corners. Replaces DankMaterialShell as the active
# Hyprland shell; DMS itself stays installed but disabled in
# home/dank-material-shell.nix, so a revert is a one-line change on each side.
#
# Active only when vexos.desktop.environment == "hyprland" — imported
# unconditionally by home-desktop.nix and gated internally, matching the shape
# of home/dank-material-shell.nix and home/gnome-common.nix.
#
# Why the Home Manager module and not the NixOS one: the home module carries
# `settings` (the TOML surface everything below needs) and a systemd user
# service bound to the graphical session. The NixOS module only installs the
# binary system-wide and toggles recommended services, which this repo already
# configures itself (NetworkManager, bluetooth, upower).
#
# Config lands at ~/.config/noctalia/config.toml as a read-only /nix/store
# symlink. Upstream's `checkConfig` (default true) runs `noctalia config
# validate` against it at BUILD time, but note what that does and does not
# catch: TOML *syntax* errors fail the build, while an unknown key or an
# unknown enum value is only a WARNING and still exits 0. So a typo here will
# not break the rebuild — it will silently do nothing. Every key and value in
# this file was therefore checked directly against noctalia 5.1.0's validator,
# which reported 0 errors and 0 warnings. Re-run that check when editing:
#   noctalia config validate ~/.config/noctalia/config.toml
# and treat any warning as a defect. Because the file is store-owned, changes
# made in
# Noctalia's own Settings GUI cannot persist across a rebuild; the same
# trade-off home/dank-material-shell.nix documents for settings.json. See
# .github/docs/subagent_docs/noctalia_v5_migration_spec.md §5.5 for the list of
# what is declarative here versus GUI-only.
{ config, pkgs, lib, inputs, osConfig, ... }:
let
  # Same app set the DMS dock pinned (home/dank-material-shell.nix), kept in
  # sync deliberately so switching shells does not silently change the dock.
  # Codium is only actually installed when the development feature is on, so
  # pinning it unconditionally would leave a dead icon that launches nothing.
  basePinnedApps = [
    "brave-origin"
    "librewolf"
    "org.gnome.Nautilus"
    "com.mitchellh.ghostty"
    "io.github.up"
    "org.gnome.Boxes"
  ] ++ lib.optional osConfig.vexos.features.development.enable "codium";

  # Every shell action is reached through `noctalia msg <command>`. These are
  # bound in two places — a Hyprland keybind (files/hypr/hyprland.conf) and a
  # hot corner (hot_corners below) — and both must run the identical string, so
  # they are defined once here. Note the binary is `noctalia`, not
  # `noctalia-shell`, and v5 uses `msg`, not v4's `ipc call`.
  ipc = {
    launcher      = "noctalia msg panel-toggle launcher";
    controlCenter = "noctalia msg panel-toggle control-center";
    # Noctalia has no workspace-grid overview. window-switcher is an Alt+Tab
    # style fullscreen window grid — the closest equivalent it exposes.
    overview      = "noctalia msg window-switcher";
    lock          = "noctalia msg session lock";
  };
in
{
  # Imports cannot be conditional — they are resolved before option values
  # exist — so this sits outside the mkIf below. The upstream module is inert
  # until programs.noctalia.enable is set, so non-Hyprland desktops are
  # unaffected by its presence.
  imports = [ inputs.noctalia.homeModules.default ];

  config = lib.mkIf (osConfig.vexos.desktop.environment == "hyprland") {
    programs.noctalia = {
      enable = true;

      # Binds noctalia.service to config.wayland.systemd.target, which resolves
      # to graphical-session.target — activated by UWSM (see the comment in
      # modules/hyprland-desktop.nix; without UWSM this never starts).
      #
      # Because the service owns the lifecycle, there is deliberately NO
      # `exec-once = noctalia` in files/hypr/hyprland.conf — that would start a
      # second instance. Same rule DMS had, and for the same reason.
      systemd.enable = true;

      # package is supplied by inputs.noctalia.homeModules.default via mkDefault,
      # built against Noctalia's own nixpkgs pin. Left alone on purpose: that is
      # exactly what keeps the Cachix cache valid (see flake.nix inputs.noctalia).

      settings = {
        # ── Shell ───────────────────────────────────────────────────────────
        shell = {
          # Required when systemd.enable is on: apps launched from the shell are
          # started as transient systemd scopes instead of children of
          # noctalia.service, so restarting the shell no longer kills them.
          launch_apps_as_systemd_services = true;

          # This repo already runs hyprpolkitagent (home/dank-material-shell.nix,
          # outside the DMS attrset, still active). Two polkit agents race for
          # the same prompts, so Noctalia's built-in one stays off.
          polkit_agent = false;

          # GNOME: org/gnome/desktop/interface clock-format=12h — matches the
          # clockFormat = "12h" the DMS config set.
          time_format = "12h";

          clipboard_enabled = true;

          # ── Launcher ──────────────────────────────────────────────────────
          # GNOME-Activities-like behaviour. Global application search is
          # inherent to the launcher — there is no toggle for it. Calculator and
          # Emoji are BUILT-IN providers and are always present; the providers
          # table below can only retune their prefix/global flags, not enable or
          # disable them (LauncherProviderConfig exposes exactly `prefix` and
          # `global`). Bound to a single Super-key toggle in
          # files/hypr/hyprland.conf.
          launcher = {
            show_icons   = true;
            app_grid     = true;   # icon grid when every result is an app — Activities-like
            sort_by_usage = true;  # frequently-used apps float to the top
            categories   = true;   # category filter chips (Internet, Dev, Games, …)
            show_app_actions = true;
            pinned       = basePinnedApps;

            providers = {
              # Calculator already auto-activates in global search whenever the
              # query contains a digit; global = true keeps digit-free
              # expressions reachable without typing the prefix first.
              calculator = { prefix = "/calc"; global = true; };
              # Emoji stays prefix-driven — as a global provider it floods
              # ordinary app searches with character matches.
              emoji      = { prefix = "/emoji"; global = false; };
            };
          };
        };

        # ── Theme — Material-You generated from the wallpaper ──────────────
        theme = {
          source = "wallpaper";  # derive the palette from the active wallpaper
          mode   = "dark";       # GNOME: color-scheme=prefer-dark
        };

        # ── Wallpaper ───────────────────────────────────────────────────────
        # Same files home-desktop.nix already deploys to ~/Pictures/Wallpapers/
        # and that the DMS session config pointed at. theme.source above reads
        # whichever of these is active to build the palette.
        wallpaper = {
          enabled        = true;
          directory      = "${config.home.homeDirectory}/Pictures/Wallpapers";
          directory_dark = "${config.home.homeDirectory}/Pictures/Wallpapers";
          default.path   = "${config.home.homeDirectory}/Pictures/Wallpapers/vex-bb-dark.jxl";
        };

        # ── Bar ─────────────────────────────────────────────────────────────
        # Flat, ungrouped widgets (upstream's own default shape — example.toml
        # ships capsule = false with bare widget tokens in each lane) rather
        # than the previous pill-grouped layout.
        bar.default = {
          position = "top";
          enabled  = true;

          # Concave (inverted) corners where the bar meets the screen edge.
          # This REQUIRES margin_edge = 0 — a floating bar does not touch the
          # edge, and the carve is silently skipped. For a top bar the two
          # bottom corners are the ones that curve inward.
          concave_edge_corners = true;
          margin_edge          = 0;
          margin_ends          = 0;
          radius               = 12;

          thickness      = 30;
          padding        = 10;
          widget_spacing = 6;

          # Translucent, wallpaper showing through slightly — no pill
          # backgrounds behind individual widgets.
          capsule             = false;
          background_opacity  = 0.85;

          start  = [ "workspaces" ];
          center = [ "clock" ];
          # Label defaults already match: network shows the interface/SSID,
          # battery and volume show their percentage, bluetooth is icon-only.
          end    = [ "media" "tray" "network" "bluetooth" "volume" "battery" "session" ];
        };

        # ── Dock ────────────────────────────────────────────────────────────
        dock = {
          enabled   = true;
          position  = "left";   # GNOME dash-to-dock position=LEFT, as DMS had
          auto_hide = true;
          # Closest equivalent to GNOME's intellihide: reveal when the active
          # workspace is empty.
          smart_auto_hide = true;
          # Without this, an auto-hidden dock still reserves an exclusive
          # zone at its edge, shrinking the visible workspace area even while
          # hidden. false makes it retract as a pure overlay with no gap.
          reserve_space = false;

          # Visible border styling.
          border       = "outline";
          border_width = 1;

          # Match the bar's inverted corners where the dock meets the edge.
          concave_edge_corners = true;
          margin_edge          = 0;
          radius               = 12;

          show_running = true;
          show_dots    = true;

          # Pinned apps. Drag-to-reorder is a RUNTIME GUI gesture with no config
          # key — this list sets the initial order. Reordering in the GUI writes
          # back to this key, which cannot persist while the config is a
          # store-owned symlink; change the order here instead.
          pinned = basePinnedApps;

          # Launcher button at the start of the dock, as DMS's dockLauncherEnabled
          # did.
          launcher_position = "start";
        };

        # ── Hot corners — GNOME-style ───────────────────────────────────────
        # Native to Noctalia v5; hyprcorners is deliberately NOT packaged, since
        # this covers the same ground declaratively with no extra derivation.
        #
        # `action = "command"` runs `command` as a shell command. Using that
        # form (rather than an internal action name) means each corner executes
        # the exact same string as its matching Hyprland keybind — see the ipc
        # attrset at the top of this file. Keyboard/mouse parity is then
        # structural, not something kept in sync by hand.
        hot_corners = {
          enabled = true;
          # Short dwell so a corner is not triggered by a pointer merely
          # crossing it on the way somewhere else.
          delay_ms = 150;

          top_left     = { action = "command"; command = ipc.launcher; };
          top_right    = { action = "command"; command = ipc.controlCenter; };
          bottom_left  = { action = "command"; command = ipc.overview; };
          # bottom_right is intentionally left unset (defaults to action =
          # "none"): it is the corner most often hit by accident when reaching
          # for a scrollbar or the dock.
        };
      };
    };
  };
}
