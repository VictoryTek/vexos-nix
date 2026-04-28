# modules/server/paperless.nix
# Paperless-ngx — document management system with OCR and full-text search.
# Default port: 28981
# Note: Redis is managed automatically by the NixOS paperless module.
#       Admin password is auto-generated on first run; check journalctl -u paperless.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.paperless;
in
{
  options.vexos.server.paperless = {
    enable = lib.mkEnableOption "Paperless-ngx document management";

    port = lib.mkOption {
      type = lib.types.port;
      default = 28981;
      description = "Port for the Paperless-ngx web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.paperless = {
      enable = true;
      port = cfg.port;
      address = "0.0.0.0";
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
