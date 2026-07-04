# modules/server/mealie.nix
# Mealie — self-hosted recipe manager and meal planner.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.mealie;
in
{
  options.vexos.server.mealie = {
    enable = lib.mkEnableOption "Mealie recipe manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9010;
      description = "Port for the Mealie web interface.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Mealie's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.mealie = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = cfg.port;
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
