# modules/server/ntfy.nix
# ntfy — self-hosted push notification service.
# Send notifications to your phone or desktop via HTTP PUT/POST.
# Default port: 2586
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.ntfy;
in
{
  options.vexos.server.ntfy = {
    enable = lib.mkEnableOption "ntfy push notification server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2586;
      description = "Port for the ntfy HTTP listener.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for ntfy's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        listen-http = ":${toString cfg.port}";
        base-url = "http://localhost:${toString cfg.port}";
        cache-file = "/var/lib/ntfy-sh/cache.db";
        auth-file = "/var/lib/ntfy-sh/auth.db";
        auth-default-access = "deny-all";
        behind-proxy = true;
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
