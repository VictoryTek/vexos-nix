# modules/server/nextcloud.nix
# Nextcloud — self-hosted file sync, calendar, and contacts.
# Secret default path: /etc/nixos/secrets/nextcloud-admin-pass
#   Override via vexos.server.nextcloud.adminPassFile for alternate backends.
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
# Reverse proxy mode (https = false, allowInsecureHttp = false):
#   Nextcloud stays on local HTTP loopback only (127.0.0.1 / ::1), intended for
#   same-host TLS termination by a reverse proxy.
#
# Insecure LAN mode (https = false, allowInsecureHttp = true):
#   Plain HTTP is exposed on port 80 and may leak passwords/session tokens.
#   Use only on intentionally isolated networks when no TLS path is available.
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
        Set to false for local reverse proxy HTTP backends or isolated LANs.
      '';
    };

    allowInsecureHttp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow plaintext HTTP exposure when https = false (default: false).
        When false and https = false, Nextcloud binds HTTP to loopback only
        for same-host reverse proxy TLS termination.
        Set to true only for explicitly accepted insecure LAN-only deployments.
      '';
    };

    adminPassFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/secrets/nextcloud-admin-pass";
      description = ''
        Path to the Nextcloud admin password file.
        Default keeps legacy plaintext behavior; the sops backend overrides this
        to a decrypted runtime secret path.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Nextcloud's HTTP/HTTPS port(s).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud30;
      hostName = cfg.hostName;
      config.adminpassFile = cfg.adminPassFile;
      https = cfg.https;
    };

    # Default non-HTTPS mode is loopback-only to support same-host reverse proxies safely.
    services.nginx.virtualHosts.${cfg.hostName} = lib.mkIf (!cfg.https && !cfg.allowInsecureHttp) {
      listen = [
        { addr = "127.0.0.1"; port = 80; }
        { addr = "[::1]"; port = 80; }
      ];
    };

    # Port 80 is open in HTTPS mode (redirect path) or explicit insecure mode.
    # Port 443 is open only when HTTPS mode is enabled.
    networking.firewall.allowedTCPPorts =
      lib.optional (cfg.openFirewall && (cfg.https || cfg.allowInsecureHttp)) 80
      ++ lib.optional (cfg.openFirewall && cfg.https) 443;
  };
}
