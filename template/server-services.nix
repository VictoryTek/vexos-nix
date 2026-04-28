# /etc/nixos/server-services.nix
# Local feature toggles for the VexOS server role.
# Managed by `just enable <service>` / `just disable <service>`.
# After editing, run `just rebuild` or `just switch server <gpu>` to apply.
#
# Available services:
#   docker, jellyfin, plex, audiobookshelf, tautulli, navidrome,
#   overseerr, jellyseerr,
#   arr (SABnzbd + Sonarr + Radarr + Lidarr + Prowlarr),
#   komga, kavita, papermc, nextcloud, syncthing, immich, minio, photoprism,
#   paperless, forgejo, code-server, vaultwarden, authelia,
#   nginx, caddy, traefik, adguard, headscale, unbound, nginx-proxy-manager,
#   cockpit, uptime-kuma, homepage, grafana, scrutiny, prometheus, loki, netdata,
#   dozzle, portainer, ntfy, mealie, listmonk, rustdesk, home-assistant,
#   node-red, zigbee2mqtt, matrix-conduit, stirling-pdf, proxmox
{
  # ── Container Runtime ────────────────────────────────────────────────────
  # vexos.server.docker.enable = false;

  # ── Media Servers ────────────────────────────────────────────────────────
  # vexos.server.jellyfin.enable = false;
  # vexos.server.plex.enable = false;
  # vexos.server.plex.plexPass = false;                 # true = expose GPU for hardware transcoding (requires Plex Pass sub)
  # vexos.server.audiobookshelf.enable = false;         # Port 3000
  # vexos.server.tautulli.enable = false;               # Port 8181 — Plex analytics
  # vexos.server.navidrome.enable = false;               # Port 4533 — music streaming

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
  # vexos.server.minio.enable = false;                   # Port 9000 API + 9001 console (⚠ conflicts with mealie)
  # vexos.server.minio.apiPort = 9000;                   # Change if mealie is also enabled
  # vexos.server.photoprism.enable = false;              # Port 2342 — photo management

  # ── Documents ─────────────────────────────────────────────────────────────
  # vexos.server.paperless.enable = false;               # Port 28981 — document management with OCR

  # ── Development ──────────────────────────────────────────────────────────
  # vexos.server.forgejo.enable = false;
  # vexos.server.code-server.enable = false;             # Port 4444 — VS Code in the browser
  # vexos.server.code-server.hashedPasswordFile = null;  # Set to /etc/nixos/secrets/code-server-password (bcrypt)

  # ── Security ─────────────────────────────────────────────────────────────
  # vexos.server.vaultwarden.enable = false;
  # vexos.server.authelia.enable = false;                # Port 9091 — SSO/2FA proxy (requires /etc/nixos/authelia/configuration.yml)

  # ── Networking & Reverse Proxies ─────────────────────────────────────────
  # vexos.server.nginx.enable = false;                  # Ports 80/443 (pick one reverse proxy)
  # vexos.server.caddy.enable = false;                  # Ports 80/443 (pick one reverse proxy)
  # vexos.server.traefik.enable = false;                # Ports 80/443 + 8080 dashboard (pick one)
  # vexos.server.adguard.enable = false;
  # vexos.server.headscale.enable = false;              # Port 8085 — Tailscale control server
  # vexos.server.unbound.enable = false;                 #           ⚠ conflicts with adguard on port 53
  # vexos.server.nginx-proxy-manager.enable = false;     # Port 81 admin + 80/443 ⚠ conflicts with nginx/caddy/traefik

  # ── Monitoring & Management ──────────────────────────────────────────────
  # vexos.server.cockpit.enable = false;                # Port 9090
  # vexos.server.uptime-kuma.enable = false;
  # vexos.server.homepage.enable = false;
  # vexos.server.grafana.enable = false;                # Port 3000 — metrics dashboards
  # vexos.server.scrutiny.enable = false;               # Port 8080 — disk health (S.M.A.R.T.)
  # vexos.server.prometheus.enable = false;              # Port 9090 (⚠ conflicts with cockpit)
  # vexos.server.loki.enable = false;                    # Port 3100 — log aggregation (pair with grafana)
  # vexos.server.netdata.enable = false;                 # Port 19999 — real-time system monitoring
  # vexos.server.dozzle.enable = false;                  # Port 8888 — Docker log viewer (requires docker)
  # vexos.server.portainer.enable = false;               # Port 9443 — Docker management UI (requires docker)

  # ── Notifications ────────────────────────────────────────────────────────
  # vexos.server.ntfy.enable = false;                   # Port 2586 — push notifications

  # ── Food & Home ──────────────────────────────────────────────────────────
  # vexos.server.mealie.enable = false;                 # Port 9000 — recipe manager
  # vexos.server.listmonk.enable = false;                # Port 9025 — newsletter/mailing list manager

  # ── Remote Access ────────────────────────────────────────────────────────
  # vexos.server.rustdesk.enable = false;               # Ports 21115-21117
  # vexos.server.rustdesk.relayIP = "";                 # Set to your server's public IP

  # ── Automation & Smart Home ──────────────────────────────────────────────
  # vexos.server.home-assistant.enable = false;
  # vexos.server.node-red.enable = false;                # Port 1880 — flow-based automation
  # vexos.server.zigbee2mqtt.enable = false;             # Port 8088 — Zigbee bridge
  # vexos.server.zigbee2mqtt.serialPort = "/dev/ttyUSB0"; # Set to your Zigbee coordinator device

  # ── Communications ────────────────────────────────────────────────────────
  # vexos.server.matrix-conduit.enable = false;          # Port 6167 — Matrix homeserver
  # vexos.server.matrix-conduit.serverName = "localhost"; # Set to your domain for federation

  # ── PDF Tools ────────────────────────────────────────────────────────────
  # vexos.server.stirling-pdf.enable = false;

  # ── Virtualisation ────────────────────────────────────────────────────────────
  # vexos.server.proxmox.enable = false;              # Web UI https://<ip>:8006 — ⚠ experimental
  # vexos.server.proxmox.ipAddress = "";              # Required: set to this host's IP address
}
