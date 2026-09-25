# modules/server/default.nix
# Umbrella import for all optional server service modules.
# Each module exposes a vexos.server.<service>.enable option (default: false).
# Services are activated by setting the flag in /etc/nixos/server-services.nix.
{
  imports = [
    # ── Container Runtime ────────────────────────────────────────────────────
    ./docker.nix
    ./podman.nix
    ./dockhand.nix
    ./arcane.nix
    # ── Media Servers ────────────────────────────────────────────────────────
    ./jellyfin.nix
    ./plex.nix
    ./audiobookshelf.nix
    ./tautulli.nix
    # ── Media Requests ───────────────────────────────────────────────────────
    ./seerr.nix
    # ── Media Automation (Arr Stack) ─────────────────────────────────────────
    ./arr.nix
    # ── Books & Comics ───────────────────────────────────────────────────────
    ./grimmory.nix
    ./bookshelf.nix
    # ── Game Servers ─────────────────────────────────────────────────────────
    ./papermc.nix
    # ── Cloud & Files ────────────────────────────────────────────────────────
    ./nextcloud.nix
    ./syncthing.nix
    ./immich.nix
    ./photoprism.nix
    ./joplin.nix
    # ── Documents ────────────────────────────────────────────────────────────
    ./paperless.nix
    # ── Development ──────────────────────────────────────────────────────────
    ./forgejo.nix
    ./code-server.nix
    ./attic.nix
    ./harmonia.nix
    ./kernel-builder.nix
    # ── Dashboards ───────────────────────────────────────────────────────────
    ./vexboard.nix
    # ── AI & Privacy ─────────────────────────────────────────────────────────
    ./kiji-proxy.nix
    ./searxng.nix
    # ── Security ─────────────────────────────────────────────────────────────
    ./vaultwarden.nix
    ./authelia.nix
    # ── Networking & Reverse Proxies ─────────────────────────────────────────
    ./nginx.nix
    ./caddy.nix
    ./proxy.nix
    ./traefik.nix
    ./adguard.nix
    ./headscale.nix
    ./unbound.nix
    ./nginx-proxy-manager.nix
    ./cloudflare-ddns.nix
    # ── Monitoring & Management ──────────────────────────────────────────────
    ./cockpit.nix
    ./nas.nix          # Phase D: NAS stack umbrella (cockpit + plugins) + backend selector
    # ── Storage Tiers (bulk mergerfs+SnapRAID, remote NFS/CIFS) ──────────────
    ./mergerfs.nix        # bulk union pool (mixed-capacity drives)
    ./snapraid.nix        # parity for the mergerfs bulk tier
    ../storage-remote.nix  # attach a pool exported by another host (NFS/CIFS) — universal module
    ./nas-sync.nix         # scheduled rsync mirror jobs between mounted NAS paths
    ./uptime-kuma.nix
    ./homepage.nix
    ./scrutiny.nix
    ./prometheus.nix
    ./alertmanager.nix
    ./fluent-bit.nix
    ./netdata.nix
    ./portainer.nix
    # ── Notifications ────────────────────────────────────────────────────────
    ./ntfy.nix
    # ── Food & Home ──────────────────────────────────────────────────────────
    ./mealie.nix
    ./wishlist.nix
    # ── Inventory ────────────────────────────────────────────────────
    ./humidor.nix
    ./home-registry.nix
    # ── Automation & Smart Home ──────────────────────────────────────────────
    ./zigbee2mqtt.nix
    # ── Virtualisation ────────────────────────────────────────────────────────────
    ./proxmox.nix
    # ── Backup ───────────────────────────────────────────────────────────────
    ./backup.nix
  ];
}
