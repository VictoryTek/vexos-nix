# modules/server/attic.nix
# Attic — modern, purpose-built NixOS binary cache server.
# Default port: 8400 (avoids conflicts with SABnzbd/scrutiny on 8080).
# Credentials default path: /etc/nixos/secrets/attic-credentials
#   Override via vexos.server.attic.environmentFile for alternate backends.
# Under the plaintext secrets backend, the RS256 signing key is generated
# automatically on first activation if the credentials file doesn't already
# exist (see the atticSecret activationScript below). Under the sops backend,
# secrets-sops.nix supplies the file instead.
# Permissions enforced at boot by modules/secrets.nix (0700 dir, 0600 files).
# The `attic` CLI is installed automatically when this module is enabled.
# After enabling and rebuilding, run `just attic-bootstrap` to create the
# cache, mint tokens, and print client/CI setup values.
# To push this repo's own custom pkgs/* packages (cockpit-navigator, portbook,
# vexos-update, etc.) after logging in, run: just attic-push [cache-name]
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.attic;
in
{
  options.vexos.server.attic = {
    enable = lib.mkEnableOption "Attic Nix binary cache server";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 8400;
      description = "Port for the Attic HTTP listener.";
    };

    dataDir = lib.mkOption {
      type    = lib.types.path;
      default = "/var/lib/atticd";
      description = "Directory for the SQLite database and local cache storage.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/secrets/attic-credentials";
      description = ''
        Path to the atticd environment file.
        Default keeps legacy plaintext behavior; the sops backend overrides this
        to a decrypted runtime template path.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Attic's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Auto-generate the RS256 signing key on first activation when using the
    # plaintext backend, so enabling Attic doesn't require a manual openssl
    # step. Under the sops backend, secrets-sops.nix forces environmentFile to
    # a sops-managed path that sops-nix itself populates at activation.
    system.activationScripts.atticSecret =
      lib.mkIf (config.vexos.secrets.backend != "sops") ''
        if [ ! -e "${cfg.environmentFile}" ]; then
          mkdir -p "$(dirname "${cfg.environmentFile}")"
          echo "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$(${pkgs.openssl}/bin/openssl genrsa -traditional 4096 2>/dev/null | ${pkgs.coreutils}/bin/base64 -w0)" \
            > "${cfg.environmentFile}"
          chmod 0600 "${cfg.environmentFile}"
        fi
      '';

    environment.systemPackages = [ pkgs.attic-client ];

    services.atticd = {
      enable = true;
      environmentFile = cfg.environmentFile;
      settings = {
        listen = "[::]:${toString cfg.port}";
        database.url = "sqlite://${cfg.dataDir}/db.sqlite?mode=rwc";
        storage = {
          type = "local";
          path = "${cfg.dataDir}/storage";
        };
        chunking = {
          nar-size-threshold = 65536;  # 64 KiB — chunk NARs larger than this
          min-size           = 16384;  # 16 KiB
          avg-size           = 65536;  # 64 KiB
          max-size           = 262144; # 256 KiB
        };
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
