# modules/server/nextcloud.nix
# Nextcloud — self-hosted file sync, calendar, and contacts.
# Secrets: /etc/nixos/secrets/nextcloud-admin-pass (plain text, single-line admin password)
#   Create with: sudo install -m 0600 -o root -g root /dev/stdin /etc/nixos/secrets/nextcloud-admin-pass
#   Permissions enforced at boot by modules/secrets.nix (0700 dir, 0600 files).
#
# TLS (https = true, the default):
#   NixOS nginx sets overwriteprotocol = https internally. You must supply a TLS cert:
#     Option A — Let's Encrypt (public domain):
#       services.nginx.virtualHosts.${cfg.hostName}.enableACME = true;
#       services.nginx.virtualHosts.${cfg.hostName}.forceSSL = true;
#       security.acme.acceptTerms = true;
#       security.acme.defaults.email = "admin@example.com";
#     Option B — Local self-signed / LAN CA:
#       services.nginx.virtualHosts.${cfg.hostName}.sslCertificate = "/etc/nixos/secrets/nextcloud.crt";
#       services.nginx.virtualHosts.${cfg.hostName}.sslCertificateKey = "/etc/nixos/secrets/nextcloud.key";
#       services.nginx.virtualHosts.${cfg.hostName}.forceSSL = true;
#   Without forceSSL, nginx will serve HTTP but Nextcloud will embed HTTPS in its URLs
#   (mixed content). Configure forceSSL alongside https = true.
#
#   Set https = false ONLY on fully-isolated LANs where no TLS termination is available.
#   Plain HTTP exposes Nextcloud passwords and OAuth session tokens in cleartext.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.nextcloud;
in
{
  options.vexos.server.nextcloud = {
    enable = lib.mkEnableOption "Nextcloud file sync and collaboration";

    hostName = lib.mkOption {
      type = lib.types.str;
      default = "nextcloud.local";
      description = "FQDN for the Nextcloud instance.";
    };

    https = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether Nextcloud is accessed over HTTPS (default: true).
        When enabled, Nextcloud sets overwriteprotocol = https and generates HTTPS URLs.
        You must additionally configure TLS in services.nginx.virtualHosts — see the
        module header comment for options A and B.
        Set to false only on fully-isolated LANs without TLS termination.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud30;
      hostName = cfg.hostName;
      config.adminpassFile = "/etc/nixos/secrets/nextcloud-admin-pass";
      https = cfg.https;
    };

    # Open port 80 always (HTTP redirect when https=true; direct access when https=false).
    # Open port 443 when HTTPS is enabled so the nginx TLS listener is reachable.
    networking.firewall.allowedTCPPorts =
      [ 80 ] ++ lib.optional cfg.https 443;
  };
}
