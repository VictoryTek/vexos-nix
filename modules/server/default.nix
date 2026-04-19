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
    # ── Media Requests ───────────────────────────────────────────────────────
    ./overseerr.nix
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
    # ── Development ──────────────────────────────────────────────────────────
    ./forgejo.nix
    # ── Security ─────────────────────────────────────────────────────────────
    ./vaultwarden.nix
    # ── Networking & Reverse Proxies ─────────────────────────────────────────
    ./nginx.nix
    ./caddy.nix
    ./traefik.nix
    ./adguard.nix
    ./headscale.nix
    # ── Monitoring & Management ──────────────────────────────────────────────
    ./cockpit.nix
    ./uptime-kuma.nix
    ./homepage.nix
    ./grafana.nix
    ./scrutiny.nix
    # ── Notifications ────────────────────────────────────────────────────────
    ./ntfy.nix
    # ── Food & Home ──────────────────────────────────────────────────────────
    ./mealie.nix
    # ── Remote Access ────────────────────────────────────────────────────────
    ./rustdesk.nix
    # ── Automation & Smart Home ──────────────────────────────────────────────
    ./home-assistant.nix
    # ── PDF Tools ────────────────────────────────────────────────────────────
    ./stirling-pdf.nix
  ];
}
