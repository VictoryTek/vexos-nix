# modules/server/photoprism.nix
# PhotoPrism — AI-powered photo management and organizer.
# Default port: 2342
# Admin password: create /etc/nixos/secrets/photoprism-password (plaintext, single line)
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.photoprism;
in
{
  options.vexos.server.photoprism = {
    enable = lib.mkEnableOption "PhotoPrism photo management";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2342;
      description = "Port for the PhotoPrism web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.photoprism = {
      enable = true;
      port = cfg.port;
      address = "0.0.0.0";
      passwordFile = "/etc/nixos/secrets/photoprism-password";
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
