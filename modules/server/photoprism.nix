# modules/server/photoprism.nix
# PhotoPrism — AI-powered photo management and organizer.
# Default port: 2342
# Admin password: create /etc/nixos/secrets/photoprism-password (plaintext, single line)
#   Create with: sudo install -m 0600 -o root -g root /dev/stdin /etc/nixos/secrets/photoprism-password
#   Permissions enforced at boot by modules/secrets.nix (0700 dir, 0600 files).
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
