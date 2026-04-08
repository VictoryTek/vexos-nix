# modules/flatpak.nix
{ config, pkgs, lib, ... }:
{
  services.flatpak.enable = true;

  # Add Flathub remote on first boot only (stamp: /var/lib/flatpak/.flathub-added).
  systemd.services.flatpak-add-flathub = {
    description = "Add Flathub Flatpak remote (once)";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network-online.target" "nss-lookup.target" "systemd-resolved.service" ];
    wants       = [ "network-online.target" "nss-lookup.target" "systemd-resolved.service" ];
    # Skip entirely if stamp already exists — avoids a failed DNS lookup on
    # every nixos-rebuild switch when the unit is re-evaluated by systemd.
    path        = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
      touch /var/lib/flatpak/.flathub-added
    '';
    unitConfig = {
      ConditionPathExists    = "!/var/lib/flatpak/.flathub-added";
      StartLimitIntervalSec  = 300;
      StartLimitBurst        = 5;
    };
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      Restart         = "on-failure";
      RestartSec      = 30;
    };
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

      FAILED=0

      for app in \
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
        com.ranfdev.DistroShelf
      do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: $app already installed, skipping"
          continue
        fi
        echo "flatpak: installing $app"
        if ! flatpak install --noninteractive --assumeyes flathub "$app"; then
          echo "flatpak: WARNING — failed to install $app"
          FAILED=1
        fi
      done

      if [ "$FAILED" -eq 0 ]; then
        touch /var/lib/flatpak/.apps-installed
        echo "flatpak: all apps installed successfully"
      else
        echo "flatpak: one or more apps failed — will retry on next start"
        exit 1
      fi
    '';
    unitConfig = {
      StartLimitIntervalSec = 600;
      StartLimitBurst       = 10;
    };
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      Restart         = "on-failure";
      RestartSec      = 60;
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
