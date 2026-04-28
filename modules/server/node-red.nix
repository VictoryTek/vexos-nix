# modules/server/node-red.nix
# Node-RED — low-code flow-based automation and IoT programming tool.
# Default port: 1880
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.node-red;
in
{
  options.vexos.server.node-red = {
    enable = lib.mkEnableOption "Node-RED flow-based automation";
  };

  config = lib.mkIf cfg.enable {
    services.node-red = {
      enable = true;
      openFirewall = true; # Port 1880
    };
  };
}
