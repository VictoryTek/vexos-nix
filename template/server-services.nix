# /etc/nixos/server-services.nix
# Local feature toggles for the VexOS server role.
# Managed by `just enable <service>` / `just disable <service>`.
# After editing, run `just rebuild` or `just switch server <gpu>` to apply.
#
# Available services:
#   docker, jellyfin, plex, papermc, immich, vaultwarden, nextcloud,
#   forgejo, syncthing, cockpit, uptime-kuma, stirling-pdf,
#   audiobookshelf, homepage, caddy, arr, adguard, home-assistant
{
  # ── Container Runtime ────────────────────────────────────────────────────
  # vexos.server.docker.enable = false;

  # ── Media Servers ────────────────────────────────────────────────────────
  # vexos.server.jellyfin.enable = false;
  # vexos.server.plex.enable = false;
  # vexos.server.audiobookshelf.enable = false;

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

  # ── Networking & DNS ─────────────────────────────────────────────────────
  # vexos.server.caddy.enable = false;
  # vexos.server.adguard.enable = false;

  # ── Monitoring & Management ──────────────────────────────────────────────
  # vexos.server.cockpit.enable = false;
  # vexos.server.uptime-kuma.enable = false;
  # vexos.server.homepage.enable = false;

  # ── Automation & Media ───────────────────────────────────────────────────
  # vexos.server.arr.enable = false;
  # vexos.server.home-assistant.enable = false;

  # ── PDF Tools ────────────────────────────────────────────────────────────
  # vexos.server.stirling-pdf.enable = false;
}
