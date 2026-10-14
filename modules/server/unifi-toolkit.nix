# modules/server/unifi-toolkit.nix
# UniFi Toolkit — monitoring and management tools (Wi-Fi Stalker, Threat
# Watch, Network Pulse, House Arrest) for UniFi OS consoles. No nixpkgs
# package exists, so it is deployed as the upstream OCI container with its
# SQLite database under dataDir.
#
# Runs in upstream's "local" mode (no login) — keep it on the LAN, or put it
# behind Authelia when exposing it. Upstream's bundled Caddy profile is not
# used; proxy.nix / caddy.nix provide the reverse proxy instead.
#
# ENCRYPTION_KEY (encrypts the stored controller credentials) is generated
# into environmentFile on first activation. Do not change it afterwards or the
# saved credentials become unreadable. Controller URL, API key and site are
# entered in the web UI (gear icon).
#
# Upstream: https://github.com/Crosstalk-Solutions/unifi-toolkit
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.unifi-toolkit;
in
{
  options.vexos.server.unifi-toolkit = {
    enable = lib.mkEnableOption "UniFi Toolkit monitoring suite for UniFi OS consoles";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8010;
      description = "Host port for the UniFi Toolkit web UI (upstream's 8000 is taken by mediamanager).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/unifi-toolkit";
      description = "Host directory bind-mounted to /app/data — the SQLite database.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/secrets/unifi-toolkit-env";
      description = ''
        systemd EnvironmentFile holding ENCRYPTION_KEY (a Fernet key).
        Generated on first activation if missing.
      '';
    };

    allowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "unifi.example.com" ];
      description = ''
        Extra hostnames the app accepts in the Host header (ALLOWED_HOSTS).
        IP addresses, localhost and .local/.lan/.internal/.home names are
        always accepted; add a public domain here when serving it through
        a reverse proxy under that name.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for UniFi Toolkit's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    vexos.server.backup.servicePaths.unifi-toolkit = [ cfg.dataDir ];

    # Fernet key = URL-safe base64 of 32 random bytes.
    system.activationScripts.unifiToolkitSecret = ''
      if [ ! -e "${cfg.environmentFile}" ]; then
        mkdir -p "$(dirname "${cfg.environmentFile}")"
        ( umask 077
          echo "ENCRYPTION_KEY=$(${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/base64 -w0 | ${pkgs.coreutils}/bin/tr '+/' '-_')" \
            > "${cfg.environmentFile}" )
      fi
    '';

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    # The image runs as UID/GID 1000.
    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 1000 1000 -" ];

    virtualisation.oci-containers.containers.unifi-toolkit = {
      image = "ghcr.io/crosstalk-solutions/unifi-toolkit:1.13.2";
      ports = [ "${toString cfg.port}:8000" ];
      environment = {
        DEPLOYMENT_TYPE = "local";
        TZ = config.time.timeZone;
      } // lib.optionalAttrs (cfg.allowedHosts != [ ]) {
        ALLOWED_HOSTS = lib.concatStringsSep "," cfg.allowedHosts;
      };
      environmentFiles = [ cfg.environmentFile ];
      volumes = [ "${cfg.dataDir}:/app/data" ];
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
