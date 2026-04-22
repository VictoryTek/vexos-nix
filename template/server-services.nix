# /etc/nixos/server-services.nix
# Local feature toggles for the VexOS server role.
# Managed by `just enable <service>` / `just disable <service>`.
# After editing, run `just rebuild` or `just switch server <gpu>` to apply.
#
# Available services:
#   docker, jellyfin, plex, audiobookshelf, tautulli, overseerr, jellyseerr,
#   arr (SABnzbd + Sonarr + Radarr + Lidarr + Prowlarr),
#   komga, kavita, papermc, nextcloud, syncthing, immich, forgejo,
#   vaultwarden, nginx, caddy, traefik, adguard, headscale,
#   cockpit, uptime-kuma, homepage, grafana, scrutiny, ntfy,
#   mealie, rustdesk, home-assistant, stirling-pdf,
#   proxmox
{
  # ── Container Runtime ────────────────────────────────────────────────────
  # vexos.server.docker.enable = false;

  # ── Media Servers ────────────────────────────────────────────────────────
  # vexos.server.jellyfin.enable = false;
  # vexos.server.plex.enable = false;
  # vexos.server.plex.plexPass = false;                 # true = expose GPU for hardware transcoding (requires Plex Pass sub)
  # vexos.server.audiobookshelf.enable = false;         # Port 3000
  # vexos.server.tautulli.enable = false;               # Port 8181 — Plex analytics

  # ── Media Requests ───────────────────────────────────────────────────────
  # vexos.server.overseerr.enable = false;              # Port 5055 — Plex requests
  # vexos.server.jellyseerr.enable = false;             # Port 5055 — Jellyfin requests (pick one)

  # ── Media Automation (Arr Stack) ─────────────────────────────────────────
  # vexos.server.arr.enable = false;                    # SABnzbd:8080 Sonarr:8989 Radarr:7878 Lidarr:8686 Prowlarr:9696

  # ── Books & Comics ───────────────────────────────────────────────────────
  # vexos.server.komga.enable = false;                  # Port 8090 — comics/manga
  # vexos.server.kavita.enable = false;                 # Port 5000 — ebooks/manga

  # ── Game Servers ─────────────────────────────────────────────────────────
  # vexos.server.papermc.enable = false;
  # vexos.server.papermc.memory = "2G";

  # ── Cloud & Files ────────────────────────────────────────────────────────
  # vexos.server.nextcloud.enable = false;
  # vexos.server.syncthing.enable = false;
  # vexos.server.immich.enable = false;

  # ── Development ──────────────────────────────────────────────────────────
  # vexos.server.forgejo.enable = false;

  # ── Security ─────────────────────────────────────────────────────────────
  # vexos.server.vaultwarden.enable = false;

  # ── Networking & Reverse Proxies ─────────────────────────────────────────
  # vexos.server.nginx.enable = false;                  # Ports 80/443 (pick one reverse proxy)
  # vexos.server.caddy.enable = false;                  # Ports 80/443 (pick one reverse proxy)
  # vexos.server.traefik.enable = false;                # Ports 80/443 + 8080 dashboard (pick one)
  # vexos.server.adguard.enable = false;
  # vexos.server.headscale.enable = false;              # Port 8085 — Tailscale control server

  # ── Monitoring & Management ──────────────────────────────────────────────
  # vexos.server.cockpit.enable = false;                # Port 9090
  # vexos.server.uptime-kuma.enable = false;
  # vexos.server.homepage.enable = false;
  # vexos.server.grafana.enable = false;                # Port 3000 — metrics dashboards
  # vexos.server.scrutiny.enable = false;               # Port 8080 — disk health (S.M.A.R.T.)

  # ── Notifications ────────────────────────────────────────────────────────
  # vexos.server.ntfy.enable = false;                   # Port 2586 — push notifications

  # ── Food & Home ──────────────────────────────────────────────────────────
  # vexos.server.mealie.enable = false;                 # Port 9000 — recipe manager

  # ── Remote Access ────────────────────────────────────────────────────────
  # vexos.server.rustdesk.enable = false;               # Ports 21115-21117
  # vexos.server.rustdesk.relayIP = "";                 # Set to your server's public IP

  # ── Automation & Smart Home ──────────────────────────────────────────────
  # vexos.server.home-assistant.enable = false;

  # ── PDF Tools ────────────────────────────────────────────────────────────
  # vexos.server.stirling-pdf.enable = false;
  # ── Virtualisation ────────────────────────────────────────────────────────────
  # vexos.server.proxmox.enable = false;              # Web UI https://<ip>:8006 — ⚠ experimental
  # vexos.server.proxmox.ipAddress = "";              # Required: set to this host's IP address}
