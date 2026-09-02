# modules/server/cloudflare-ddns.nix
# Cloudflare DDNS — keeps a Cloudflare DNS record pointed at this host's
# current public IP (oznu/cloudflare-ddns). Single OCI container, no
# persistent state: the container polls on a cron schedule and writes the
# result straight to Cloudflare's API, so there is no dataDir, no volume,
# no port, and no backup registration. It is listed in backup.nix's
# noBackupNeeded for exactly that reason.
#
# Upstream: https://github.com/oznu/docker-cloudflare-ddns
#
# Required configuration — unlike grimmory/joplin, the credential here is an
# external Cloudflare API token, so it cannot be auto-generated on first
# activation. Supply it yourself:
#
#   vexos.server.cloudflare-ddns.environmentFile = "/etc/nixos/secrets/cloudflare-ddns-env";
#
#   printf 'API_KEY=%s\n' "<scoped API token>" > /etc/nixos/secrets/cloudflare-ddns-env
#   chmod 0600 /etc/nixos/secrets/cloudflare-ddns-env
#
# The token needs Zone:DNS:Edit on the zone being updated. ZONE and the other
# non-secret settings are plain module options below, so only the token
# itself lives in the secret file.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.cloudflare-ddns;
in
{
  options.vexos.server.cloudflare-ddns = {
    enable = lib.mkEnableOption "Cloudflare dynamic DNS updater";

    zone = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = "The Cloudflare DNS zone updates are applied to (ZONE).";
    };

    subdomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "home";
      description = ''
        Subdomain within the zone to update (SUBDOMAIN). Leave null to
        update the root zone record.
      '';
    };

    proxied = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Route traffic for the record through Cloudflare's CDN (PROXIED).
        Upstream's default is false. Note that proxying hides the origin IP
        but also breaks non-HTTP protocols on that name.
      '';
    };

    recordType = lib.mkOption {
      type = lib.types.enum [ "A" "AAAA" ];
      default = "A";
      description = "DNS record type to maintain (RRTYPE): A for IPv4, AAAA for IPv6.";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*/5 * * * *";
      description = "Cron expression controlling how often the IP is checked (CRON).";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      example = "/etc/nixos/secrets/cloudflare-ddns-env";
      description = ''
        systemd EnvironmentFile supplying API_KEY=<scoped Cloudflare API
        token>. Required — this credential is issued by Cloudflare and
        cannot be generated locally the way grimmory's and joplin's database
        passwords are.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.zone != "";
        message = "vexos.server.cloudflare-ddns.zone must be set to the Cloudflare zone to update (e.g. \"example.com\").";
      }
    ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    virtualisation.oci-containers.containers.cloudflare-ddns = {
      image = "oznu/cloudflare-ddns:latest";
      environment = {
        ZONE    = cfg.zone;
        PROXIED = lib.boolToString cfg.proxied;
        RRTYPE  = cfg.recordType;
        CRON    = cfg.schedule;
      } // lib.optionalAttrs (cfg.subdomain != null) {
        SUBDOMAIN = cfg.subdomain;
      };
      environmentFiles = [ cfg.environmentFile ];
    };
  };
}
