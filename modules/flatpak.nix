# modules/flatpak.nix
{ config, pkgs, lib, ... }:
{
  services.flatpak.enable = true;

  # Add Flathub remote on first boot only (stamp: /var/lib/flatpak/.flathub-added).
  systemd.services.flatpak-add-flathub = {
    description = "Add Flathub Flatpak remote (once)";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network-online.target" "nss-lookup.target" ];
    wants       = [ "network-online.target" "nss-lookup.target" ];
    path        = [ pkgs.flatpak ];
    script = ''
      if [ -f /var/lib/flatpak/.flathub-added ]; then exit 0; fi
      flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
      touch /var/lib/flatpak/.flathub-added
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  # Install apps from Flathub on first boot only (stamp: /var/lib/flatpak/.apps-installed).
  # After initial install, Up manages all flatpak updates.
  systemd.services.flatpak-install-apps = {
    description = "Install Flatpak applications from Flathub (once)";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "flatpak-add-flathub.service" ];
    requires    = [ "flatpak-add-flathub.service" ];
    path        = [ pkgs.flatpak ];
    script = ''
      if [ -f /var/lib/flatpak/.apps-installed ]; then exit 0; fi
      flatpak install --noninteractive --assumeyes flathub \
        com.bitwarden.desktop \
        io.github.pol_rivero.github-desktop-plus \
        com.github.tchx84.Flatseal \
        it.mijorus.gearlever \
        org.gimp.GIMP \
        io.missioncenter.MissionCenter \
        org.onlyoffice.desktopeditors \
        org.prismlauncher.PrismLauncher \
        com.simplenote.Simplenote \
        io.github.flattool.Warehouse \
        app.zen_browser.zen \
        com.mattjakeman.ExtensionManager \
        com.rustdesk.RustDesk \
        io.github.kolunmi.Bazaar \
        org.pulseaudio.pavucontrol \
        com.vysp3r.ProtonPlus \
        net.lutris.Lutris
      touch /var/lib/flatpak/.apps-installed
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  # Ensure Flatpak-installed desktop files are visible to GNOME's app launcher.
  environment.sessionVariables = {
    XDG_DATA_DIRS = lib.mkAfter [
      "/var/lib/flatpak/exports/share"
      "$HOME/.local/share/flatpak/exports/share"
    ];
  };
}
