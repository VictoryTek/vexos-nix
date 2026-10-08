# modules/server/mealie.nix
# Mealie — self-hosted recipe manager and meal planner (OCI container).
# Run from the upstream image rather than nixpkgs' services.mealie, which lags
# upstream by many releases (and Mealie refuses to restore newer-version
# backups). Bump the image tag deliberately after reading the release notes.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.mealie;
in
{
  options.vexos.server.mealie = {
    enable = lib.mkEnableOption "Mealie recipe manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9010;
      description = "Port for the Mealie web interface.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Mealie's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Named Docker/Podman volume, not a /var/lib bind mount.
    vexos.server.backup.servicePaths.mealie = [
      (if config.virtualisation.oci-containers.backend == "podman"
       then "/var/lib/containers/storage/volumes/mealie-data/_data"
       else "/var/lib/docker/volumes/mealie-data/_data")
    ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    virtualisation.oci-containers.containers.mealie = {
      image = "ghcr.io/mealie-recipes/mealie:v3.28.0";
      ports = [ "${toString cfg.port}:9000" ];
      volumes = [ "mealie-data:/app/data" ];
      environment = {
        TZ = if config.time.timeZone != null then config.time.timeZone else "UTC";
        ALLOW_SIGNUP = "false";
      };
      # Upstream recommends a memory limit; Python otherwise idles high.
      extraOptions = [ "--memory=1000m" ];
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
