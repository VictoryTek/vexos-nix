# Spec: Move dconf Overrides to System-Level (dconf-system-level)

## Current State
`home.nix` declares all GNOME dconf settings via `dconf.settings` (Home Manager user-level).
`modules/desktop.nix` declares a partial, stale extension list via `programs.dconf.profiles.user.databases`.

## Problem
`dconf.settings` in Home Manager activates via `dconf load`, which requires `DBUS_SESSION_BUS_ADDRESS`.
The `home-manager-nimda.service` that runs during `nixos-rebuild switch` operates in a system activation context without a live user D-Bus session, so `dconf load` fails silently — no settings are written.

Additionally, the extension UUIDs in `desktop.nix`'s existing system database differ from the correct list in `home.nix`, meaning even the system-level settings may not produce the intended results.

## Proposed Solution
Move ALL dconf settings from `home.nix`'s `dconf.settings` into `modules/desktop.nix`'s `programs.dconf.profiles.user.databases`. This writes to the NixOS-managed system dconf database at build time — no D-Bus session required. Settings are available at first login.

Remove `dconf.settings` from `home.nix` entirely.

## Files to Modify
- `modules/desktop.nix` — expand `programs.dconf.profiles.user.databases` to cover all settings
- `home.nix` — remove `dconf.settings` block; keep function signature intact

## Implementation Details

### `programs.dconf.profiles.user.databases` expansion in `desktop.nix`

Replace the existing partial block with a comprehensive single-database entry:

```nix
programs.dconf.profiles.user.databases = [{
  settings = {
    "org/gnome/shell" = {
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "dash-to-dock@micxgx.gmail.com"
        "AlphabeticalAppGrid@stuarthayhurst"
        "gamemodeshellextension@trsnaqe.com"
        "gnome-ui-tune@itstime.tech"
        "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
        "steal-my-focus-window@steal-my-focus-window"
        "tailscale-status@maxgallup.github.com"
        "caffeine@patapon.info"
        pkgs.gnomeExtensions.restart-to.extensionUuid
        "blur-my-shell@aunetx"
        "background-logo@fedorahosted.org"
      ];
      favorite-apps = [
        "brave-browser.desktop"
        "app.zen_browser.zen.desktop"
        "org.gnome.Nautilus.desktop"
        "com.mitchellh.ghostty.desktop"
        "io.github.up.desktop"
        "org.gnome.Boxes.desktop"
        "code.desktop"
        "discord.desktop"
      ];
    };
    "org/gnome/desktop/interface" = {
      clock-format = "12h";
      cursor-size  = 24;
      cursor-theme = "Bibata-Modern-Classic";
      icon-theme   = "kora";
    };
    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
    };
    "org/gnome/desktop/background" = {
      picture-uri      = "file:///home/nimda/Pictures/Wallpapers/vex-bb-light.jxl";
      picture-uri-dark = "file:///home/nimda/Pictures/Wallpapers/vex-bb-dark.jxl";
      picture-options  = "zoom";
    };
    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-position = "LEFT";
    };
    "org/gnome/desktop/screensaver" = {
      lock-enabled = true;
      lock-delay   = 0;
    };
    "org/gnome/session" = {
      idle-delay = 300;
    };
    "org/gnome/desktop/app-folders" = {
      folder-children = [ "Games" "Office" "Utilities" "System" ];
    };
    "org/gnome/desktop/app-folders/folders/Games" = {
      name = "Games";
      apps = [
        "org.prismlauncher.PrismLauncher.desktop"
        "com.vysp3r.ProtonPlus.desktop"
      ];
    };
    "org/gnome/desktop/app-folders/folders/Office" = {
      name = "Office";
      apps = [
        "org.onlyoffice.desktopeditors.desktop"
        "org.gnome.TextEditor.desktop"
        "org.gnome.Papers.desktop"
      ];
    };
    "org/gnome/desktop/app-folders/folders/Utilities" = {
      name = "Utilities";
      apps = [
        "com.mattjakeman.ExtensionManager.desktop"
        "it.mijorus.gearlever.desktop"
        "org.gnome.tweaks.desktop"
        "io.github.flattool.Warehouse.desktop"
        "io.missioncenter.MissionCenter.desktop"
        "com.github.tchx84.Flatseal.desktop"
      ];
    };
    "org/gnome/desktop/app-folders/folders/System" = {
      name = "System";
      apps = [
        "org.pulseaudio.pavucontrol.desktop"
        "rog-control-center.desktop"
        "org.gnome.SystemMonitor.desktop"
        "org.gnome.Settings.desktop"
        "org.gnome.seahorse.Application.desktop"
        "nixos-manual.desktop"
        "cups.desktop"
        "blivet-gui.desktop"
        "blueman-manager.desktop"
        "btop.desktop"
        "ca.desrt.dconf-editor.desktop"
        "org.gnome.baobab.desktop"
        "org.gnome.DiskUtility.desktop"
        "org.gnome.font-viewer.desktop"
        "htop.desktop"
        "org.gnome.Logs.desktop"
      ];
    };
  };
}];
```

Notes:
- Extension UUIDs taken from home.nix (authoritative source)
- `lib.hm.gvariant.mkUint32` replaced with plain integers (0, 300) — system dconf module converts integers to int32; GNOME reads these correctly
- `config.home.homeDirectory` replaced with hardcoded `/home/nimda`
- `pkgs.gnomeExtensions.restart-to.extensionUuid` works as-is since `pkgs` is available in desktop.nix

### `home.nix` change
Remove the entire `dconf.settings = { ... };` block (lines covering `# ── GNOME dconf overrides ──` through the closing `};`).
Keep the function signature `{ config, pkgs, lib, inputs, ... }:` unchanged.

## Risks / Mitigations
- **uint32 vs int32 type mismatch for `lock-delay`/`idle-delay`**: Plain integers become int32 in the dconf system database. GNOME's dconf daemon reads these without complaints in practice. If needed, a follow-up can add explicit GVariant type annotations.
- **Wallpaper paths hardcoded**: Files at `/home/nimda/Pictures/Wallpapers/` must exist for the wallpaper setting to take effect. The `home.file` declarations in home.nix are currently commented out; this is a separate issue.
- **User can still override**: System DB settings are defaults, not locks (`lockAll` is false). Users can override via GNOME Settings or dconf-editor.
