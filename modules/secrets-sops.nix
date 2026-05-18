# modules/secrets-sops.nix
# Encrypted secrets backend for server roles (sops-nix), with plaintext fallback
# controlled by vexos.secrets.backend.
{ config, lib, ... }:
let
  cfg = config.vexos.secrets;
in
{
  options.vexos.secrets = {
    backend = lib.mkOption {
      type = lib.types.enum [ "plaintext" "sops" ];
      default = "plaintext";
      description = ''
        Secrets backend for server modules.
        plaintext = use /etc/nixos/secrets/* compatibility paths.
        sops = decrypt runtime secrets via sops-nix.
      '';
    };

    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "./secrets/server/secrets.yaml";
      description = ''
        Encrypted sops file containing server secrets.
        Required when vexos.secrets.backend = "sops".
      '';
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sops-nix/key.txt";
      description = "Path to the local age private key used for decryption.";
    };

    ageGenerateKey = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Generate ageKeyFile automatically if it does not exist.";
    };

    ageSshKeyPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/etc/ssh/ssh_host_ed25519_key" ];
      description = "SSH private keys to import as age identities.";
    };
  };

  config = lib.mkIf (cfg.backend == "sops") {
    assertions = [
      {
        assertion = cfg.sopsFile != null;
        message = "vexos.secrets.sopsFile must be set when vexos.secrets.backend = \"sops\".";
      }
      {
        assertion = config.sops.secrets ? "nextcloud-admin-pass";
        message = "sops secret 'nextcloud-admin-pass' must be declared for vexos.secrets.backend = \"sops\".";
      }
      {
        assertion = config.sops.secrets ? "photoprism-password";
        message = "sops secret 'photoprism-password' must be declared for vexos.secrets.backend = \"sops\".";
      }
      {
        assertion = config.sops.secrets ? "minio-root-user";
        message = "sops secret 'minio-root-user' must be declared for vexos.secrets.backend = \"sops\".";
      }
      {
        assertion = config.sops.secrets ? "minio-root-password";
        message = "sops secret 'minio-root-password' must be declared for vexos.secrets.backend = \"sops\".";
      }
      {
        assertion = config.sops.secrets ? "attic-server-token-rs256-secret-base64";
        message = "sops secret 'attic-server-token-rs256-secret-base64' must be declared for vexos.secrets.backend = \"sops\".";
      }
    ];

    sops = {
      age = {
        keyFile = cfg.ageKeyFile;
        generateKey = cfg.ageGenerateKey;
        sshKeyPaths = cfg.ageSshKeyPaths;
      };

      secrets = {
        nextcloud-admin-pass = {
          owner = "root";
          group = "root";
          mode = "0400";
        };

        photoprism-password = {
          owner = "root";
          group = "root";
          mode = "0400";
        };

        minio-root-user = {
          owner = "root";
          group = "root";
          mode = "0400";
        };

        minio-root-password = {
          owner = "root";
          group = "root";
          mode = "0400";
        };

        attic-server-token-rs256-secret-base64 = {
          owner = "root";
          group = "root";
          mode = "0400";
        };
      };

      templates = {
        "minio-credentials" = {
          owner = "root";
          group = "root";
          mode = "0400";
          content = ''
            MINIO_ROOT_USER=${config.sops.placeholder.minio-root-user}
            MINIO_ROOT_PASSWORD=${config.sops.placeholder.minio-root-password}
          '';
        };

        "attic-credentials" = {
          owner = "root";
          group = "root";
          mode = "0400";
          content = ''
            ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=${config.sops.placeholder.attic-server-token-rs256-secret-base64}
          '';
        };
      };
    } // lib.optionalAttrs (cfg.sopsFile != null) {
      defaultSopsFile = cfg.sopsFile;
    };

    vexos.server.nextcloud.adminPassFile = lib.mkForce config.sops.secrets."nextcloud-admin-pass".path;
    vexos.server.photoprism.passwordFile = lib.mkForce config.sops.secrets."photoprism-password".path;
    vexos.server.minio.rootCredentialsFile = lib.mkForce config.sops.templates."minio-credentials".path;
    vexos.server.attic.environmentFile = lib.mkForce config.sops.templates."attic-credentials".path;
  };
}