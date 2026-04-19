# modules/server/homepage.nix
# Homepage — customizable service dashboard (OCI container).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.homepage;
in
{
  options.vexos.server.homepage = {
    enable = lib.mkEnableOption "Homepage dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3010;
      description = "Port for the Homepage dashboard.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.homepage = {
      image = "ghcr.io/gethomepage/homepage:latest";
      ports = [ "${toString cfg.port}:3000" ];
      volumes = [
        "homepage-config:/app/config"
        "/var/run/docker.sock:/var/run/docker.sock:ro"
      ];
      extraOptions = [ "--restart=unless-stopped" ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
