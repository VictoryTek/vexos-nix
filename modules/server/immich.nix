# modules/server/immich.nix
# Immich — self-hosted photo and video backup (Google Photos alternative).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.immich;
in
{
  options.vexos.server.immich = {
    enable = lib.mkEnableOption "Immich photo/video backup server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2283;
      description = "Port for the Immich web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.immich = {
      enable = true;
      port = cfg.port;
      openFirewall = true;
    };
  };
}
