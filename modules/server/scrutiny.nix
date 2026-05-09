# modules/server/scrutiny.nix
# Scrutiny — hard drive health monitoring via S.M.A.R.T. data (web UI + collector).
# Default web port: 8078
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.scrutiny;
in
{
  options.vexos.server.scrutiny = {
    enable = lib.mkEnableOption "Scrutiny disk health monitoring";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8078;
      description = "Port for the Scrutiny web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.scrutiny = {
      enable = true;
      openFirewall = true;
      settings.web.listen.port = cfg.port;
      collector.enable = true;
    };
  };
}
