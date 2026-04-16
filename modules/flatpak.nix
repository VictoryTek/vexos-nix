# modules/flatpak.nix
{ config, pkgs, lib, ... }:
let
  # Default Flatpak apps installed on first boot.
  # Roles can exclude apps by setting vexos.flatpak.excludeApps.
  defaultApps = [
    "com.bitwarden.desktop"
    "io.github.pol_rivero.github-desktop-plus"
    "com.github.tchx84.Flatseal"
    "it.mijorus.gearlever"
    "org.gimp.GIMP"
    "io.missioncenter.MissionCenter"
    "org.onlyoffice.desktopeditors"
    "org.prismlauncher.PrismLauncher"
    "com.simplenote.Simplenote"
    "io.github.flattool.Warehouse"
    "app.zen_browser.zen"
    "com.mattjakeman.ExtensionManager"
    "com.rustdesk.RustDesk"
    "io.github.kolunmi.Bazaar"
    "org.pulseaudio.pavucontrol"
    "com.vysp3r.ProtonPlus"
    "net.lutris.Lutris"
    "com.ranfdev.DistroShelf"
    "org.gnome.World.PikaBackup"
  ];

  appsToInstall = (lib.filter
    (a: !builtins.elem a config.vexos.flatpak.excludeApps)
    defaultApps) ++ config.vexos.flatpak.extraApps;

  # Short hash of the desired app list, baked in at Nix evaluation time.
  # When excludeApps or extraApps changes the hash changes, causing the
  # stamp path to change and the service to re-run and sync.
  appsListHash = builtins.substring 0 16
    (builtins.hashString "sha256" (lib.concatStringsSep "," appsToInstall));
in
{
  options.vexos.flatpak.excludeApps = lib.mkOption {
    type        = lib.types.listOf lib.types.str;
    default     = [];
    description = "Flatpak app IDs to skip during first-boot installation.";
  };

  options.vexos.flatpak.extraApps = lib.mkOption {
    type        = lib.types.listOf lib.types.str;
    default     = [];
    description = "Role-specific Flatpak app IDs to install in addition to the defaults.";
  };

  config = {
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
      # Hash of the desired app list baked in at build time.
      # Changes when excludeApps or extraApps changes — triggers a sync.
      STAMP="/var/lib/flatpak/.apps-installed-${appsListHash}"
      if [ -f "$STAMP" ]; then exit 0; fi

      FAILED=0

      # ── Remove excluded apps that may still be installed from a prior config ──
      for app in \
        ${lib.concatMapStringsSep " \\\n        " (a: a) config.vexos.flatpak.excludeApps}
      do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: uninstalling excluded app $app"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done

      # ── Install desired apps ───────────────────────────────────────────────
      for app in \
        ${lib.concatMapStringsSep " \\\n        " (a: a) appsToInstall}
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
        # Remove old stamps (previous app-list hashes) and write the current one
        rm -f /var/lib/flatpak/.apps-installed /var/lib/flatpak/.apps-installed-*
        touch "$STAMP"
        echo "flatpak: sync complete"
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
  }; # end config
}
