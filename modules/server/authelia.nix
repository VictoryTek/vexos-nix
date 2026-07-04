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

    jwtSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing the JWT secret, passed to the container via
        Authelia's native AUTHELIA_JWT_SECRET_FILE mechanism.
      '';
    };

    sessionSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing the session secret, passed to the container via
        Authelia's native AUTHELIA_SESSION_SECRET_FILE mechanism.
      '';
    };

    storageEncryptionKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing the storage encryption key, passed to the container
        via Authelia's native AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE mechanism.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Authelia's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    virtualisation.oci-containers.containers.authelia = {
      image = "authelia/authelia:4.39.20";
      ports = [ "${toString cfg.port}:9091" ];
      volumes = [
        "/var/lib/authelia/config:/config"
      ]
      ++ lib.optional (cfg.jwtSecretFile != null) "${cfg.jwtSecretFile}:/secrets/jwt_secret:ro"
      ++ lib.optional (cfg.sessionSecretFile != null) "${cfg.sessionSecretFile}:/secrets/session_secret:ro"
      ++ lib.optional (cfg.storageEncryptionKeyFile != null) "${cfg.storageEncryptionKeyFile}:/secrets/storage_encryption_key:ro";
      environment = {
        TZ = config.time.timeZone;
      }
      // lib.optionalAttrs (cfg.jwtSecretFile != null) {
        AUTHELIA_JWT_SECRET_FILE = "/secrets/jwt_secret";
      }
      // lib.optionalAttrs (cfg.sessionSecretFile != null) {
        AUTHELIA_SESSION_SECRET_FILE = "/secrets/session_secret";
      }
      // lib.optionalAttrs (cfg.storageEncryptionKeyFile != null) {
        AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE = "/secrets/storage_encryption_key";
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
