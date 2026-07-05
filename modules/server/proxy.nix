# modules/server/proxy.nix
# Caddy LAN reverse-proxy layer — generates a "<service>.<hostname>.local"
# Caddy virtualHost for every enabled service with a web UI, instead of
# remembering ~40 raw ports. Requires vexos.server.caddy.enable — adds
# virtualHosts to that same Caddy instance rather than starting a second one.
#
# Caddy automatically uses its internal CA (not ACME/Let's Encrypt) for
# ".local" and other non-public hostnames, so these get real local TLS with
# no extra configuration.
#
# Scope note: this does NOT publish any Avahi/mDNS records for these names —
# the existing Avahi setup (modules/network.nix, modules/network-desktop.nix)
# is relied on elsewhere for SMB/NAS discovery and is deliberately left
# untouched here. Resolve "<service>.<hostname>.local" via your own DNS or
# /etc/hosts on the client.
#
# Maintenance note: the service table below is hand-maintained. Adding a new
# server module with a web UI needs a one-line addition here to pick it up —
# there's no automatic registration mechanism (would require touching every
# existing service module to add one, which is out of scope for this file).
{ config, lib, ... }:
let
  cfg = config.vexos.server.proxy;
  hostName = config.networking.hostName;

  services = [
    { name = "adguard"; enable = config.vexos.server.adguard.enable; port = config.vexos.server.adguard.port; }
    { name = "seerr"; enable = config.vexos.server.seerr.enable; port = config.vexos.server.seerr.port; }
    { name = "home-assistant"; enable = config.vexos.server.home-assistant.enable; port = 8123; }
    { name = "cockpit"; enable = config.vexos.server.cockpit.enable; port = config.vexos.server.cockpit.port; }
    { name = "tautulli"; enable = config.vexos.server.tautulli.enable; port = 8181; }
    { name = "immich"; enable = config.vexos.server.immich.enable; port = config.vexos.server.immich.port; }
    { name = "jellyfin"; enable = config.vexos.server.jellyfin.enable; port = 8096; }
    { name = "audiobookshelf"; enable = config.vexos.server.audiobookshelf.enable; port = config.vexos.server.audiobookshelf.port; }
    { name = "kiji-proxy"; enable = config.vexos.server.kiji-proxy.enable; port = config.vexos.server.kiji-proxy.port; }
    { name = "portbook"; enable = config.vexos.server.portbook.enable; port = 7777; }
    { name = "komga"; enable = config.vexos.server.komga.enable; port = 8080; }
    { name = "plex"; enable = config.vexos.server.plex.enable; port = 32400; }
    { name = "prometheus"; enable = config.vexos.server.prometheus.enable; port = config.vexos.server.prometheus.port; }
    { name = "alertmanager"; enable = config.vexos.server.alertmanager.enable; port = config.vexos.server.alertmanager.port; }
    { name = "vaultwarden"; enable = config.vexos.server.vaultwarden.enable; port = config.vexos.server.vaultwarden.port; }
    { name = "zigbee2mqtt"; enable = config.vexos.server.zigbee2mqtt.enable; port = config.vexos.server.zigbee2mqtt.port; }
    { name = "node-red"; enable = config.vexos.server.node-red.enable; port = 1880; }
    { name = "scrutiny"; enable = config.vexos.server.scrutiny.enable; port = config.vexos.server.scrutiny.port; }
    { name = "vexboard"; enable = config.vexos.server.vexboard.enable; port = config.vexos.server.vexboard.port; }
    { name = "headscale"; enable = config.vexos.server.headscale.enable; port = config.vexos.server.headscale.port; }
    { name = "forgejo"; enable = config.vexos.server.forgejo.enable; port = config.vexos.server.forgejo.port; }
    { name = "minio"; enable = config.vexos.server.minio.enable; port = config.vexos.server.minio.consolePort; }
    { name = "arcane"; enable = config.vexos.server.arcane.enable; port = config.vexos.server.arcane.port; }
    { name = "dozzle"; enable = config.vexos.server.dozzle.enable; port = config.vexos.server.dozzle.port; }
    { name = "attic"; enable = config.vexos.server.attic.enable; port = config.vexos.server.attic.port; }
    { name = "paperless"; enable = config.vexos.server.paperless.enable; port = config.vexos.server.paperless.port; }
    { name = "grafana"; enable = config.vexos.server.grafana.enable; port = config.vexos.server.grafana.port; }
    { name = "dockhand"; enable = config.vexos.server.dockhand.enable; port = config.vexos.server.dockhand.port; }
    { name = "stirling-pdf"; enable = config.vexos.server.stirling-pdf.enable; port = config.vexos.server.stirling-pdf.port; }
    { name = "code-server"; enable = config.vexos.server.code-server.enable; port = config.vexos.server.code-server.port; }
    { name = "kavita"; enable = config.vexos.server.kavita.enable; port = config.vexos.server.kavita.port; }
    { name = "navidrome"; enable = config.vexos.server.navidrome.enable; port = config.vexos.server.navidrome.port; }
    { name = "portainer"; enable = config.vexos.server.portainer.enable; port = config.vexos.server.portainer.port; }
    { name = "photoprism"; enable = config.vexos.server.photoprism.enable; port = config.vexos.server.photoprism.port; }
    { name = "ntfy"; enable = config.vexos.server.ntfy.enable; port = config.vexos.server.ntfy.port; }
    { name = "authelia"; enable = config.vexos.server.authelia.enable; port = config.vexos.server.authelia.port; }
    { name = "listmonk"; enable = config.vexos.server.listmonk.enable; port = config.vexos.server.listmonk.port; }
    { name = "homepage"; enable = config.vexos.server.homepage.enable; port = config.vexos.server.homepage.port; }
    { name = "uptime-kuma"; enable = config.vexos.server.uptime-kuma.enable; port = config.vexos.server.uptime-kuma.port; }
    { name = "mealie"; enable = config.vexos.server.mealie.enable; port = config.vexos.server.mealie.port; }
    { name = "proxmox"; enable = config.vexos.server.proxmox.enable; port = 8006; }
    { name = "sonarr"; enable = config.vexos.server.arr.enable; port = 8989; }
    { name = "radarr"; enable = config.vexos.server.arr.enable; port = 7878; }
    { name = "lidarr"; enable = config.vexos.server.arr.enable; port = 8686; }
    { name = "prowlarr"; enable = config.vexos.server.arr.enable; port = 9696; }
    { name = "sabnzbd"; enable = config.vexos.server.arr.enable; port = 8080; }
    { name = "qbittorrent"; enable = config.vexos.server.arr.qbittorrent.enable; port = 8081; }
    { name = "bazarr"; enable = config.vexos.server.arr.bazarr.enable; port = 6767; }
  ];

  enabledServices = builtins.filter (s: s.enable) services;

  virtualHosts = builtins.listToAttrs (map
    (s: {
      name = "${s.name}.${hostName}.local";
      value.extraConfig = "reverse_proxy 127.0.0.1:${toString s.port}";
    })
    enabledServices);
in
{
  options.vexos.server.proxy = {
    enable = lib.mkEnableOption "Caddy LAN reverse-proxy layer (service names instead of raw ports)";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.vexos.server.caddy.enable;
        message = "vexos.server.proxy.enable requires vexos.server.caddy.enable = true — the proxy layer adds virtualHosts to that Caddy instance.";
      }
    ];

    services.caddy.virtualHosts = virtualHosts;
  };
}
