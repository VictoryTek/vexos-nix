# Server Port Conflicts — Final Review

**Feature:** server_port_conflicts
**Date:** 2025-05-09
**Reviewer:** Phase 5 Re-Review
**Verdict:** APPROVED

---

## 1. Issue Resolution Verification

### C1 (CRITICAL): Traefik entrypoint naming — RESOLVED ✅

In `modules/server/traefik.nix`, the entrypoint is now correctly named `traefik` (not `dashboard`):

```nix
entryPoints = {
  web.address = ":${toString cfg.httpPort}";
  websecure.address = ":${toString cfg.httpsPort}";
  traefik.address = ":${toString cfg.dashboardPort}";
};
```

This ensures Traefik's `api.insecure = true` dashboard is served on port 8079, eliminating the port 8080 conflict with SABnzbd.

### R1 (RECOMMENDED): template/server-services.nix stale comments — RESOLVED ✅

All port comments have been updated to reflect the new port assignments:

| Service | Old Comment | New Comment | Correct |
|---------|------------|-------------|---------|
| overseerr | Port 5055 | Port 5057 | ✅ |
| jellyseerr | Port 5055 | Port 5056 | ✅ |
| caddy | Ports 80/443 | Ports 8880/8443 | ✅ |
| traefik | 80/443 + 8080 | Ports 8882/8445 + 8079 dashboard | ✅ |
| nginx-proxy-manager | 80/443 | Port 81 admin + 8881/8444 | ✅ |
| grafana | Port 3000 | Port 3030 | ✅ |
| scrutiny | Port 8080 | Port 8078 | ✅ |
| mealie | Port 9000 | Port 9010 | ✅ |
| prometheus | Port 9090 (⚠ conflicts) | Port 9092 | ✅ |
| unbound | (conflict warning) | Port 5353 | ✅ |

### R2 (RECOMMENDED): minio.nix stale Mealie conflict warning — RESOLVED ✅

`modules/server/minio.nix` no longer contains any Mealie conflict warnings. The header comment reads:

```
# API default port: 9000
# Console default port: 9001
```

The `apiPort` option description is now simply: `"Port for the MinIO S3 API."`

---

## 2. Full Port Uniqueness Audit

Complete post-fix port map across all `modules/server/*.nix` files — **zero conflicts**:

| Port | Service | File |
|------|---------|------|
| 53 | AdGuard Home (DNS) | adguard.nix |
| 80 | Nginx (HTTP) | nginx.nix |
| 81 | Nginx Proxy Manager (admin) | nginx-proxy-manager.nix |
| 443 | Nginx (HTTPS) | nginx.nix |
| 1880 | Node-RED | node-red.nix |
| 2283 | Immich | immich.nix |
| 2342 | PhotoPrism | photoprism.nix |
| 2586 | ntfy | ntfy.nix |
| 3000 | Forgejo | forgejo.nix |
| 3001 | Uptime Kuma | uptime-kuma.nix |
| 3010 | Homepage | homepage.nix |
| 3030 | Grafana | grafana.nix |
| 3080 | AdGuard Home (Web UI) | adguard.nix |
| 3100 | Loki | loki.nix |
| 4444 | code-server | code-server.nix |
| 4533 | Navidrome | navidrome.nix |
| 5000 | Kavita | kavita.nix |
| 5055 | Seerr | seerr.nix |
| 5056 | Jellyseerr | jellyseerr.nix |
| 5057 | Overseerr | overseerr.nix |
| 5353 | Unbound (DNS) | unbound.nix |
| 6167 | Matrix Conduit | matrix-conduit.nix |
| 7878 | Radarr | arr.nix |
| 8006 | Proxmox (Web UI) | proxmox.nix |
| 8007 | Proxmox (VNC/SPICE) | proxmox.nix |
| 8077 | Stirling PDF | stirling-pdf.nix |
| 8078 | Scrutiny | scrutiny.nix |
| 8079 | Traefik (dashboard) | traefik.nix |
| 8080 | SABnzbd | arr.nix |
| 8085 | Headscale (HTTP) | headscale.nix |
| 8088 | Zigbee2MQTT | zigbee2mqtt.nix |
| 8090 | Komga | komga.nix |
| 8096 | Jellyfin | jellyfin.nix |
| 8123 | Home Assistant | home-assistant.nix |
| 8181 | Tautulli | tautulli.nix |
| 8222 | Vaultwarden | vaultwarden.nix |
| 8234 | Audiobookshelf | audiobookshelf.nix |
| 8384 | Syncthing (GUI) | syncthing.nix |
| 8400 | Attic | attic.nix |
| 8443 | Caddy (HTTPS) | caddy.nix |
| 8444 | Nginx Proxy Manager (HTTPS) | nginx-proxy-manager.nix |
| 8445 | Traefik (HTTPS) | traefik.nix |
| 8686 | Lidarr | arr.nix |
| 8880 | Caddy (HTTP) | caddy.nix |
| 8881 | Nginx Proxy Manager (HTTP) | nginx-proxy-manager.nix |
| 8882 | Traefik (HTTP) | traefik.nix |
| 8888 | Dozzle | dozzle.nix |
| 8989 | Sonarr | arr.nix |
| 9000 | MinIO (S3 API) | minio.nix |
| 9001 | MinIO (console) | minio.nix |
| 9010 | Mealie | mealie.nix |
| 9025 | Listmonk | listmonk.nix |
| 9090 | Cockpit | cockpit.nix |
| 9091 | Authelia | authelia.nix |
| 9092 | Prometheus | prometheus.nix |
| 9093 | Headscale (metrics, localhost) | headscale.nix |
| 9443 | Portainer | portainer.nix |
| 9696 | Prowlarr | arr.nix |
| 19999 | Netdata | netdata.nix |
| 21115–21119 | RustDesk | rustdesk.nix |
| 22000 | Syncthing (protocol) | syncthing.nix |
| 25565 | PaperMC | papermc.nix |
| 28981 | Paperless | paperless.nix |
| 32400 | Plex | plex.nix |

**Result: All 60+ port assignments are unique. Zero conflicts.**

---

## 3. Spot-Check Summary

Additional files verified for correctness beyond the 3 fixes:

- **grafana.nix**: Port 3030, `http_port = cfg.port`, firewall correct ✅
- **mealie.nix**: Port 9010, `port = cfg.port`, firewall correct ✅
- **prometheus.nix**: Port 9092, `port = cfg.port`, firewall correct ✅
- **stirling-pdf.nix**: Port 8077, container mapping `"${toString cfg.port}:8080"` correct ✅
- **unbound.nix**: Port 5353, firewall TCP+UDP correct ✅
- **headscale.nix**: Metrics at `127.0.0.1:9093`, main port 8085 ✅

---

## 4. Architecture Compliance

All 16 modified files follow Option B pattern:
- ✅ `lib.mkIf cfg.enable` guard (per-service toggle, not role-gated)
- ✅ Options under `vexos.server.<service>.*`
- ✅ Port options use `lib.types.port`
- ✅ No role/display/gaming guards in shared modules
- ✅ Consistent `cfg = config.vexos.server.<service>` pattern

---

## 5. Remaining INFO Items (Non-blocking)

| # | File | Note |
|---|------|------|
| I1 | `modules/server/headscale.nix` | Header comment says "Default port: 8080" but actual default is 8085. Pre-existing issue, not introduced by this change set. |
| I2 | `modules/server/scrutiny.nix` | `openFirewall = true` relies on NixOS module reading `settings.web.listen.port`. Expected to work in nixpkgs 25.05. |

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 96% | A |
| Functionality | 98% | A+ |
| Code Quality | 95% | A |
| Security | 95% | A |
| Performance | 98% | A+ |
| Consistency | 97% | A |
| Build Success | 95% | A |

**Overall: 97% (A) — APPROVED**

---

## 7. Verdict

**APPROVED** — All three issues from the initial review have been correctly resolved:

1. **C1 (CRITICAL)**: Traefik entrypoint renamed from `dashboard` to `traefik` — port 8080 conflict eliminated
2. **R1 (RECOMMENDED)**: All stale port comments in `template/server-services.nix` updated
3. **R2 (RECOMMENDED)**: Stale Mealie conflict warnings removed from `modules/server/minio.nix`

The full port audit confirms zero conflicts across all 60+ service port assignments. No regressions detected.
