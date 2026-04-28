# modules/server/listmonk.nix
# Listmonk — self-hosted newsletter and mailing list manager.
# Default port: 9025 (non-standard default; avoids conflict with Mealie/MinIO on port 9000)
# PostgreSQL is created automatically by the NixOS listmonk module.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.listmonk;
in
{
  options.vexos.server.listmonk = {
    enable = lib.mkEnableOption "Listmonk newsletter and mailing list manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9025;
      description = "Port for the Listmonk web interface. Default 9025 avoids conflict with Mealie/MinIO on port 9000.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.listmonk = {
      enable = true;
      settings.app.address = "0.0.0.0:${toString cfg.port}";
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
