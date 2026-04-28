# modules/server/portainer.nix
# Portainer CE — Docker container management web UI (OCI container).
# Default port: 9443 (HTTPS)
# Requires Docker to be enabled (vexos.server.docker.enable = true).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.portainer;
in
{
  options.vexos.server.portainer = {
    enable = lib.mkEnableOption "Portainer Docker management UI";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9443;
      description = "HTTPS port for the Portainer web UI.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.portainer = {
      image = "portainer/portainer-ce:latest";
      ports = [ "${toString cfg.port}:9443" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock:ro"
        "portainer-data:/data"
      ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
