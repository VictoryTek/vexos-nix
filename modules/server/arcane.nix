# modules/server/arcane.nix
# Arcane — Docker container management UI (OCI container, Docker backend).
# Grants Arcane control of the host's Docker daemon via the mounted socket —
# equivalent access level to Portainer; treat as root-equivalent exposure.
#
# Default access: http://<host-ip>:3552
#
# Required configuration:
#   vexos.server.arcane.appUrl          = "https://arcane.example.com";
#   vexos.server.arcane.environmentFile = "/etc/nixos/secrets/arcane-env";
#
#   The environment file must be a systemd EnvironmentFile (KEY=VALUE lines)
#   containing ENCRYPTION_KEY and JWT_SECRET, e.g.:
#     echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"  > /etc/nixos/secrets/arcane-env
#     echo "JWT_SECRET=$(openssl rand -hex 32)"     >> /etc/nixos/secrets/arcane-env
#     chmod 0600 /etc/nixos/secrets/arcane-env
#   Without these, Arcane cannot encrypt stored secrets or sign auth tokens.
{ config, lib, ... }:
let
  cfg = config.vexos.server.arcane;
in
{
  options.vexos.server.arcane = {
    enable = lib.mkEnableOption "Arcane Docker management UI";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3552;
      description = "Host port on which Arcane listens.";
    };

    appUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://arcane.example.com";
      description = ''
        Public URL for this Arcane instance, e.g. "https://arcane.example.com".
        Used by Arcane to construct links and redirects. Must be set to the
        actual URL — the default placeholder is intentionally invalid.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a systemd EnvironmentFile (KEY=VALUE lines) providing
        ENCRYPTION_KEY and JWT_SECRET (each a 32-byte value, e.g. from
        `openssl rand -hex 32`). Required before enabling Arcane.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Arcane's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.appUrl != "http://arcane.example.com";
        message = ''
          vexos.server.arcane.appUrl must be set to the actual public URL of
          this Arcane instance (e.g. "https://arcane.example.com").
        '';
      }
      {
        assertion = cfg.environmentFile != null;
        message = ''
          vexos.server.arcane.environmentFile must be set before enabling Arcane.
          Generate one with:
            echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"  > /etc/nixos/secrets/arcane-env
            echo "JWT_SECRET=$(openssl rand -hex 32)"     >> /etc/nixos/secrets/arcane-env
            chmod 0600 /etc/nixos/secrets/arcane-env
          Then set: vexos.server.arcane.environmentFile = "/etc/nixos/secrets/arcane-env";
        '';
      }
    ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.arcane = {
      image = "ghcr.io/getarcaneapp/manager:latest";
      ports = [ "${toString cfg.port}:3552" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "arcane-data:/app/data"
      ];
      environment = {
        APP_URL = cfg.appUrl;
        PUID = "65532";
        PGID = "65532";
      };
      environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
