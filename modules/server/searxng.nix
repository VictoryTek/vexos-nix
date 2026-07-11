# modules/server/searxng.nix
# SearXNG — self-hosted private metasearch engine.
# Hardened for privacy by default: no query logging, POST-based search
# submissions (queries stay out of URLs/logs), loopback-only unless opted in.
# Default port: 8888
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.searxng;
in
{
  options.vexos.server.searxng = {
    enable = lib.mkEnableOption "SearXNG private metasearch engine";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Port for the SearXNG HTTP listener.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the firewall for SearXNG's port. Defaults to false — this is a
        private instance intended for localhost/LAN reverse-proxy access, not
        direct public exposure.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an environment file providing SEARXNG_SECRET_KEY, referenced
        from settings.yml as $SEARXNG_SECRET_KEY. Required for a working
        instance (SearXNG needs a secret key for session/CSRF signing). File
        should not be world-readable (chmod 600 recommended).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.searx = {
      enable = true;
      environmentFile = cfg.environmentFile;
      openFirewall = cfg.openFirewall;

      # uWSGI instead of the built-in Werkzeug server: the built-in server
      # logs all queries by default (see upstream configureUwsgi option
      # description). uWSGI + disable-logging avoids that entirely.
      configureUwsgi = true;
      uwsgiConfig = {
        disable-logging = true;
        http = ":${toString cfg.port}";
      };

      settings = {
        use_default_settings = true;
        server = {
          port = cfg.port;
          bind_address = "127.0.0.1";
          secret_key = "$SEARXNG_SECRET_KEY";
          method = "POST"; # keep queries out of URLs/logs/referrers
        };
        search = {
          safe_search = 0;
          autocomplete = "";
        };
      };
    };
  };
}
