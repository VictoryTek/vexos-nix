# modules/flatpak-bundles.nix
# Installs Flatpak apps that are distributed only as `.flatpak` bundle files
# (e.g. GitHub release assets) rather than from the Flathub remote.
#
# Declares options.vexos.flatpak.bundles; a role's flatpak module sets it
# (see modules/flatpak-desktop.nix). Requires modules/flatpak.nix (flathub
# remote — the bundle's runtime is pulled from it).
#
# Bundles have no update URL, so `flatpak update` cannot refresh them. Instead
# the pinned version is part of the stamp hash: bumping a pin (automated by
# .github/workflows/update-craft-apps-daily.yml) re-runs the service on the next
# rebuild and `flatpak install --bundle` upgrades the installed app in place.
{ config, pkgs, lib, ... }:
let
  cfg = config.vexos.flatpak;

  # Changes whenever an app or its pinned version changes.
  bundlesHash = builtins.substring 0 16
    (builtins.hashString "sha256"
      (lib.concatMapStringsSep "," (b: "${b.id}@${b.version}") cfg.bundles));
in
{
  options.vexos.flatpak.bundles = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        id      = lib.mkOption { type = lib.types.str;     description = "Flatpak application ID."; };
        version = lib.mkOption { type = lib.types.str;     description = "Pinned bundle version (stamp hash input)."; };
        src     = lib.mkOption { type = lib.types.package; description = "The fetched .flatpak bundle file."; };
      };
    });
    default     = [];
    description = "Flatpak apps installed from a `.flatpak` bundle file instead of Flathub.";
  };

  config = lib.mkIf (config.services.flatpak.enable && cfg.bundles != []) {
    systemd.services.flatpak-install-bundles = {
      description = "Install Flatpak bundles (pinned release assets)";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "flatpak-install-apps.service" ];
      requires    = [ "flatpak-add-flathub.service" ];
      # /run/current-system/sw puts vexos-notify (modules/notify.nix) on PATH;
      # systemd services do not inherit environment.systemPackages otherwise.
      path        = [ pkgs.flatpak "/run/current-system/sw" ];
      script = ''
        STAMP="/var/lib/flatpak/.bundles-installed-${bundlesHash}"
        if [ -f "$STAMP" ]; then exit 0; fi

        FAILED=0
        ${lib.concatMapStrings (b: ''
          echo "flatpak: installing bundle ${b.id} ${b.version}"
          if OUT=$(flatpak install --system --noninteractive --assumeyes --bundle ${b.src} 2>&1); then
            echo "$OUT"
          elif echo "$OUT" | grep -q "already installed"; then
            echo "flatpak: ${b.id} already at this build, skipping"
          else
            echo "$OUT"
            echo "flatpak: WARNING — failed to install bundle ${b.id}"
            FAILED=1
          fi
        '') cfg.bundles}

        if [ "$FAILED" -eq 0 ]; then
          rm -f /var/lib/flatpak/.bundles-installed /var/lib/flatpak/.bundles-installed-*
          touch "$STAMP"
          echo "flatpak: bundle sync complete"
        else
          # Do NOT exit 1 — a non-zero exit would make nixos-rebuild switch
          # report failure even though the NixOS config applied fine. Stamp is
          # left unwritten so the service retries on the next boot.
          date -u +%FT%TZ > /var/lib/flatpak/.bundles-last-failed-install
          echo "flatpak: one or more bundles failed — will retry on next boot"
          vexos-notify "Flatpak bundle install failed on $(hostname) — will retry next boot" "VexOS Flatpak" || true
        fi
      '';
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
