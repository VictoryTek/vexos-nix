# modules/server/syncthing.nix
# Syncthing — continuous peer-to-peer file synchronization.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.syncthing;
in
{
  options.vexos.server.syncthing = {
    enable = lib.mkEnableOption "Syncthing file sync";
  };

  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = "nimda";
      dataDir = "/home/nimda";
      configDir = "/home/nimda/.config/syncthing";
      openDefaultPorts = true;
      guiAddress = "0.0.0.0:8384";
    };

    networking.firewall.allowedTCPPorts = [ 8384 ];
  };
}
