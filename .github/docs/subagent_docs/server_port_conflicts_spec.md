# Server Port Conflicts — Research & Specification

**Feature:** server_port_conflicts
**Date:** 2025-05-09
**Status:** SPECIFICATION COMPLETE

---

## 1. Current State Analysis

The `modules/server/` directory contains 52 service modules (including `default.nix` umbrella).
All modules are imported unconditionally by `default.nix`, but each service is gated behind a
`vexos.server.<service>.enable` option (default: `false`). Both `configuration-server.nix` and
`configuration-headless-server.nix` import `./modules/server` (the `default.nix` umbrella).

The problem: several services share the same default port numbers. If a user enables all
services simultaneously, bind failures will occur.

---

## 2. Complete Port Inventory

### 2.1 Master Port Table

| Port | Proto | Service | File | Purpose | Configurable | Nix Attribute |
|------|-------|---------|------|---------|--------------|---------------|
| 53 | TCP | AdGuard Home | `modules/server/adguard.nix` | DNS | Hardcoded in settings | `services.adguardhome.settings.dns.port` |
| 53 | UDP | AdGuard Home | `modules/server/adguard.nix` | DNS | Hardcoded in settings | `services.adguardhome.settings.dns.port` |
| 53 | TCP | Unbound | `modules/server/unbound.nix` | DNS resolver | Hardcoded (default) | `services.unbound.settings.server.port` |
| 53 | UDP | Unbound | `modules/server/unbound.nix` | DNS resolver | Hardcoded (default) | `services.unbound.settings.server.port` |
| 80 | TCP | Caddy | `modules/server/caddy.nix` | HTTP reverse proxy | Hardcoded | `services.caddy` (Caddyfile) |
| 80 | TCP | Nginx | `modules/server/nginx.nix` | HTTP web server | Hardcoded | `services.nginx` (default listen) |
| 80 | TCP | Nginx Proxy Manager | `modules/server/nginx-proxy-manager.nix` | HTTP proxy (Docker) | Hardcoded in container ports | OCI container `ports` |
| 80 | TCP | Traefik | `modules/server/traefik.nix` | HTTP entrypoint | Hardcoded in static config | `services.traefik.staticConfigOptions.entryPoints.web.address` |
| 80 | TCP | Nextcloud | `modules/server/nextcloud.nix` | Web UI (via Nginx vhost) | Hardcoded (shares Nginx) | `services.nextcloud` + `services.nginx` |
| 81 | TCP | Nginx Proxy Manager | `modules/server/nginx-proxy-manager.nix` | Admin UI | Configurable (`cfg.adminPort`) | `vexos.server.nginx-proxy-manager.adminPort` |
| 443 | TCP | Caddy | `modules/server/caddy.nix` | HTTPS reverse proxy | Hardcoded | `services.caddy` (Caddyfile) |
| 443 | TCP | Nginx | `modules/server/nginx.nix` | HTTPS web server | Hardcoded | `services.nginx` (default listen) |
| 443 | TCP | Nginx Proxy Manager | `modules/server/nginx-proxy-manager.nix` | HTTPS proxy (Docker) | Hardcoded in container ports | OCI container `ports` |
| 443 | TCP | Traefik | `modules/server/traefik.nix` | HTTPS entrypoint | Hardcoded in static config | `services.traefik.staticConfigOptions.entryPoints.websecure.address` |
| 1880 | TCP | Node-RED | `modules/server/node-red.nix` | Web UI | Hardcoded (`openFirewall`) | `services.node-red` (default) |
| 2283 | TCP | Immich | `modules/server/immich.nix` | Web UI | Configurable (`cfg.port`) | `vexos.server.immich.port` |
| 2342 | TCP | PhotoPrism | `modules/server/photoprism.nix` | Web UI | Configurable (`cfg.port`) | `vexos.server.photoprism.port` |
| 2586 | TCP | ntfy | `modules/server/ntfy.nix` | Push notifications | Hardcoded in settings | `services.ntfy-sh.settings.listen-http` |
| 3000 | TCP | Forgejo | `modules/server/forgejo.nix` | Git forge Web UI | Configurable (`cfg.port`) | `vexos.server.forgejo.port` |
| 3000 | TCP | Grafana | `modules/server/grafana.nix` | Dashboards Web UI | Hardcoded | `services.grafana.settings.server.http_port` |
| 3001 | TCP | Uptime Kuma | `modules/server/uptime-kuma.nix` | Monitoring Web UI | Configurable (`cfg.port`) | `vexos.server.uptime-kuma.port` |
| 3010 | TCP | Homepage | `modules/server/homepage.nix` | Dashboard | Configurable (`cfg.port`) | `vexos.server.homepage.port` |
| 3080 | TCP | AdGuard Home | `modules/server/adguard.nix` | Web UI | Configurable (`cfg.port`) | `vexos.server.adguard.port` |
| 3100 | TCP | Loki | `modules/server/loki.nix` | Log aggregation API | Hardcoded | `services.loki.configuration.server.http_listen_port` |
| 4444 | TCP | code-server | `modules/server/code-server.nix` | VS Code Web UI | Configurable (`cfg.port`) | `vexos.server.code-server.port` |
| 4533 | TCP | Navidrome | `modules/server/navidrome.nix` | Music streaming | Configurable (`cfg.port`) | `vexos.server.navidrome.port` |
| 5000 | TCP | Kavita | `modules/server/kavita.nix` | Ebook library | Hardcoded | `services.kavita.port` |
| 5055 | TCP | Jellyseerr | `modules/server/jellyseerr.nix` | Media requests | Configurable (`cfg.port`) | `vexos.server.jellyseerr.port` |
| 5055 | TCP | Overseerr | `modules/server/overseerr.nix` | Media requests | Configurable (`cfg.port`) | `vexos.server.overseerr.port` |
| 5055 | TCP | Seerr | `modules/server/seerr.nix` | Media requests | Configurable (`cfg.port`) | `vexos.server.seerr.port` |
| 6167 | TCP | Matrix Conduit | `modules/server/matrix-conduit.nix` | Matrix homeserver | Configurable (`cfg.port`) | `vexos.server.matrix-conduit.port` |
| 7878 | TCP | Radarr | `modules/server/arr.nix` | Movie automation | Hardcoded (`openFirewall`) | `services.radarr` (default) |
| 8006 | TCP | Proxmox VE | `modules/server/proxmox.nix` | Web UI / API | Hardcoded | `services.proxmox-ve` |
| 8007 | TCP | Proxmox VE | `modules/server/proxmox.nix` | VNC/SPICE websocket | Hardcoded | `services.proxmox-ve` |
| 8080 | TCP | SABnzbd (arr) | `modules/server/arr.nix` | Usenet downloader | Hardcoded (`openFirewall`) | `services.sabnzbd` (default) |
| 8080 | TCP | Scrutiny | `modules/server/scrutiny.nix` | Disk health Web UI | Hardcoded (`openFirewall`) | `services.scrutiny` (default) |
| 8080 | TCP | Stirling PDF | `modules/server/stirling-pdf.nix` | PDF tools Web UI | Configurable (`cfg.port`) | `vexos.server.stirling-pdf.port` |
| 8080 | TCP | Traefik | `modules/server/traefik.nix` | Dashboard | Hardcoded in static config | `services.traefik.staticConfigOptions.api.insecure` |
| 8085 | TCP | Headscale | `modules/server/headscale.nix` | VPN control HTTP | Configurable (`cfg.port`) | `vexos.server.headscale.port` |
| 8088 | TCP | Zigbee2MQTT | `modules/server/zigbee2mqtt.nix` | Zigbee frontend | Configurable (`cfg.port`) | `vexos.server.zigbee2mqtt.port` |
| 8090 | TCP | Komga | `modules/server/komga.nix` | Comics server | Hardcoded | `services.komga.port` |
| 8096 | TCP | Jellyfin | `modules/server/jellyfin.nix` | Media server Web UI | Hardcoded (`openFirewall`) | `services.jellyfin` (default) |
| 8123 | TCP | Home Assistant | `modules/server/home-assistant.nix` | Automation Web UI | Hardcoded in config | `services.home-assistant.config.http.server_port` |
| 8181 | TCP | Tautulli | `modules/server/tautulli.nix` | Plex analytics | Hardcoded (`openFirewall`) | `services.tautulli` (default) |
| 8222 | TCP | Vaultwarden | `modules/server/vaultwarden.nix` | Password manager | Configurable (`cfg.port`) | `vexos.server.vaultwarden.port` |
| 8234 | TCP | Audiobookshelf | `modules/server/audiobookshelf.nix` | Audiobooks | Configurable (`cfg.port`) | `vexos.server.audiobookshelf.port` |
| 8384 | TCP | Syncthing | `modules/server/syncthing.nix` | File sync Web UI | Hardcoded | `services.syncthing.guiAddress` |
| 8400 | TCP | Attic | `modules/server/attic.nix` | Nix binary cache | Configurable (`cfg.port`) | `vexos.server.attic.port` |
| 8686 | TCP | Lidarr | `modules/server/arr.nix` | Music automation | Hardcoded (`openFirewall`) | `services.lidarr` (default) |
| 8888 | TCP | Dozzle | `modules/server/dozzle.nix` | Docker log viewer | Configurable (`cfg.port`) | `vexos.server.dozzle.port` |
| 8989 | TCP | Sonarr | `modules/server/arr.nix` | TV automation | Hardcoded (`openFirewall`) | `services.sonarr` (default) |
| 9000 | TCP | Mealie | `modules/server/mealie.nix` | Recipe manager | Hardcoded | `services.mealie.port` |
| 9000 | TCP | MinIO | `modules/server/minio.nix` | S3 API | Configurable (`cfg.apiPort`) | `vexos.server.minio.apiPort` |
| 9001 | TCP | MinIO | `modules/server/minio.nix` | Web console | Configurable (`cfg.consolePort`) | `vexos.server.minio.consolePort` |
| 9025 | TCP | Listmonk | `modules/server/listmonk.nix` | Newsletter manager | Configurable (`cfg.port`) | `vexos.server.listmonk.port` |
| 9090 | TCP | Cockpit | `modules/server/cockpit.nix` | Server management | Configurable (`cfg.port`) | `vexos.server.cockpit.port` |
| 9090 | TCP | Prometheus | `modules/server/prometheus.nix` | Metrics Web UI | Configurable (`cfg.port`) | `vexos.server.prometheus.port` |
| 9090 | TCP | Headscale | `modules/server/headscale.nix` | Internal metrics | Hardcoded (`127.0.0.1:9090`) | `services.headscale.settings.metrics_listen_addr` |
| 9091 | TCP | Authelia | `modules/server/authelia.nix` | SSO/2FA portal | Configurable (`cfg.port`) | `vexos.server.authelia.port` |
| 9443 | TCP | Portainer | `modules/server/portainer.nix` | Docker mgmt (HTTPS) | Configurable (`cfg.port`) | `vexos.server.portainer.port` |
| 9696 | TCP | Prowlarr | `modules/server/arr.nix` | Indexer manager | Hardcoded (`openFirewall`) | `services.prowlarr` (default) |
| 19999 | TCP | Netdata | `modules/server/netdata.nix` | System monitoring | Hardcoded | `services.netdata` (default) |
| 21115 | TCP | RustDesk | `modules/server/rustdesk.nix` | Signal server | Hardcoded (`openFirewall`) | `services.rustdesk-server` |
| 21116 | TCP+UDP | RustDesk | `modules/server/rustdesk.nix` | Relay | Hardcoded (`openFirewall`) | `services.rustdesk-server` |
| 21117 | TCP | RustDesk | `modules/server/rustdesk.nix` | Relay | Hardcoded (`openFirewall`) | `services.rustdesk-server` |
| 21118 | TCP | RustDesk | `modules/server/rustdesk.nix` | WebSocket | Hardcoded (`openFirewall`) | `services.rustdesk-server` |
| 21119 | TCP | RustDesk | `modules/server/rustdesk.nix` | WebSocket | Hardcoded (`openFirewall`) | `services.rustdesk-server` |
| 22000 | TCP+UDP | Syncthing | `modules/server/syncthing.nix` | File sync protocol | Hardcoded (`openDefaultPorts`) | `services.syncthing.openDefaultPorts` |
| 21027 | UDP | Syncthing | `modules/server/syncthing.nix` | Discovery | Hardcoded (`openDefaultPorts`) | `services.syncthing.openDefaultPorts` |
| 25565 | TCP | PaperMC | `modules/server/papermc.nix` | Minecraft server | Hardcoded (`openFirewall`) | `services.minecraft-server` (default) |
| 28981 | TCP | Paperless | `modules/server/paperless.nix` | Document mgmt | Configurable (`cfg.port`) | `vexos.server.paperless.port` |
| 32400 | TCP | Plex | `modules/server/plex.nix` | Media server Web UI | Hardcoded (`openFirewall`) | `services.plex` (default) |

### 2.2 Services With No Network Ports

| Service | File | Notes |
|---------|------|-------|
| Docker | `modules/server/docker.nix` | Container runtime only; no listen ports |

---

## 3. Conflicts Identified

### Conflict Group 1 — Port 53 (TCP+UDP): DNS

| Service | File | Bind Address |
|---------|------|-------------|
| AdGuard Home | `modules/server/adguard.nix` | `0.0.0.0:53` |
| Unbound | `modules/server/unbound.nix` | `0.0.0.0:53` / `:::53` |

**Nature:** Both are DNS resolvers/filters. Binding two services to the same DNS port is a hard conflict.

### Conflict Group 2 — Port 80 (TCP): HTTP

| Service | File | Bind Address |
|---------|------|-------------|
| Caddy | `modules/server/caddy.nix` | `0.0.0.0:80` |
| Nginx | `modules/server/nginx.nix` | `0.0.0.0:80` (default) |
| Nginx Proxy Manager | `modules/server/nginx-proxy-manager.nix` | `0.0.0.0:80` (Docker `80:80`) |
| Traefik | `modules/server/traefik.nix` | `:80` (entryPoint web) |
| Nextcloud | `modules/server/nextcloud.nix` | `0.0.0.0:80` (via shared Nginx) |

**Note:** Nextcloud uses the NixOS `services.nginx` module internally. If `modules/server/nginx.nix` is also enabled, they share the same nginx process and port 80 is bound only once — these two are NOT in conflict with each other. However, Caddy, Traefik, and NPM are separate processes and DO conflict with Nginx/Nextcloud and each other.

**Effective conflicts (separate processes):**
- Nginx/Nextcloud (one nginx process) vs Caddy vs NPM vs Traefik

### Conflict Group 3 — Port 443 (TCP): HTTPS

| Service | File | Bind Address |
|---------|------|-------------|
| Caddy | `modules/server/caddy.nix` | `0.0.0.0:443` |
| Nginx | `modules/server/nginx.nix` | `0.0.0.0:443` (default) |
| Nginx Proxy Manager | `modules/server/nginx-proxy-manager.nix` | `0.0.0.0:443` (Docker `443:443`) |
| Traefik | `modules/server/traefik.nix` | `:443` (entryPoint websecure) |

**Same note as Group 2:** Nginx and Nextcloud share a process. Caddy, NPM, Traefik are separate.

### Conflict Group 4 — Port 3000 (TCP): Web UI

| Service | File | Configurable? |
|---------|------|--------------|
| Forgejo | `modules/server/forgejo.nix` | Yes (`cfg.port`, default 3000) |
| Grafana | `modules/server/grafana.nix` | No (hardcoded `http_port = 3000`) |

### Conflict Group 5 — Port 5055 (TCP): Media Requests

| Service | File | Configurable? |
|---------|------|--------------|
| Seerr | `modules/server/seerr.nix` | Yes (`cfg.port`, default 5055) |
| Jellyseerr | `modules/server/jellyseerr.nix` | Yes (`cfg.port`, default 5055) |
| Overseerr | `modules/server/overseerr.nix` | Yes (`cfg.port`, default 5055) |

**Note:** All three are media request managers (Seerr is the successor). Comments in the code already warn about this conflict.

### Conflict Group 6 — Port 8080 (TCP): Web UI / Dashboard

| Service | File | Configurable? |
|---------|------|--------------|
| SABnzbd (arr) | `modules/server/arr.nix` | No (hardcoded default via `openFirewall`) |
| Scrutiny | `modules/server/scrutiny.nix` | No (hardcoded default via `openFirewall`) |
| Stirling PDF | `modules/server/stirling-pdf.nix` | Yes (`cfg.port`, default 8080) |
| Traefik dashboard | `modules/server/traefik.nix` | No (hardcoded `api.insecure = true` on 8080) |

### Conflict Group 7 — Port 9000 (TCP): API / Web UI

| Service | File | Configurable? |
|---------|------|--------------|
| Mealie | `modules/server/mealie.nix` | No (hardcoded `port = 9000`) |
| MinIO (S3 API) | `modules/server/minio.nix` | Yes (`cfg.apiPort`, default 9000) |

### Conflict Group 8 — Port 9090 (TCP): Web UI / Metrics

| Service | File | Configurable? | Bind Address |
|---------|------|--------------|-------------|
| Cockpit | `modules/server/cockpit.nix` | Yes (`cfg.port`, default 9090) | `0.0.0.0:9090` |
| Prometheus | `modules/server/prometheus.nix` | Yes (`cfg.port`, default 9090) | `0.0.0.0:9090` |
| Headscale (metrics) | `modules/server/headscale.nix` | No (hardcoded) | `127.0.0.1:9090` |

**Note:** Even though Headscale binds to localhost only, if Cockpit or Prometheus binds to `0.0.0.0:9090`, the localhost address is included and the bind will fail.

---

## 4. Proposed Resolutions

### 4.1 Resolution Summary

| Conflict Group | Service to Change | Old Port | New Port | Rationale |
|---------------|-------------------|----------|----------|-----------|
| 1 (DNS 53) | Unbound | 53 | 5353 | mDNS-standard alt port; AdGuard keeps 53 as primary DNS filter |
| 2 (HTTP 80) | Caddy | 80 | 8880 | Nginx/Nextcloud keep 80 (Nextcloud requires Nginx) |
| 2 (HTTP 80) | NPM (HTTP) | 80 | 8881 | Unique HTTP alt port |
| 2 (HTTP 80) | Traefik (web) | 80 | 8882 | Unique HTTP alt port |
| 3 (HTTPS 443) | Caddy | 443 | 8443 | Standard HTTPS-alt port |
| 3 (HTTPS 443) | NPM (HTTPS) | 443 | 8444 | Unique HTTPS alt port |
| 3 (HTTPS 443) | Traefik (websecure) | 443 | 8445 | Unique HTTPS alt port |
| 4 (3000) | Grafana | 3000 | 3030 | Forgejo keeps 3000 (standard Git forge port) |
| 5 (5055) | Jellyseerr | 5055 | 5056 | Seerr keeps 5055 (successor project) |
| 5 (5055) | Overseerr | 5055 | 5057 | Unique alt port |
| 6 (8080) | Scrutiny | 8080 | 8078 | SABnzbd keeps 8080 (no Nix port option) |
| 6 (8080) | Stirling PDF | 8080 | 8077 | Already configurable |
| 6 (8080) | Traefik dashboard | 8080 | 8079 | New dashboard port |
| 7 (9000) | Mealie | 9000 | 9010 | MinIO keeps 9000 (S3 standard) |
| 8 (9090) | Prometheus | 9090 | 9092 | Cockpit keeps 9090 (widely known) |
| 8 (9090) | Headscale metrics | 9090 | 9093 | Prometheus alertmanager-range port |

### 4.2 Verified Port Uniqueness

All proposed new ports have been checked against the full inventory above. None collide with any existing service port.

---

## 5. Implementation Steps

### 5.1 `modules/server/unbound.nix` — Change DNS port from 53 → 5353

**Old value:**
```nix
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [ "0.0.0.0" "::" ];
```
No explicit port is set (defaults to 53).

**New value — add `port` to server settings:**
```nix
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [ "0.0.0.0" "::" ];
          port = 5353;
```

**Firewall — old:**
```nix
    networking.firewall.allowedTCPPorts = [ 53 ];
    networking.firewall.allowedUDPPorts = [ 53 ];
```

**Firewall — new:**
```nix
    networking.firewall.allowedTCPPorts = [ 5353 ];
    networking.firewall.allowedUDPPorts = [ 5353 ];
```

---

### 5.2 `modules/server/caddy.nix` — Change HTTP/HTTPS from 80/443 → 8880/8443

**Old:**
```nix
    networking.firewall.allowedTCPPorts = [ 80 443 ];
```

**New — add `httpPort`/`httpsPort` config and update Caddy settings:**
```nix
  options.vexos.server.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8880;
      description = "Port for Caddy HTTP listener.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = "Port for Caddy HTTPS listener.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      globalConfig = ''
        http_port  ${toString cfg.httpPort}
        https_port ${toString cfg.httpsPort}
      '';
    };

    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort ];
  };
```

---

### 5.3 `modules/server/nginx.nix` — Change HTTP/HTTPS from 80/443 → 8880/8443

Since Nginx and Nextcloud share the same `services.nginx` process, and Nextcloud's vhost must remain accessible, the standalone nginx module should use non-conflicting alternate ports when other proxies are present.

**Old:**
```nix
    networking.firewall.allowedTCPPorts = [ 80 443 ];
```

**New — add `httpPort`/`httpsPort` options:**
```nix
  options.vexos.server.nginx = {
    enable = lib.mkEnableOption "Nginx web server";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "Default HTTP listen port for Nginx virtual hosts.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Default HTTPS listen port for Nginx virtual hosts.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;
      defaultHTTPListenPort  = cfg.httpPort;
      defaultSSLListenPort   = cfg.httpsPort;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
    };

    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort ];
  };
```

**Note:** `services.nginx.defaultHTTPListenPort` and `services.nginx.defaultSSLListenPort` are available in NixOS 25.05+.

---

### 5.4 `modules/server/nginx-proxy-manager.nix` — Change HTTP/HTTPS from 80/443 → 8881/8444

**Old:**
```nix
      ports = [
        "80:80"
        "443:443"
        "${toString cfg.adminPort}:81"
      ];
```

**New — add `httpPort`/`httpsPort` options:**
```nix
  options.vexos.server.nginx-proxy-manager = {
    enable = lib.mkEnableOption "Nginx Proxy Manager reverse proxy UI";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8881;
      description = "Host port for HTTP proxy traffic.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 8444;
      description = "Host port for HTTPS proxy traffic.";
    };

    adminPort = lib.mkOption {
      type = lib.types.port;
      default = 81;
      description = "Port for the Nginx Proxy Manager admin interface.";
    };
  };
```

Container ports:
```nix
      ports = [
        "${toString cfg.httpPort}:80"
        "${toString cfg.httpsPort}:443"
        "${toString cfg.adminPort}:81"
      ];
```

Firewall:
```nix
    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort cfg.adminPort ];
```

---

### 5.5 `modules/server/traefik.nix` — Change web 80→8882, websecure 443→8445, dashboard 8080→8079

**Old:**
```nix
        entryPoints = {
          web.address = ":80";
          websecure.address = ":443";
        };
...
    networking.firewall.allowedTCPPorts = [ 80 443 8080 ];
```

**New — add port options:**
```nix
  options.vexos.server.traefik = {
    enable = lib.mkEnableOption "Traefik reverse proxy";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8882;
      description = "Port for the Traefik HTTP entrypoint.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 8445;
      description = "Port for the Traefik HTTPS entrypoint.";
    };

    dashboardPort = lib.mkOption {
      type = lib.types.port;
      default = 8079;
      description = "Port for the Traefik dashboard (insecure API).";
    };
  };
```

Static config:
```nix
        entryPoints = {
          web.address = ":${toString cfg.httpPort}";
          websecure.address = ":${toString cfg.httpsPort}";
          dashboard.address = ":${toString cfg.dashboardPort}";
        };
        api = {
          dashboard = true;
          insecure = true;
        };
```

Firewall:
```nix
    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort cfg.dashboardPort ];
```

---

### 5.6 `modules/server/grafana.nix` — Change port from 3000 → 3030

**Old:**
```nix
      settings.server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
        domain = "localhost";
      };
    };

    networking.firewall.allowedTCPPorts = [ 3000 ];
```

**New — add configurable port option:**
```nix
  options.vexos.server.grafana = {
    enable = lib.mkEnableOption "Grafana observability dashboards";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3030;
      description = "Port for the Grafana web UI.";
    };
  };
```

Config:
```nix
      settings.server = {
        http_addr = "0.0.0.0";
        http_port = cfg.port;
        domain = "localhost";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
```

---

### 5.7 `modules/server/jellyseerr.nix` — Change default from 5055 → 5056

**Old:**
```nix
      default = 5055;
```

**New:**
```nix
      default = 5056;
```

---

### 5.8 `modules/server/overseerr.nix` — Change default from 5055 → 5057

**Old:**
```nix
      default = 5055;
```

**New:**
```nix
      default = 5057;
```

---

### 5.9 `modules/server/scrutiny.nix` — Add port option, change from 8080 → 8078

**Old:**
```nix
  options.vexos.server.scrutiny = {
    enable = lib.mkEnableOption "Scrutiny disk health monitoring";
  };

  config = lib.mkIf cfg.enable {
    services.scrutiny = {
      enable = true;
      openFirewall = true; # Default port: 8080
      collector.enable = true;
    };
  };
```

**New:**
```nix
  options.vexos.server.scrutiny = {
    enable = lib.mkEnableOption "Scrutiny disk health monitoring";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8078;
      description = "Port for the Scrutiny web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.scrutiny = {
      enable = true;
      openFirewall = true;
      settings.web.listen.port = cfg.port;
      collector.enable = true;
    };
  };
```

---

### 5.10 `modules/server/stirling-pdf.nix` — Change default from 8080 → 8077

**Old:**
```nix
      default = 8080;
```

**New:**
```nix
      default = 8077;
```

---

### 5.11 `modules/server/mealie.nix` — Change port from 9000 → 9010

**Old:**
```nix
    services.mealie = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 9000; # Default port: 9000
    };

    networking.firewall.allowedTCPPorts = [ 9000 ];
```

**New — add configurable port option:**
```nix
  options.vexos.server.mealie = {
    enable = lib.mkEnableOption "Mealie recipe manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9010;
      description = "Port for the Mealie web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.mealie = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = cfg.port;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
```

---

### 5.12 `modules/server/prometheus.nix` — Change default from 9090 → 9092

**Old:**
```nix
      default = 9090;
      description = "Port for the Prometheus web UI and API. ⚠ Conflicts with Cockpit on port 9090.";
```

**New:**
```nix
      default = 9092;
      description = "Port for the Prometheus web UI and API.";
```

---

### 5.13 `modules/server/headscale.nix` — Change metrics from 9090 → 9093

**Old:**
```nix
      settings = {
        metrics_listen_addr = "127.0.0.1:9090";
```

**New:**
```nix
      settings = {
        metrics_listen_addr = "127.0.0.1:9093";
```

---

### 5.14 `modules/server/nextcloud.nix` — Update firewall comment (no port change needed)

Nextcloud shares the Nginx process with `modules/server/nginx.nix`. Both modules configure
`services.nginx`, which is a single process. The firewall rule in `nextcloud.nix` opens port 80
because the Nginx vhost listens on the default HTTP port. Since Nginx keeps port 80, no change
is needed in `nextcloud.nix` for port conflicts. However, the Nginx and Nextcloud modules will
share the same port.

**No code change required for nextcloud.nix.**

---

## 6. Justfile Updates Required

After changing ports, the `service-info` and `status` recipes in the justfile must be updated
to reflect new port numbers. The affected entries:

| Service | Old Port in justfile | New Port |
|---------|---------------------|----------|
| caddy | `:80, :443` | `:8880, :8443` |
| grafana | `:3000` | `:3030` |
| jellyseerr | `:5055` | `:5056` |
| mealie | `:9000` | `:9010` |
| nginx-proxy-manager | `:80, :443` (plus `:81`) | `:8881, :8444` (plus `:81`) |
| overseerr | `:5055` | `:5057` |
| prometheus | `:9090` | `:9092` |
| scrutiny | `:8080` | `:8078` |
| stirling-pdf | `:8080` | `:8077` |
| traefik | `:80, :443, :8080` | `:8882, :8445, :8079` |

---

## 7. Files Requiring Modification

1. `modules/server/unbound.nix` — DNS port 53 → 5353
2. `modules/server/caddy.nix` — HTTP/HTTPS 80/443 → 8880/8443 + add port options
3. `modules/server/nginx.nix` — Add `httpPort`/`httpsPort` options (defaults remain 80/443)
4. `modules/server/nginx-proxy-manager.nix` — HTTP/HTTPS 80/443 → 8881/8444 + add port options
5. `modules/server/traefik.nix` — web/websecure/dashboard 80/443/8080 → 8882/8445/8079 + add port options
6. `modules/server/grafana.nix` — Port 3000 → 3030 + add port option
7. `modules/server/jellyseerr.nix` — Default port 5055 → 5056
8. `modules/server/overseerr.nix` — Default port 5055 → 5057
9. `modules/server/scrutiny.nix` — Port 8080 → 8078 + add port option
10. `modules/server/stirling-pdf.nix` — Default port 8080 → 8077
11. `modules/server/mealie.nix` — Port 9000 → 9010 + add port option
12. `modules/server/prometheus.nix` — Default port 9090 → 9092
13. `modules/server/headscale.nix` — Metrics 9090 → 9093
14. `justfile` — Update `service-info` and `status` port references

---

## 8. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Existing users have bookmarks/configs pointing to old ports | Document changes in commit message; old ports remain as option overrides |
| Upstream NixOS module may not support `settings.web.listen.port` for Scrutiny | Verify against nixpkgs 25.05 NixOS module source; fall back to `extraArgs` if needed |
| Changing Unbound from port 53 means clients must be reconfigured | Document that standard DNS clients expect port 53; this is by design for coexistence with AdGuard |
| Reverse proxies on non-standard ports require client-side port in URL | Expected; users running all proxies simultaneously can pick one as the front door on 80/443 via option override |
| `services.nginx.defaultHTTPListenPort` availability | Requires NixOS 25.05+; project already targets 25.05 |

---

## 9. Post-Change Port Map (All Unique)

| Port | Service | Purpose |
|------|---------|---------|
| 53 | AdGuard Home | DNS |
| 80 | Nginx / Nextcloud | HTTP (shared process) |
| 81 | Nginx Proxy Manager | Admin UI |
| 443 | Nginx / Nextcloud | HTTPS (shared process) |
| 1880 | Node-RED | Web UI |
| 2283 | Immich | Web UI |
| 2342 | PhotoPrism | Web UI |
| 2586 | ntfy | Push notifications |
| 3000 | Forgejo | Git forge |
| 3001 | Uptime Kuma | Monitoring |
| 3010 | Homepage | Dashboard |
| 3030 | Grafana | Dashboards |
| 3080 | AdGuard Home | Web UI |
| 3100 | Loki | Log API |
| 4444 | code-server | VS Code Web |
| 4533 | Navidrome | Music streaming |
| 5000 | Kavita | Ebook library |
| 5055 | Seerr | Media requests |
| 5056 | Jellyseerr | Media requests |
| 5057 | Overseerr | Media requests |
| 5353 | Unbound | DNS resolver |
| 6167 | Matrix Conduit | Matrix homeserver |
| 7878 | Radarr | Movie automation |
| 8006 | Proxmox VE | Web UI |
| 8007 | Proxmox VE | VNC/SPICE |
| 8077 | Stirling PDF | PDF tools |
| 8078 | Scrutiny | Disk health |
| 8079 | Traefik | Dashboard |
| 8080 | SABnzbd | Usenet downloader |
| 8085 | Headscale | VPN control |
| 8088 | Zigbee2MQTT | Zigbee frontend |
| 8090 | Komga | Comics server |
| 8096 | Jellyfin | Media server |
| 8123 | Home Assistant | Automation |
| 8181 | Tautulli | Plex analytics |
| 8222 | Vaultwarden | Password manager |
| 8234 | Audiobookshelf | Audiobooks |
| 8384 | Syncthing | File sync UI |
| 8400 | Attic | Nix cache |
| 8443 | Caddy | HTTPS |
| 8444 | Nginx Proxy Manager | HTTPS proxy |
| 8445 | Traefik | HTTPS entrypoint |
| 8686 | Lidarr | Music automation |
| 8880 | Caddy | HTTP |
| 8881 | Nginx Proxy Manager | HTTP proxy |
| 8882 | Traefik | HTTP entrypoint |
| 8888 | Dozzle | Docker logs |
| 8989 | Sonarr | TV automation |
| 9000 | MinIO | S3 API |
| 9001 | MinIO | Web console |
| 9010 | Mealie | Recipe manager |
| 9025 | Listmonk | Newsletter |
| 9090 | Cockpit | Server management |
| 9091 | Authelia | SSO/2FA |
| 9092 | Prometheus | Metrics |
| 9093 | Headscale | Internal metrics |
| 9443 | Portainer | Docker mgmt |
| 9696 | Prowlarr | Indexer manager |
| 19999 | Netdata | System monitoring |
| 21027 | Syncthing | Discovery (UDP) |
| 21115 | RustDesk | Signal |
| 21116 | RustDesk | Relay |
| 21117 | RustDesk | Relay |
| 21118 | RustDesk | WebSocket |
| 21119 | RustDesk | WebSocket |
| 22000 | Syncthing | Sync protocol |
| 25565 | PaperMC | Minecraft |
| 28981 | Paperless | Document mgmt |
| 32400 | Plex | Media server |

**Zero conflicts remaining.**
