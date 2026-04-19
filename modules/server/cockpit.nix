# modules/server/cockpit.nix
# Cockpit — web-based Linux server management UI.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.cockpit;
in
{
  options.vexos.server.cockpit = {
    enable = lib.mkEnableOption "Cockpit web management console";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for the Cockpit web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.cockpit = {
      enable = true;
      port = cfg.port;
      openFirewall = true;
    };
  };
}
