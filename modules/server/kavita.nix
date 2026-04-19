# modules/server/kavita.nix
# Kavita — self-hosted digital library server for ebooks, comics, and manga.
# Default port: 5000
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.kavita;
in
{
  options.vexos.server.kavita = {
    enable = lib.mkEnableOption "Kavita ebook and manga library server";
  };

  config = lib.mkIf cfg.enable {
    services.kavita = {
      enable = true;
      port = 5000;
      tokenKeyFile = "/var/lib/kavita/token-key"; # Must exist; generate with: openssl rand -base64 32 > /var/lib/kavita/token-key
    };

    networking.firewall.allowedTCPPorts = [ 5000 ];
  };
}
