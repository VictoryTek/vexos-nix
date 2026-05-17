# modules/server/nextcloud.nix
# Nextcloud — self-hosted file sync, calendar, and contacts.
# Secrets: /etc/nixos/secrets/nextcloud-admin-pass (plain text, single-line admin password)
#   Create with: sudo install -m 0600 -o root -g root /dev/stdin /etc/nixos/secrets/nextcloud-admin-pass
#   Permissions enforced at boot by modules/secrets.nix (0700 dir, 0600 files).
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
  };

  config = lib.mkIf cfg.enable {
    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud30;
      hostName = cfg.hostName;
      config.adminpassFile = "/etc/nixos/secrets/nextcloud-admin-pass";
      https = false; # Set to true if Caddy/reverse proxy handles TLS
    };

    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
