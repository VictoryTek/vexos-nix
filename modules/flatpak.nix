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

  # Automatically install Flatpak applications from Flathub on boot.
  # Runs after Flathub remote is registered; idempotent (install --noninteractive).
  systemd.services.flatpak-install-apps = {
    description = "Install Flatpak applications from Flathub";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "flatpak-add-flathub.service" ];
    requires    = [ "flatpak-add-flathub.service" ];
    path        = [ pkgs.flatpak ];
    script      = ''
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
        net.lutris.Lutris \
        net.davidotek.pupgui2 \
        || true
    '';
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
  };

  # Ensure Flatpak-installed desktop files are visible to GNOME's app launcher.
  environment.sessionVariables = {
    XDG_DATA_DIRS = lib.mkAfter [
      "/var/lib/flatpak/exports/share"
      "$HOME/.local/share/flatpak/exports/share"
    ];
  };
}
