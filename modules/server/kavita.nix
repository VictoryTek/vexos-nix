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
      tokenKeyFile = "/var/lib/kavita/token-key";
    };

    # Auto-generate the JWT signing key on first activation. This is a purely
    # internal secret (never typed or memorized by a user, unlike a login
    # password), so there's no reason to require manual creation — without
    # this, kavita.service crash-loops forever, since LoadCredential fails to
    # start the unit at all when the referenced file is missing.
    system.activationScripts.kavitaTokenKey = ''
      if [ ! -e /var/lib/kavita/token-key ]; then
        mkdir -p /var/lib/kavita
        ${pkgs.openssl}/bin/openssl rand -base64 64 | tr -d '\n' > /var/lib/kavita/token-key
        chmod 0600 /var/lib/kavita/token-key
      fi
    '';

    networking.firewall.allowedTCPPorts = [ 5000 ];
  };
}
