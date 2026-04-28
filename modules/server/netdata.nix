# modules/server/netdata.nix
# Netdata — real-time system performance and health monitoring.
# Default port: 19999
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.netdata;
in
{
  options.vexos.server.netdata = {
    enable = lib.mkEnableOption "Netdata real-time system monitoring";
  };

  config = lib.mkIf cfg.enable {
    services.netdata = {
      enable = true;
    };

    networking.firewall.allowedTCPPorts = [ 19999 ];
  };
}
