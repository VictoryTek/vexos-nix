# modules/gnome-stateless.nix
# Stateless-only GNOME additions: teal accent, stateless dock favourites, and
# the Flatpak install service for the stateless role (TextEditor, Loupe). mpv
# is the video player (nixpkgs, via packages-desktop.nix).
{ config, pkgs, lib, ... }:
{
  imports = [ ./gnome.nix ];

  # ── Role-specific dconf overlay ───────────────────────────────────────────
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/desktop/interface" = {
          accent-color = "teal";
        };

        "org/gnome/shell" = {
          enabled-extensions = config.vexos.gnome.commonExtensions;
          favorite-apps = [
            "brave-origin.desktop"
            "torbrowser.desktop"
            "app.zen_browser.zen.desktop"
            "org.gnome.Nautilus.desktop"
            "com.mitchellh.ghostty.desktop"
            "io.github.up.desktop"
          ];
        };

        "org/gnome/shell/extensions/dash-to-dock" = {
          dock-position = "LEFT";
          autohide      = true;
          intellihide   = true;
        };

        "org/gnome/desktop/app-folders" = {
          folder-children = [ "Office" "Utilities" "System" ];
        };

        "org/gnome/desktop/app-folders/folders/Office" = {
          name = "Office";
          apps = [
            "org.onlyoffice.desktopeditors.desktop"
            "org.gnome.TextEditor.desktop"
            "net.cozic.joplin_desktop.desktop"
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
            "io.missioncenter.MissionCenter.desktop"
            "org.gnome.Settings.desktop"
            "org.gnome.seahorse.Application.desktop"
            "nixos-manual.desktop"
            "cups.desktop"
            "gparted.desktop"
            "blueman-manager.desktop"
            "btop.desktop"
            "ca.desrt.dconf-editor.desktop"
            "org.gnome.baobab.desktop"
            "org.gnome.DiskUtility.desktop"
            "org.gnome.font-viewer.desktop"
            "org.gnome.Logs.desktop"
            "btrfs-assistant.desktop"
            "org.gnome.SystemMonitor.desktop"
          ];
        };
      };
    }
  ];

  # ── GNOME default app Flatpaks (stateless role) ───────────────────────────
  vexos.gnome.flatpakInstall.apps = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
  ];

  # ── Persist display configuration ────────────────────────────────────────
  # GNOME Wayland stores display resolution and layout in monitors.xml.
  # On stateless, / is a tmpfs so both files are wiped on every reboot,
  # resetting the resolution back to the fallback 1024×768.
  #
  # /var/lib/gdm/.config/monitors.xml — persisted via impermanence (system file).
  # ~/.config/monitors.xml            — copied from GDM's file on every boot via
  #                                     activation script. This avoids using
  #                                     nixos-impermanence's users.*.files which
  #                                     asserts neededForBoot on the /home
  #                                     filesystem and creates a broken fstab
  #                                     entry on systems without a separate /home
  #                                     partition (e.g. VMs).
  #
  # Workflow: set resolution once in GNOME Settings → Displays. GNOME writes
  # both ~/.config/monitors.xml and (via GDM) /var/lib/gdm/.config/monitors.xml.
  # The GDM copy survives reboots; the activation script seeds the user copy
  # from it on each boot so the session starts at the correct resolution.
  vexos.impermanence.extraPersistFiles = [
    "/var/lib/gdm/.config/monitors.xml"
  ];

  system.activationScripts.statelessMonitorsXml = {
    deps = [ "users" "groups" ];
    text = ''
      GDM_FILE="/var/lib/gdm/.config/monitors.xml"
      USER_DIR="/home/${config.vexos.user.name}/.config"
      USER_FILE="$USER_DIR/monitors.xml"
      if [ -s "$GDM_FILE" ] && [ ! -f "$USER_FILE" ]; then
        mkdir -p "$USER_DIR"
        cp "$GDM_FILE" "$USER_FILE"
        chown 1000:1000 "$USER_FILE"
      fi
    '';
  };
}
