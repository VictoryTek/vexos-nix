# modules/server/audiobookshelf.nix
# Audiobookshelf — self-hosted audiobook and podcast server.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.audiobookshelf;
in
{
  options.vexos.server.audiobookshelf = {
    enable = lib.mkEnableOption "Audiobookshelf audiobook server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8234;
      description = "Port for the Audiobookshelf web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.audiobookshelf = {
      enable = true;
      port = cfg.port;
      openFirewall = true;
    };
  };
}
