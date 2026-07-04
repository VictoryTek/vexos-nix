# modules/server/dozzle.nix
# Dozzle — real-time web UI for Docker container logs (OCI container).
# Default port: 8888
# Requires Docker to be enabled (vexos.server.docker.enable = true).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.dozzle;
in
{
  options.vexos.server.dozzle = {
    enable = lib.mkEnableOption "Dozzle Docker log viewer";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Port for the Dozzle web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    virtualisation.oci-containers.containers.dozzle = {
      image = "amir20/dozzle:v10.6.7";
      ports = [ "${toString cfg.port}:8080" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock:ro"
      ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
