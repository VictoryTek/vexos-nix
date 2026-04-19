# modules/server/forgejo.nix
# Forgejo — lightweight self-hosted Git forge (Gitea fork).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.forgejo;
in
{
  options.vexos.server.forgejo = {
    enable = lib.mkEnableOption "Forgejo Git forge";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for the Forgejo web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.forgejo = {
      enable = true;
      settings = {
        server = {
          HTTP_PORT = cfg.port;
          ROOT_URL = "http://localhost:${toString cfg.port}/";
        };
        service.DISABLE_REGISTRATION = true;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
