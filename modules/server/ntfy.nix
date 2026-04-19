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
  };

  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        listen-http = ":2586";
        base-url = "http://localhost:2586";
        cache-file = "/var/lib/ntfy-sh/cache.db";
        auth-file = "/var/lib/ntfy-sh/auth.db";
        auth-default-access = "deny-all";
        behind-proxy = true;
      };
    };

    networking.firewall.allowedTCPPorts = [ 2586 ];
  };
}
