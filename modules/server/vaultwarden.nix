# modules/server/vaultwarden.nix
# Vaultwarden — lightweight Bitwarden-compatible password manager server.
#
# Required configuration:
#   vexos.server.vaultwarden.domain = "https://vault.example.com";
#
#   Without a DOMAIN, WebSocket push notifications and email/invite URLs
#   are constructed incorrectly and will not work.
#
# Admin panel / ADMIN_TOKEN:
#   The admin panel is disabled by default (no ADMIN_TOKEN set). To enable it,
#   provide ADMIN_TOKEN via an environment file:
#     services.vaultwarden.environmentFile = "/run/secrets/vaultwarden-env";
#   where the file contains:
#     ADMIN_TOKEN=<argon2id-or-bcrypt-hash-of-your-token>
#   See: https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page
#
# Network:
#   Vaultwarden binds to 127.0.0.1 by default. Expose it via a TLS-terminating
#   reverse proxy (Caddy, nginx, Traefik) and set the domain option to match.
#   The firewall port is only opened when openFirewall = true.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.vaultwarden;
in
{
  options.vexos.server.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden password manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8222;
      description = "Port for the Vaultwarden web vault.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "https://vault.example.com";
      description = ''
        Public HTTPS URL for this Vaultwarden instance, e.g.
        "https://vault.example.com". Used to construct WebSocket push
        notification URLs and email invite links. Must be set to the
        actual domain — the default placeholder is intentionally invalid.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the Vaultwarden port in the firewall. Disabled by default —
        Vaultwarden should be placed behind a TLS reverse proxy; only
        enable this if you are terminating TLS on this host.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an env file containing ADMIN_TOKEN=<argon2id-or-bcrypt-hash>.
        Loaded as a systemd EnvironmentFile. Enables the Vaultwarden admin panel.
        See: https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.domain != "https://vault.example.com";
        message = ''
          vexos.server.vaultwarden.domain must be set to the actual public URL
          of this Vaultwarden instance (e.g. "https://vault.example.com").
          Without a real DOMAIN, WebSocket push notifications and email invite
          links will be broken.
        '';
      }
    ];

    services.vaultwarden = {
      enable = true;
      config = {
        ROCKET_PORT    = cfg.port;
        ROCKET_ADDRESS = "127.0.0.1";
        SIGNUPS_ALLOWED = false;
        DOMAIN         = cfg.domain;
      };
      environmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
    };

    networking.firewall.allowedTCPPorts =
      lib.optional cfg.openFirewall cfg.port;
  };
}

