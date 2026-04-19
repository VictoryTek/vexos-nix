# modules/server/mealie.nix
# Mealie — self-hosted recipe manager and meal planner.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.mealie;
in
{
  options.vexos.server.mealie = {
    enable = lib.mkEnableOption "Mealie recipe manager";
  };

  config = lib.mkIf cfg.enable {
    services.mealie = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 9000; # Default port: 9000
    };

    networking.firewall.allowedTCPPorts = [ 9000 ];
  };
}
