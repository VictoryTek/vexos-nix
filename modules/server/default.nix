# modules/server/default.nix
# Umbrella import for all optional server service modules.
# Each module exposes a vexos.server.<service>.enable option (default: false).
# Services are activated by setting the flag in /etc/nixos/server-services.nix.
{
  imports = [
    ./docker.nix
    ./jellyfin.nix
    ./plex.nix
    ./papermc.nix
    ./immich.nix
    ./vaultwarden.nix
    ./nextcloud.nix
    ./forgejo.nix
    ./syncthing.nix
    ./cockpit.nix
    ./uptime-kuma.nix
    ./stirling-pdf.nix
    ./audiobookshelf.nix
    ./homepage.nix
    ./caddy.nix
    ./arr.nix
    ./adguard.nix
    ./home-assistant.nix
  ];
}
