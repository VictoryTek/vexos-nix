# modules/server/authelia.nix
# Authelia — SSO and 2FA authentication proxy (OCI container).
# Default port: 9091
# Before enabling, create the configuration directory:
#   sudo mkdir -p /var/lib/authelia/config
#   sudo cp /path/to/configuration.yml /var/lib/authelia/config/
#   sudo cp /path/to/users_database.yml /var/lib/authelia/config/
# See: https://www.authelia.com/configuration/prologue/introduction/
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.authelia;
in
{
  options.vexos.server.authelia = {
    enable = lib.mkEnableOption "Authelia SSO/2FA authentication proxy";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9091;
      description = "Port for the Authelia web portal.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.authelia = {
      image = "authelia/authelia:latest";
      ports = [ "${toString cfg.port}:9091" ];
      volumes = [
        "/var/lib/authelia/config:/config"
      ];
      environment = {
        TZ = config.time.timeZone;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
