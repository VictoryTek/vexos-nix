# modules/flatpak.nix
# Flatpak subsystem with automatic Flathub remote registration on boot.
{ config, pkgs, lib, ... }:
{
  # Enable the Flatpak subsystem
  services.flatpak.enable = true;

  # Automatically add the Flathub remote on system activation.
  # Runs once after network is up; idempotent (--if-not-exists).
  systemd.services.flatpak-add-flathub = {
    description = "Add Flathub Flatpak remote";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];
    path        = [ pkgs.flatpak ];
    script      = ''
      flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
  };

  # Ensure Flatpak-installed desktop files are visible to KDE Plasma's app launcher.
  environment.sessionVariables = {
    XDG_DATA_DIRS = lib.mkAfter [
      "/var/lib/flatpak/exports/share"
      "$HOME/.local/share/flatpak/exports/share"
    ];
  };
}
