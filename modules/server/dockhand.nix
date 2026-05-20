# modules/server/dockhand.nix
# Dockhand — container management UI that speaks the Docker API.
# Deployed as an OCI container backed by Podman. Mounts the Podman
# Docker-compat socket so Dockhand can manage containers on this host.
#
# Prerequisites:
#   vexos.server.podman.enable = true   (enforced by assertion below)
#
# Default access:  http://<host-ip>:8073
# On first launch: authentication is DISABLED — go to Settings > Authentication
#                  immediately after first access to secure the instance.
#
# Data is stored at vexos.server.dockhand.dataDir (default /var/lib/dockhand).
# Using matching paths (host path == container path) so compose stacks with
# relative volume bind mounts work correctly.
{ config, lib, ... }:
let
  cfg = config.vexos.server.dockhand;
in
{
  options.vexos.server.dockhand = {
    enable = lib.mkEnableOption "Dockhand container management UI";

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 8073; # 3000 is Forgejo's default port; shifted to 8073 to avoid conflict
      description = "Host port on which Dockhand listens.";
    };

    dataDir = lib.mkOption {
      type        = lib.types.str;
      default     = "/var/lib/dockhand";
      description = ''
        Host directory for Dockhand persistent data (SQLite database, compose
        stack definitions, Git repository clones).
        Uses matching paths: this directory is mounted at the same absolute
        path inside the container and DATA_DIR is set accordingly.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.vexos.server.podman.enable;
        message   = "vexos.server.dockhand.enable requires vexos.server.podman.enable = true. Enable Podman first.";
      }
    ];

    # Ensure the data directory exists with correct permissions before the
    # container service starts.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root -"
    ];

    virtualisation.oci-containers.containers.dockhand = {
      image     = "ghcr.io/finsys/dockhand:latest";
      autoStart = true;

      # Expose Dockhand on the configured host port.
      ports = [ "0.0.0.0:${toString cfg.port}:3000" ];

      # Mount the Podman Docker-compat socket (created by dockerCompat = true)
      # and the persistent data directory using matching paths.
      volumes = [
        "/run/podman/podman.sock:/var/run/docker.sock:ro"  # Podman native socket (read-only)
        "${cfg.dataDir}:${cfg.dataDir}"          # Matching-path persistent data
      ];

      environment = {
        DATA_DIR = cfg.dataDir;
      };

      # Run as root to avoid Docker group GID-matching complexity.
      # Acceptable for home-lab environments per Dockhand official docs.
      # See: https://dockhand.pro/manual/#docker-socket-permissions
      user = "0:0";
    };

    # Open the firewall for Dockhand's web UI.
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
