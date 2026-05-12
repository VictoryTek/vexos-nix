# modules/server/default.nix
# Umbrella import for all optional server service modules.
# Each module exposes a vexos.server.<service>.enable option (default: false).
# Services are activated by setting the flag in /etc/nixos/server-services.nix.
{
  imports = [
    # ── Container Runtime ────────────────────────────────────────────────────
    ./docker.nix
    # ── Media Servers ────────────────────────────────────────────────────────
    ./jellyfin.nix
    ./plex.nix
    ./audiobookshelf.nix
    ./tautulli.nix
    ./navidrome.nix
    # ── Media Requests ───────────────────────────────────────────────────────
    ./seerr.nix
    ./jellyseerr.nix
    # ── Media Automation (Arr Stack) ─────────────────────────────────────────
    ./arr.nix
    # ── Books & Comics ───────────────────────────────────────────────────────
    ./komga.nix
    ./kavita.nix
    # ── Game Servers ─────────────────────────────────────────────────────────
    ./papermc.nix
    # ── Cloud & Files ────────────────────────────────────────────────────────
    ./nextcloud.nix
    ./syncthing.nix
    ./immich.nix
    ./minio.nix
    ./photoprism.nix
    # ── Documents ────────────────────────────────────────────────────────────
    ./paperless.nix
    # ── Development ──────────────────────────────────────────────────────────
    ./forgejo.nix
    ./code-server.nix
    ./attic.nix
    # ── AI & Privacy ─────────────────────────────────────────────────────────
    ./kiji-proxy.nix
    # ── Security ─────────────────────────────────────────────────────────────
    ./vaultwarden.nix
    ./authelia.nix
    # ── Networking & Reverse Proxies ─────────────────────────────────────────
    ./nginx.nix
    ./caddy.nix
    ./traefik.nix
    ./adguard.nix
    ./headscale.nix
    ./unbound.nix
    ./nginx-proxy-manager.nix
    # ── Monitoring & Management ──────────────────────────────────────────────
    ./cockpit.nix
    ./nas.nix          # Phase D: NAS stack umbrella (cockpit + plugins)
    ./uptime-kuma.nix
    ./homepage.nix
    ./grafana.nix
    ./scrutiny.nix
    ./prometheus.nix
    ./loki.nix
    ./netdata.nix
    ./dozzle.nix
    ./portainer.nix
    # ── Notifications ────────────────────────────────────────────────────────
    ./ntfy.nix
    # ── Food & Home ──────────────────────────────────────────────────────────
    ./mealie.nix
    ./listmonk.nix
    # ── Remote Access ────────────────────────────────────────────────────────
    ./rustdesk.nix
    # ── Automation & Smart Home ──────────────────────────────────────────────
    ./home-assistant.nix
    ./node-red.nix
    ./zigbee2mqtt.nix
    # ── Communications ───────────────────────────────────────────────────────
    ./matrix-conduit.nix
    # ── PDF Tools ────────────────────────────────────────────────────────────
    ./stirling-pdf.nix
    # ── Virtualisation ────────────────────────────────────────────────────────────
    ./proxmox.nix
  ];
}
