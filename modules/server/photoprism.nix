# modules/server/photoprism.nix
# PhotoPrism — AI-powered photo management and organizer.
# Default port: 2342
# Admin password default path: /etc/nixos/secrets/photoprism-password
#   Override via vexos.server.photoprism.passwordFile for alternate backends.
# Create file (plaintext, single line):
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

    passwordFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/secrets/photoprism-password";
      description = ''
        Path to the PhotoPrism admin password file.
        Default keeps legacy plaintext behavior; the sops backend overrides this
        to a decrypted runtime secret path.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.photoprism = {
      enable = true;
      port = cfg.port;
      address = "0.0.0.0";
      passwordFile = cfg.passwordFile;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
