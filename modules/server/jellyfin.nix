# modules/server/jellyfin.nix
# Jellyfin media server — free software alternative to Plex.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.jellyfin;
in
{
  options.vexos.server.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server";

    hardwareAcceleration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable hardware acceleration permissions for Jellyfin.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = true;
    };

    systemd.services.jellyfin.serviceConfig = lib.mkIf cfg.hardwareAcceleration {
      SupplementaryGroups = [ "render" "video" ];
    };

    # Allow the primary user to manage media directories alongside the jellyfin user.
    users.users.${config.vexos.user.name}.extraGroups = [ "jellyfin" ];
  };
}
