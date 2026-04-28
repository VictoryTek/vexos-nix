# Server Services Expansion — Implementation Specification

**Feature:** `server_services_expansion`  
**Date:** 2026-04-28  
**Status:** Ready for Implementation  
**Spec file:** `.github/docs/subagent_docs/server_services_expansion_spec.md`

---

## Summary

Add 17 new server service modules to vexos-nix. Three services are explicitly skipped (wireguard, tubearchivist, authentik) with documented reasoning.

### Services Being Added (17)

| # | Service | Type | Port(s) | Category |
|---|---------|------|---------|----------|
| 1 | prometheus | Native NixOS | 9090 (⚠ cockpit) | Monitoring & Admin |
| 2 | loki | Native NixOS | 3100 | Monitoring & Admin |
| 3 | netdata | Native NixOS | 19999 | Monitoring & Admin |
| 4 | unbound | Native NixOS | 53 (⚠ adguard) | Networking & Security |
| 5 | paperless | Native NixOS | 28981 | Productivity |
| 6 | minio | Native NixOS | 9000+9001 (⚠ mealie) | Files & Storage |
| 7 | matrix-conduit | Native NixOS | 6167 | Communications (new) |
| 8 | navidrome | Native NixOS | 4533 | Media |
| 9 | code-server | Native NixOS | 4444 | Productivity |
| 10 | node-red | Native NixOS | 1880 | Smart Home & Notifications |
| 11 | zigbee2mqtt | Native NixOS | 8088 | Smart Home & Notifications |
| 12 | authelia | OCI container | 9091 | Networking & Security |
| 13 | photoprism | Native NixOS | 2342 | Files & Storage |
| 14 | listmonk | Native NixOS | 9025 | Productivity |
| 15 | dozzle | OCI container | 8888 | Monitoring & Admin |
| 16 | portainer | OCI container | 9443 | Infrastructure |
| 17 | nginx-proxy-manager | OCI container | 81+80+443 | Infrastructure |

### Services Skipped (3)

| Service | Reason |
|---------|--------|
| **wireguard** | Requires interface name, private key, IP CIDR, port, and peer list — too many required options to safely wire as a simple enable toggle. Recommend users configure directly via `networking.wireguard.interfaces` in a host-specific module. |
| **tubearchivist** | Requires three companion OCI containers (the main app, Elasticsearch, and Redis) with coordinated volume mounts and a shared network. Complexity of 3-container orchestration exceeds the simple enable-flag pattern. |
| **authentik** | Requires PostgreSQL, Redis, a worker process, and a large environment config block. Authelia (added as service #12) provides SSO/2FA with simpler setup and is a direct alternative. |

### Gitea

Gitea is explicitly excluded. Forgejo (already present) is a Gitea fork and provides the same functionality.

---

## Port Conflict Matrix

| Port | Existing Services | New Services | Resolution |
|------|-------------------|--------------|------------|
| 53 | adguard | unbound | Note conflict — enable only one DNS service |
| 80 | nginx, caddy, traefik | nginx-proxy-manager | Note conflict — enable only one reverse proxy |
| 443 | nginx, caddy, traefik | nginx-proxy-manager | Note conflict — enable only one reverse proxy |
| 3000 | grafana, forgejo | — | Existing conflict unchanged |
| 8080 | arr, scrutiny, stirling-pdf, traefik dashboard | — | No new services on 8080 |
| 8088 | — | zigbee2mqtt | Safe (standard zigbee2mqtt uses 8080; we use 8088 to avoid conflict) |
| 9000 | mealie | minio (API), listmonk (standard) | minio default is 9000 — note conflict; listmonk default changed to 9025 |
| 9090 | cockpit | prometheus | Note conflict — adjust cockpit.port if both are needed |

---

## Existing Patterns Reference

Before implementing, the following patterns from existing modules MUST be followed exactly:

### Pattern A — Simple native service (enable only)
Reference: `modules/server/mealie.nix`, `modules/server/ntfy.nix`, `modules/server/scrutiny.nix`
```nix
{ config, lib, pkgs, ... }:
let cfg = config.vexos.server.<name>; in
{
  options.vexos.server.<name> = {
    enable = lib.mkEnableOption "<description>";
  };
  config = lib.mkIf cfg.enable {
    services.<name>.enable = true;
    networking.firewall.allowedTCPPorts = [ <port> ];
  };
}
```

### Pattern B — Native service with port option
Reference: `modules/server/vaultwarden.nix`, `modules/server/headscale.nix`, `modules/server/adguard.nix`
```nix
options.vexos.server.<name> = {
  enable = lib.mkEnableOption "...";
  port = lib.mkOption {
    type = lib.types.port;
    default = <port>;
    description = "Port for the <name> web interface.";
  };
};
```

### Pattern C — Native service with extra string option + assertion
Reference: `modules/server/proxmox.nix`
```nix
options.vexos.server.<name> = {
  enable = lib.mkEnableOption "...";
  someOption = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "...";
  };
};
config = lib.mkIf cfg.enable {
  assertions = [{
    assertion = cfg.someOption != "";
    message = "vexos.server.<name>.someOption must be set when enable = true.";
  }];
  ...
};
```

### Pattern D — OCI container
Reference: `modules/server/uptime-kuma.nix`, `modules/server/homepage.nix`, `modules/server/stirling-pdf.nix`
```nix
config = lib.mkIf cfg.enable {
  virtualisation.docker.enable = lib.mkDefault true;
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.<name> = {
    image = "<image>:<tag>";
    ports = [ "${toString cfg.port}:<internal-port>" ];
    volumes = [ "<named-volume>:/path" ];
  };
  networking.firewall.allowedTCPPorts = [ cfg.port ];
};
```

### Pattern E — Service with extra options and optional extras (no assertion)
Reference: `modules/server/rustdesk.nix`
```nix
config = lib.mkIf cfg.enable {
  services.rustdesk-server = {
    enable = true;
    openFirewall = true;
  } // lib.optionalAttrs (cfg.relayIP != "") {
    relayIP = cfg.relayIP;
  };
};
```

---

## Files to Create (17 new module files)

```
modules/server/prometheus.nix
modules/server/loki.nix
modules/server/netdata.nix
modules/server/unbound.nix
modules/server/paperless.nix
modules/server/minio.nix
modules/server/matrix-conduit.nix
modules/server/navidrome.nix
modules/server/code-server.nix
modules/server/node-red.nix
modules/server/zigbee2mqtt.nix
modules/server/authelia.nix
modules/server/photoprism.nix
modules/server/listmonk.nix
modules/server/dozzle.nix
modules/server/portainer.nix
modules/server/nginx-proxy-manager.nix
```

## Files to Modify (3 existing files)

```
modules/server/default.nix
template/server-services.nix
justfile
```

---

## Section 1: New Module File Contents

### 1.1 — `modules/server/prometheus.nix`

```nix
# modules/server/prometheus.nix
# Prometheus — time-series metrics collection and alerting.
# Pair with Grafana (enable separately) for dashboards.
# ⚠ Default port 9090 conflicts with Cockpit — adjust cockpit.port if both are needed.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.prometheus;
in
{
  options.vexos.server.prometheus = {
    enable = lib.mkEnableOption "Prometheus metrics collection";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for the Prometheus web UI and API. ⚠ Conflicts with Cockpit on port 9090.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = cfg.port;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

---

### 1.2 — `modules/server/loki.nix`

```nix
# modules/server/loki.nix
# Loki — log aggregation system (Grafana stack).
# Pair with Grafana for log visualization. Ships logs via Promtail or Alloy agents.
# Default port: 3100
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.loki;
in
{
  options.vexos.server.loki = {
    enable = lib.mkEnableOption "Loki log aggregation";
  };

  config = lib.mkIf cfg.enable {
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;

        server.http_listen_port = 3100;

        ingester = {
          lifecycler = {
            ring = {
              kvstore.store = "inmemory";
              replication_factor = 1;
            };
            final_sleep = "0s";
          };
          chunk_idle_period = "5m";
          chunk_retain_period = "30s";
        };

        schema_config.configs = [{
          from = "2024-01-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }];

        storage_config = {
          tsdb_shipper = {
            active_index_directory = "/var/lib/loki/tsdb-active";
            cache_location = "/var/lib/loki/tsdb-cache";
          };
          filesystem.directory = "/var/lib/loki/chunks";
        };

        limits_config = {
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };

        compactor = {
          working_directory = "/var/lib/loki/compactor";
          retention_enabled = false;
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 3100 ];
  };
}
```

---

### 1.3 — `modules/server/netdata.nix`

```nix
# modules/server/netdata.nix
# Netdata — real-time system performance and health monitoring.
# Default port: 19999
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.netdata;
in
{
  options.vexos.server.netdata = {
    enable = lib.mkEnableOption "Netdata real-time system monitoring";
  };

  config = lib.mkIf cfg.enable {
    services.netdata = {
      enable = true;
    };

    networking.firewall.allowedTCPPorts = [ 19999 ];
  };
}
```

---

### 1.4 — `modules/server/unbound.nix`

```nix
# modules/server/unbound.nix
# Unbound — validating, recursive, caching DNS resolver.
# ⚠ Port 53 conflicts with AdGuard Home (adguard) — enable only one DNS service.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.unbound;
in
{
  options.vexos.server.unbound = {
    enable = lib.mkEnableOption "Unbound local DNS resolver";
  };

  config = lib.mkIf cfg.enable {
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [ "0.0.0.0" "::" ];
          access-control = [
            "127.0.0.0/8 allow"
            "10.0.0.0/8 allow"
            "172.16.0.0/12 allow"
            "192.168.0.0/16 allow"
          ];
          hide-identity = true;
          hide-version = true;
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 53 ];
    networking.firewall.allowedUDPPorts = [ 53 ];
  };
}
```

---

### 1.5 — `modules/server/paperless.nix`

```nix
# modules/server/paperless.nix
# Paperless-ngx — document management system with OCR and full-text search.
# Default port: 28981
# Note: Redis is managed automatically by the NixOS paperless module.
#       Admin password is auto-generated on first run; check journalctl -u paperless.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.paperless;
in
{
  options.vexos.server.paperless = {
    enable = lib.mkEnableOption "Paperless-ngx document management";

    port = lib.mkOption {
      type = lib.types.port;
      default = 28981;
      description = "Port for the Paperless-ngx web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.paperless = {
      enable = true;
      port = cfg.port;
      address = "0.0.0.0";
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

> **VERIFY:** `services.paperless.address` — confirm this option exists in nixpkgs 25.05. If not, the bind address may be controlled via `services.paperless.settings.PAPERLESS_ALLOWED_HOSTS` or similar. The firewall rule is required regardless.

---

### 1.6 — `modules/server/minio.nix`

```nix
# modules/server/minio.nix
# MinIO — S3-compatible object storage server.
# API default port: 9000  ⚠ conflicts with Mealie — set apiPort if both are enabled.
# Console default port: 9001
# Credentials: create /etc/nixos/secrets/minio-credentials containing:
#   MINIO_ROOT_USER=admin
#   MINIO_ROOT_PASSWORD=changeme123
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.minio;
in
{
  options.vexos.server.minio = {
    enable = lib.mkEnableOption "MinIO S3-compatible object storage";

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 9000;
      description = "Port for the MinIO S3 API. ⚠ Conflicts with Mealie on port 9000.";
    };

    consolePort = lib.mkOption {
      type = lib.types.port;
      default = 9001;
      description = "Port for the MinIO web console.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.minio = {
      enable = true;
      listenAddress = ":${toString cfg.apiPort}";
      consoleAddress = ":${toString cfg.consolePort}";
      rootCredentialsFile = "/etc/nixos/secrets/minio-credentials";
    };

    networking.firewall.allowedTCPPorts = [ cfg.apiPort cfg.consolePort ];
  };
}
```

---

### 1.7 — `modules/server/matrix-conduit.nix`

```nix
# modules/server/matrix-conduit.nix
# Conduit — simple, fast Matrix homeserver written in Rust.
# Default HTTP port: 6167
# For federation, set serverName to your public domain and place a reverse proxy
# in front at /_matrix/ and /.well-known/matrix/ paths.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.matrix-conduit;
in
{
  options.vexos.server.matrix-conduit = {
    enable = lib.mkEnableOption "Conduit Matrix homeserver";

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = ''
        Matrix server name (your domain, e.g. example.com).
        Appears in Matrix IDs: @user:example.com.
        Set to your actual domain for federation; use "localhost" for local-only.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6167;
      description = "Port for the Conduit HTTP listener.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.matrix-conduit = {
      enable = true;
      settings.global = {
        server_name = cfg.serverName;
        port = cfg.port;
        address = "0.0.0.0";
        database_backend = "rocksdb";
        allow_registration = false;
        allow_federation = cfg.serverName != "localhost";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

> **Note on `just enable` prompting:** The `enable` recipe must prompt for `serverName` at enable time (see Section 3 — justfile changes). This follows the same pattern as `proxmox.ipAddress`.

---

### 1.8 — `modules/server/navidrome.nix`

```nix
# modules/server/navidrome.nix
# Navidrome — self-hosted music streaming (Subsonic/Airsonic API compatible).
# Compatible clients: DSub, Symfonium, Substreamer, Feishin, Sonixd.
# Default port: 4533
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.navidrome;
in
{
  options.vexos.server.navidrome = {
    enable = lib.mkEnableOption "Navidrome music streaming server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4533;
      description = "Port for the Navidrome web interface.";
    };

    musicFolder = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/navidrome/music";
      description = "Path to the music library folder.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.navidrome = {
      enable = true;
      settings = {
        Address = "0.0.0.0";
        Port = cfg.port;
        MusicFolder = cfg.musicFolder;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

---

### 1.9 — `modules/server/code-server.nix`

```nix
# modules/server/code-server.nix
# code-server — VS Code in the browser, accessible from any device on the LAN.
# Default port: 4444
# Password: if hashedPasswordFile is set, auth is enabled. Otherwise auth=none.
#   Generate a bcrypt hash: nix shell nixpkgs#apacheHttpd -c htpasswd -nbBC 10 "" password | cut -d: -f2
#   Then write the hash (single line) to /etc/nixos/secrets/code-server-password
# ⚠ Bind behind a TLS reverse proxy before exposing outside the LAN.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.code-server;
in
{
  options.vexos.server.code-server = {
    enable = lib.mkEnableOption "code-server VS Code in the browser";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4444;
      description = "Port for the code-server web interface.";
    };

    hashedPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing a bcrypt-hashed password for code-server authentication.
        If null, authentication is disabled (suitable for trusted LAN only).
        Generate with: nix shell nixpkgs#apacheHttpd -c htpasswd -nbBC 10 "" yourpassword | cut -d: -f2
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.code-server = {
      enable = true;
      host = "0.0.0.0";
      port = cfg.port;
      auth = if cfg.hashedPasswordFile != null then "password" else "none";
      hashedPasswordFile = cfg.hashedPasswordFile;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

> **VERIFY:** Confirm `services.code-server.host`, `services.code-server.auth`, and `services.code-server.hashedPasswordFile` option names exist in nixpkgs 25.05. If the module uses `extraArguments` instead of direct options, substitute:
> ```nix
> services.code-server = {
>   enable = true;
>   extraArguments =
>     [ "--bind-addr" "0.0.0.0:${toString cfg.port}" ]
>     ++ lib.optionals (cfg.hashedPasswordFile == null) [ "--auth" "none" ];
> };
> ```

---

### 1.10 — `modules/server/node-red.nix`

```nix
# modules/server/node-red.nix
# Node-RED — low-code flow-based automation and IoT programming tool.
# Default port: 1880
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.node-red;
in
{
  options.vexos.server.node-red = {
    enable = lib.mkEnableOption "Node-RED flow-based automation";
  };

  config = lib.mkIf cfg.enable {
    services.node-red = {
      enable = true;
      openFirewall = true; # Port 1880
    };
  };
}
```

> **VERIFY:** If `services.node-red.openFirewall` does not exist in nixpkgs 25.05, replace with:
> ```nix
> services.node-red.enable = true;
> networking.firewall.allowedTCPPorts = [ 1880 ];
> ```

---

### 1.11 — `modules/server/zigbee2mqtt.nix`

```nix
# modules/server/zigbee2mqtt.nix
# Zigbee2MQTT — bridges Zigbee devices to MQTT, no proprietary hub required.
# Default frontend port: 8088 (non-standard to avoid conflict with port 8080 services)
# Set serialPort to your Zigbee coordinator device (e.g. /dev/ttyUSB0, /dev/ttyACM0).
# MQTT broker: this module assumes an MQTT broker is running at localhost:1883.
# Pair with home-assistant or node-red for automations.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.zigbee2mqtt;
in
{
  options.vexos.server.zigbee2mqtt = {
    enable = lib.mkEnableOption "Zigbee2MQTT Zigbee bridge";

    serialPort = lib.mkOption {
      type = lib.types.str;
      default = "/dev/ttyUSB0";
      description = "Path to the Zigbee coordinator serial device (e.g. /dev/ttyUSB0, /dev/ttyACM0).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8088;
      description = "Port for the Zigbee2MQTT web frontend.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.zigbee2mqtt = {
      enable = true;
      settings = {
        homeassistant = false;
        permit_join = false;
        serial.port = cfg.serialPort;
        frontend = {
          enabled = true;
          port = cfg.port;
          host = "0.0.0.0";
        };
        mqtt.server = "mqtt://localhost:1883";
        advanced.log_level = "info";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

> **Note on `just enable` prompting:** The `enable` recipe must prompt for `serialPort` at enable time (see Section 3 — justfile changes).

---

### 1.12 — `modules/server/authelia.nix`

```nix
# modules/server/authelia.nix
# Authelia — SSO and 2FA authentication proxy (OCI container).
# Default port: 9091
# Before enabling, create the configuration directory:
#   sudo mkdir -p /etc/nixos/authelia
#   sudo cp /path/to/configuration.yml /etc/nixos/authelia/
#   sudo cp /path/to/users_database.yml /etc/nixos/authelia/
# See: https://www.authelia.com/configuration/prologue/introduction/
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.authelia;
in
{
  options.vexos.server.authelia = {
    enable = lib.mkEnableOption "Authelia SSO/2FA authentication proxy";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9091;
      description = "Port for the Authelia web portal.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.authelia = {
      image = "authelia/authelia:latest";
      ports = [ "${toString cfg.port}:9091" ];
      volumes = [
        "/etc/nixos/authelia:/config"
      ];
      environment = {
        TZ = "America/Chicago";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

---

### 1.13 — `modules/server/photoprism.nix`

```nix
# modules/server/photoprism.nix
# PhotoPrism — AI-powered photo management and organizer.
# Default port: 2342
# Admin password: create /etc/nixos/secrets/photoprism-password (plaintext, single line)
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.photoprism;
in
{
  options.vexos.server.photoprism = {
    enable = lib.mkEnableOption "PhotoPrism photo management";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2342;
      description = "Port for the PhotoPrism web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.photoprism = {
      enable = true;
      port = cfg.port;
      address = "0.0.0.0";
      passwordFile = "/etc/nixos/secrets/photoprism-password";
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

> **VERIFY:** Confirm `services.photoprism.address` and `services.photoprism.passwordFile` option names in nixpkgs 25.05. The `passwordFile` might be named `initialAdminPasswordFile` or similar. If `passwordFile` does not exist, remove it from the module and document that the user must set the password via the first-run wizard.

---

### 1.14 — `modules/server/listmonk.nix`

```nix
# modules/server/listmonk.nix
# Listmonk — self-hosted newsletter and mailing list manager.
# Default port: 9025 (non-standard default; avoids conflict with Mealie/MinIO on port 9000)
# PostgreSQL is created automatically by the NixOS listmonk module.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.listmonk;
in
{
  options.vexos.server.listmonk = {
    enable = lib.mkEnableOption "Listmonk newsletter and mailing list manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9025;
      description = "Port for the Listmonk web interface. Default 9025 avoids conflict with Mealie/MinIO on port 9000.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.listmonk = {
      enable = true;
      settings.app.address = "0.0.0.0:${toString cfg.port}";
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

> **VERIFY:** Confirm `services.listmonk.settings.app.address` is the correct nixpkgs option path for listmonk's bind address in nixpkgs 25.05. If the option does not exist at that path, check the listmonk module source for the correct attribute name. The TOML config key is `[app]\naddress = "host:port"`.

---

### 1.15 — `modules/server/dozzle.nix`

```nix
# modules/server/dozzle.nix
# Dozzle — real-time web UI for Docker container logs (OCI container).
# Default port: 8888
# Requires Docker to be enabled (vexos.server.docker.enable = true).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.dozzle;
in
{
  options.vexos.server.dozzle = {
    enable = lib.mkEnableOption "Dozzle Docker log viewer";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Port for the Dozzle web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.dozzle = {
      image = "amir20/dozzle:latest";
      ports = [ "${toString cfg.port}:8080" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock:ro"
      ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

---

### 1.16 — `modules/server/portainer.nix`

```nix
# modules/server/portainer.nix
# Portainer CE — Docker container management web UI (OCI container).
# Default port: 9443 (HTTPS)
# Requires Docker to be enabled (vexos.server.docker.enable = true).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.portainer;
in
{
  options.vexos.server.portainer = {
    enable = lib.mkEnableOption "Portainer Docker management UI";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9443;
      description = "HTTPS port for the Portainer web UI.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.portainer = {
      image = "portainer/portainer-ce:latest";
      ports = [ "${toString cfg.port}:9443" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock:ro"
        "portainer-data:/data"
      ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

---

### 1.17 — `modules/server/nginx-proxy-manager.nix`

```nix
# modules/server/nginx-proxy-manager.nix
# Nginx Proxy Manager — web GUI for managing Nginx reverse proxy rules (OCI container).
# Admin UI port: 81  |  HTTP proxy: 80  |  HTTPS proxy: 443
# ⚠ Ports 80 and 443 conflict with nginx, caddy, and traefik — enable only one reverse proxy.
# Default login: admin@example.com / changeme — change immediately after first login.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.nginx-proxy-manager;
in
{
  options.vexos.server.nginx-proxy-manager = {
    enable = lib.mkEnableOption "Nginx Proxy Manager reverse proxy UI";

    adminPort = lib.mkOption {
      type = lib.types.port;
      default = 81;
      description = "Port for the Nginx Proxy Manager admin interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.nginx-proxy-manager = {
      image = "jc21/nginx-proxy-manager:latest";
      ports = [
        "80:80"
        "443:443"
        "${toString cfg.adminPort}:81"
      ];
      volumes = [
        "npm-data:/data"
        "npm-letsencrypt:/etc/letsencrypt"
      ];
    };

    networking.firewall.allowedTCPPorts = [ 80 443 cfg.adminPort ];
  };
}
```

---

## Section 2: `modules/server/default.nix` Changes

The updated `default.nix` must add 17 new import lines, organized under the correct category comments. Replace the current file contents with the following (additions marked with `# NEW`):

```nix
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
    ./navidrome.nix          # NEW
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
    ./minio.nix              # NEW
    ./photoprism.nix         # NEW
    # ── Documents ────────────────────────────────────────────────────────────
    ./paperless.nix          # NEW
    # ── Development ──────────────────────────────────────────────────────────
    ./forgejo.nix
    ./code-server.nix        # NEW
    # ── Security ─────────────────────────────────────────────────────────────
    ./vaultwarden.nix
    ./authelia.nix           # NEW
    # ── Networking & Reverse Proxies ─────────────────────────────────────────
    ./nginx.nix
    ./caddy.nix
    ./traefik.nix
    ./adguard.nix
    ./headscale.nix
    ./unbound.nix            # NEW
    ./nginx-proxy-manager.nix  # NEW
    # ── Monitoring & Management ──────────────────────────────────────────────
    ./cockpit.nix
    ./uptime-kuma.nix
    ./homepage.nix
    ./grafana.nix
    ./scrutiny.nix
    ./prometheus.nix         # NEW
    ./loki.nix               # NEW
    ./netdata.nix            # NEW
    ./dozzle.nix             # NEW
    ./portainer.nix          # NEW
    # ── Notifications ────────────────────────────────────────────────────────
    ./ntfy.nix
    # ── Food & Home ──────────────────────────────────────────────────────────
    ./mealie.nix
    ./listmonk.nix           # NEW
    # ── Remote Access ────────────────────────────────────────────────────────
    ./rustdesk.nix
    # ── Automation & Smart Home ──────────────────────────────────────────────
    ./home-assistant.nix
    ./node-red.nix           # NEW
    ./zigbee2mqtt.nix        # NEW
    # ── Communications ───────────────────────────────────────────────────────
    ./matrix-conduit.nix     # NEW
    # ── PDF Tools ────────────────────────────────────────────────────────────
    ./stirling-pdf.nix
    # ── Virtualisation ────────────────────────────────────────────────────────────
    ./proxmox.nix
  ];
}
```

---

## Section 3: `template/server-services.nix` Changes

Add the following blocks to the existing template at the end of each relevant category section. Each line follows the existing comment format exactly.

### New `# ── Media Servers` entries (after `tautulli` line):
```nix
  # vexos.server.navidrome.enable = false;               # Port 4533 — music streaming
```

### New `# ── Cloud & Files` entries (after `immich` line):
```nix
  # vexos.server.minio.enable = false;                   # Port 9000 API + 9001 console (⚠ conflicts with mealie)
  # vexos.server.minio.apiPort = 9000;                   # Change if mealie is also enabled
  # vexos.server.photoprism.enable = false;              # Port 2342 — photo management
```

### New `# ── Documents` section (after the cloud & files block):
```nix
  # ── Documents ─────────────────────────────────────────────────────────────
  # vexos.server.paperless.enable = false;               # Port 28981 — document management with OCR
```

### New `# ── Development` entries (after `forgejo` line):
```nix
  # vexos.server.code-server.enable = false;             # Port 4444 — VS Code in the browser
  # vexos.server.code-server.hashedPasswordFile = null;  # Set to /etc/nixos/secrets/code-server-password (bcrypt)
```

### New `# ── Security` entries (after `vaultwarden` line):
```nix
  # vexos.server.authelia.enable = false;                # Port 9091 — SSO/2FA proxy (requires /etc/nixos/authelia/configuration.yml)
```

### New `# ── Networking & Reverse Proxies` entries (after `headscale` line):
```nix
  # vexos.server.unbound.enable = false;                 #           ⚠ conflicts with adguard on port 53
  # vexos.server.nginx-proxy-manager.enable = false;     # Port 81 admin + 80/443 ⚠ conflicts with nginx/caddy/traefik
```

### New `# ── Monitoring & Management` entries (after `grafana` line):
```nix
  # vexos.server.prometheus.enable = false;              # Port 9090 (⚠ conflicts with cockpit)
  # vexos.server.loki.enable = false;                    # Port 3100 — log aggregation (pair with grafana)
  # vexos.server.netdata.enable = false;                 # Port 19999 — real-time system monitoring
  # vexos.server.dozzle.enable = false;                  # Port 8888 — Docker log viewer (requires docker)
  # vexos.server.portainer.enable = false;               # Port 9443 — Docker management UI (requires docker)
```

### New `# ── Food & Home` / `# ── Productivity` entries:

Add after mealie line:
```nix
  # vexos.server.listmonk.enable = false;                # Port 9025 — newsletter/mailing list manager
```

### New `# ── Automation & Smart Home` entries (after `home-assistant` line):
```nix
  # vexos.server.node-red.enable = false;                # Port 1880 — flow-based automation
  # vexos.server.zigbee2mqtt.enable = false;             # Port 8088 — Zigbee bridge
  # vexos.server.zigbee2mqtt.serialPort = "/dev/ttyUSB0"; # Set to your Zigbee coordinator device
```

### New `# ── Communications` section (new section near end):
```nix
  # ── Communications ────────────────────────────────────────────────────────
  # vexos.server.matrix-conduit.enable = false;          # Port 6167 — Matrix homeserver
  # vexos.server.matrix-conduit.serverName = "localhost"; # Set to your domain for federation
```

---

## Section 4: `justfile` Changes

### 4.1 — `_server_service_names` (line 341)

Replace the current value with the expanded alphabetically-sorted list:

```just
_server_service_names := "adguard arr audiobookshelf authelia caddy cockpit code-server docker dozzle forgejo grafana headscale home-assistant homepage immich jellyfin jellyseerr kavita komga listmonk loki matrix-conduit mealie minio navidrome netdata nextcloud nginx nginx-proxy-manager node-red ntfy overseerr paperless papermc photoprism plex portainer prometheus proxmox rustdesk scrutiny stirling-pdf syncthing tautulli traefik unbound uptime-kuma vaultwarden zigbee2mqtt"
```

---

### 4.2 — `list-services` recipe

Add new service entries to the appropriate `_svc` lines. Show the full updated recipe body:

```bash
    echo ""
    echo "Available server service modules:"
    _hdr "Books & Reading";            _svc kavita;           _svc komga
    _hdr "Communications";             _svc matrix-conduit
    _hdr "Files & Storage";            _svc immich;           _svc minio;           _svc nextcloud;       _svc photoprism;      _svc syncthing
    _hdr "Gaming";                     _svc papermc
    _hdr "Infrastructure";             _svc caddy;            _svc docker;          _svc nginx;           _svc nginx-proxy-manager; _svc portainer; _svc traefik
    _hdr "Media";                      _svc audiobookshelf;   _svc jellyfin;        _svc navidrome;       _svc plex;            _svc tautulli
    _hdr "Media Requests & Automation";_svc arr;              _svc jellyseerr;      _svc overseerr
    _hdr "Monitoring & Admin";         _svc cockpit;          _svc dozzle;          _svc grafana;         _svc loki;            _svc netdata;     _svc prometheus;  _svc scrutiny;  _svc uptime-kuma
    _hdr "Networking & Security";      _svc adguard;          _svc authelia;        _svc headscale;       _svc unbound;         _svc vaultwarden
    _hdr "Productivity";               _svc code-server;      _svc forgejo;         _svc homepage;        _svc listmonk;        _svc mealie;      _svc paperless;   _svc stirling-pdf
    _hdr "Remote Access";              _svc rustdesk
    _hdr "Smart Home & Notifications"; _svc home-assistant;   _svc node-red;        _svc ntfy;            _svc zigbee2mqtt
    _hdr "Experimental";               _svc proxmox
    echo ""
    echo "Use 'just enable <service>' to enable a module on a server host."
    echo ""
```

---

### 4.3 — `service-info` recipe — `_info()` case additions

Add the following cases to the `_info()` function's `case "$1" in` block, inserted in alphabetical order alongside existing entries:

```bash
        authelia)        printf "  %-18s  Web UI  http://<server-ip>:9091   (SSO portal + 2FA)\n"                     "$1" ;;
        code-server)     printf "  %-18s  Web UI  http://<server-ip>:4444   (VS Code in browser)\n"                   "$1" ;;
        dozzle)          printf "  %-18s  Web UI  http://<server-ip>:8888   (requires docker)\n"                      "$1" ;;
        listmonk)        printf "  %-18s  Web UI  http://<server-ip>:9025\n"                                          "$1" ;;
        loki)            printf "  %-18s  API     http://<server-ip>:3100   (pair with grafana)\n"                    "$1" ;;
        matrix-conduit)  printf "  %-18s  HTTP    http://<server-ip>:6167   (Matrix homeserver)\n"                    "$1" ;;
        minio)           printf "  %-18s  API :9000  |  Console http://<server-ip>:9001  ⚠ conflicts with mealie\n"  "$1" ;;
        navidrome)       printf "  %-18s  Web UI  http://<server-ip>:4533\n"                                          "$1" ;;
        netdata)         printf "  %-18s  Web UI  http://<server-ip>:19999\n"                                         "$1" ;;
        nginx-proxy-manager) printf "  %-18s  Admin   http://<server-ip>:81   |  Proxy :80/:443  ⚠ conflicts with nginx/caddy/traefik\n" "$1" ;;
        node-red)        printf "  %-18s  Web UI  http://<server-ip>:1880\n"                                          "$1" ;;
        paperless)       printf "  %-18s  Web UI  http://<server-ip>:28981\n"                                         "$1" ;;
        photoprism)      printf "  %-18s  Web UI  http://<server-ip>:2342\n"                                          "$1" ;;
        portainer)       printf "  %-18s  Web UI  https://<server-ip>:9443  (requires docker)\n"                      "$1" ;;
        prometheus)      printf "  %-18s  Web UI  http://<server-ip>:9090   ⚠ conflicts with cockpit\n"               "$1" ;;
        unbound)         printf "  %-18s  DNS on :53  (no web UI)  ⚠ conflicts with adguard\n"                        "$1" ;;
        zigbee2mqtt)     printf "  %-18s  Web UI  http://<server-ip>:8088\n"                                          "$1" ;;
```

---

### 4.4 — `services` recipe

Add new service entries to the appropriate `_check` lines. Show the full updated recipe body:

```bash
    echo ""
    echo "Server services (/etc/nixos/server-services.nix):"
    _hdr "Books & Reading";            _check kavita;         _check komga
    _hdr "Communications";             _check matrix-conduit
    _hdr "Files & Storage";            _check immich;         _check minio;         _check nextcloud;     _check photoprism;    _check syncthing
    _hdr "Gaming";                     _check papermc
    _hdr "Infrastructure";             _check caddy;          _check docker;        _check nginx;         _check nginx-proxy-manager; _check portainer; _check traefik
    _hdr "Media";                      _check audiobookshelf; _check jellyfin;      _check navidrome;     _check plex;          _check tautulli
    _hdr "Media Requests & Automation";_check arr;            _check jellyseerr;    _check overseerr
    _hdr "Monitoring & Admin";         _check cockpit;        _check dozzle;        _check grafana;       _check loki;          _check netdata;   _check prometheus; _check scrutiny; _check uptime-kuma
    _hdr "Networking & Security";      _check adguard;        _check authelia;      _check headscale;     _check unbound;       _check vaultwarden
    _hdr "Productivity";               _check code-server;    _check forgejo;       _check homepage;      _check listmonk;      _check mealie;    _check paperless;  _check stirling-pdf
    _hdr "Remote Access";              _check rustdesk
    _hdr "Smart Home & Notifications"; _check home-assistant; _check node-red;      _check ntfy;          _check zigbee2mqtt
    _hdr "Experimental";               _check proxmox
    echo ""
```

---

### 4.5 — `status` recipe — case additions

Add the following cases to the `case "$SERVICE" in` block in the `status` recipe, inserted in alphabetical order:

```bash
      authelia)       UNITS="docker-authelia";             URLS="http://localhost:9091" ;;
      code-server)    UNITS="code-server";                 URLS="http://localhost:4444" ;;
      dozzle)         UNITS="docker-dozzle";               URLS="http://localhost:8888" ;;
      listmonk)       UNITS="listmonk";                    URLS="http://localhost:9025" ;;
      loki)           UNITS="loki";                        URLS="http://localhost:3100" ;;
      matrix-conduit) UNITS="matrix-conduit";              URLS="http://localhost:6167" ;;
      minio)          UNITS="minio";                       URLS="http://localhost:9000 http://localhost:9001" ;;
      navidrome)      UNITS="navidrome";                   URLS="http://localhost:4533" ;;
      netdata)        UNITS="netdata";                     URLS="http://localhost:19999" ;;
      nginx-proxy-manager) UNITS="docker-nginx-proxy-manager"; URLS="http://localhost:81" ;;
      node-red)       UNITS="node-red";                    URLS="http://localhost:1880" ;;
      paperless)      UNITS="paperless";                   URLS="http://localhost:28981" ;;
      photoprism)     UNITS="photoprism";                  URLS="http://localhost:2342" ;;
      portainer)      UNITS="docker-portainer";            URLS="https://localhost:9443" ;;
      prometheus)     UNITS="prometheus";                  URLS="http://localhost:9090" ;;
      unbound)        UNITS="unbound";                     URLS="" ;;
      zigbee2mqtt)    UNITS="zigbee2mqtt";                 URLS="http://localhost:8088" ;;
```

> **Note on systemd unit names for OCI containers:** NixOS names OCI container services as `docker-<container-name>.service`. Verify the exact unit names after first build. The container names used in `virtualisation.oci-containers.containers.<name>` determine the systemd unit name.

---

### 4.6 — `enable` recipe — new prompt blocks

Two new services need interactive prompts at enable time, following the existing `proxmox.ipAddress` pattern. Add these blocks **AFTER** the existing proxmox prompt block and **BEFORE** the `echo "✓ Enabled: $SERVICE"` line:

```bash
    # Matrix Conduit serverName prompt — ask once at enable time
    if [ "$SERVICE" = "matrix-conduit" ]; then
        SN_OPTION="vexos.server.matrix-conduit.serverName"
        _server_name=""
        while [ -z "$_server_name" ]; do
            read -r -p "  Enter your Matrix server name (domain, e.g. example.com, or 'localhost' for local-only): " _server_name
        done
        if grep -qP "^\s*#?\s*${SN_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
            sudo sed -i -E "s|^(\s*)#?\s*(${SN_OPTION//./\\.})\s*=\s*\"[^\"]*\"\s*;|\1${SN_OPTION} = \"${_server_name}\";|" "$SVC_FILE"
        else
            sudo sed -i "s|${OPTION} = true;|${OPTION} = true;\n  ${SN_OPTION} = \"${_server_name}\";|" "$SVC_FILE"
        fi
    fi

    # Zigbee2MQTT serialPort prompt — ask once at enable time
    if [ "$SERVICE" = "zigbee2mqtt" ]; then
        SP_OPTION="vexos.server.zigbee2mqtt.serialPort"
        read -r -p "  Enter the Zigbee coordinator serial port [/dev/ttyUSB0]: " _serial
        [ -z "$_serial" ] && _serial="/dev/ttyUSB0"
        if grep -qP "^\s*#?\s*${SP_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
            sudo sed -i -E "s|^(\s*)#?\s*(${SP_OPTION//./\\.})\s*=\s*\"[^\"]*\"\s*;|\1${SP_OPTION} = \"${_serial}\";|" "$SVC_FILE"
        else
            sudo sed -i "s|${OPTION} = true;|${OPTION} = true;\n  ${SP_OPTION} = \"${_serial}\";|" "$SVC_FILE"
        fi
    fi
```

---

### 4.7 — `enable` recipe — post-enable case block additions

Add the following cases to the final `case "$SERVICE" in` block (the post-`echo "✓ Enabled"` info display). Insert in alphabetical order alongside existing entries:

```bash
      authelia)
        echo "  Container: authelia (NixOS OCI container)"
        echo "  Web UI:    http://<server-ip>:9091"
        echo "  About:     SSO portal with 2FA (TOTP, WebAuthn). Place in front of other services via your reverse proxy."
        echo "  Config:    Create /etc/nixos/authelia/configuration.yml and users_database.yml BEFORE rebuilding."
        echo "             See: https://www.authelia.com/configuration/prologue/introduction/"
        ;;
      code-server)
        echo "  Service:  code-server.service"
        echo "  Web UI:   http://<server-ip>:4444"
        echo "  About:    Full VS Code experience in the browser — edit files, run terminals, install extensions."
        echo "  Auth:     If vexos.server.code-server.hashedPasswordFile is set, password auth is enforced."
        echo "            Generate hash: nix shell nixpkgs#apacheHttpd -c htpasswd -nbBC 10 \"\" yourpassword | cut -d: -f2"
        echo "            Write single-line hash to: /etc/nixos/secrets/code-server-password"
        echo "  Warning:  Put behind a TLS reverse proxy before exposing outside your local network."
        ;;
      dozzle)
        echo "  Container: dozzle (NixOS OCI container)"
        echo "  Web UI:    http://<server-ip>:8888"
        echo "  About:     Real-time log viewer for all running Docker containers — no setup, no storage required."
        echo "  Note:      Requires Docker to be enabled (vexos.server.docker.enable = true)."
        ;;
      listmonk)
        echo "  Service:  listmonk.service"
        echo "  Web UI:   http://<server-ip>:9025"
        echo "  About:    Self-hosted newsletter and mailing list manager with subscriber import and campaign analytics."
        echo "  Note:     PostgreSQL is created automatically. Visit the web UI to complete setup."
        echo "  Warning:  Port 9025 is the vexos default (the standard port 9000 conflicts with Mealie/MinIO)."
        ;;
      loki)
        echo "  Service:  loki.service"
        echo "  API:      http://<server-ip>:3100"
        echo "  About:    Log aggregation system. Pair with Grafana and a Promtail/Alloy agent to ship and visualize logs."
        echo "  Note:     Add Loki as a data source in Grafana: http://localhost:3100"
        ;;
      matrix-conduit)
        echo "  Service:  matrix-conduit.service"
        echo "  Port:     :6167 (HTTP listener)"
        echo "  About:    Lightweight Matrix homeserver. Use any Matrix client (Element, FluffyChat, Cinny)."
        echo "  Connect:  In your Matrix client, set the homeserver to http://<server-ip>:6167"
        echo "  Federation: For federation, set serverName to your public domain and route"
        echo "              /_matrix/ and /.well-known/matrix/ through your reverse proxy to :6167."
        ;;
      minio)
        echo "  Service:  minio.service"
        echo "  API:      http://<server-ip>:9000  |  Console: http://<server-ip>:9001"
        echo "  About:    S3-compatible object storage — compatible with any S3 client, SDK, or tool (rclone, s3cmd)."
        echo "  Secrets:  Create /etc/nixos/secrets/minio-credentials before rebuilding:"
        echo "              MINIO_ROOT_USER=admin"
        echo "              MINIO_ROOT_PASSWORD=changeme123"
        echo "  Warning:  Port 9000 conflicts with Mealie. Add vexos.server.minio.apiPort = 9100; if using both."
        ;;
      navidrome)
        echo "  Service:  navidrome.service"
        echo "  Web UI:   http://<server-ip>:4533"
        echo "  About:    Music streaming server compatible with Subsonic/Airsonic apps (DSub, Symfonium, Feishin, Sonixd)."
        echo "  Note:     First run creates the admin account. Add music to the configured MusicFolder."
        echo "            Default music folder: /var/lib/navidrome/music — set vexos.server.navidrome.musicFolder to override."
        ;;
      netdata)
        echo "  Service:  netdata.service"
        echo "  Web UI:   http://<server-ip>:19999"
        echo "  About:    Real-time system monitoring dashboard — CPU, memory, disk, network, and hundreds of collectors."
        echo "  Note:     Data is stored in-memory by default. For persistent history, configure persistent storage via services.netdata.config."
        ;;
      nginx-proxy-manager)
        echo "  Container: nginx-proxy-manager (NixOS OCI container)"
        echo "  Admin UI:  http://<server-ip>:81"
        echo "  Ports:     :80 (HTTP proxy), :443 (HTTPS proxy)"
        echo "  About:     Web GUI to configure Nginx reverse proxy rules with automatic Let's Encrypt TLS."
        echo "  Login:     Default: admin@example.com / changeme — CHANGE IMMEDIATELY after first login."
        echo "  Warning:   Ports 80/443 conflict with nginx, caddy, and traefik — enable only one reverse proxy."
        ;;
      node-red)
        echo "  Service:  node-red.service"
        echo "  Web UI:   http://<server-ip>:1880"
        echo "  About:    Low-code flow-based automation. Wire together APIs, IoT sensors, MQTT, and services visually."
        echo "  Note:     Flows are stored in /var/lib/node-red/. Pair with zigbee2mqtt or home-assistant for smart home automations."
        ;;
      paperless)
        echo "  Service:  paperless.service"
        echo "  Web UI:   http://<server-ip>:28981"
        echo "  About:    Document management with automatic OCR, full-text search, tagging, and correspondent tracking."
        echo "  Admin:    The initial admin password is printed to the journal on first run:"
        echo "              journalctl -u paperless | grep -i password"
        echo "  Consume:  Drop documents into the consumption directory for automatic import and OCR."
        ;;
      photoprism)
        echo "  Service:  photoprism.service"
        echo "  Web UI:   http://<server-ip>:2342"
        echo "  About:    AI-powered photo management — browse, search, face recognition, geo maps, and RAW support."
        echo "  Secrets:  Create /etc/nixos/secrets/photoprism-password (plaintext, single line) before rebuilding."
        ;;
      portainer)
        echo "  Container: portainer (NixOS OCI container)"
        echo "  Web UI:    https://<server-ip>:9443"
        echo "  About:     Docker container management UI — deploy stacks, inspect containers, view logs and stats."
        echo "  Note:      Create the admin account on first visit. Requires Docker to be enabled."
        echo "  Warning:   Uses self-signed TLS by default — browser will show a warning; proceed to access the UI."
        ;;
      prometheus)
        echo "  Service:  prometheus.service"
        echo "  Web UI:   http://<server-ip>:9090"
        echo "  About:    Time-series metrics database and alerting. Scrape exporters (node_exporter, etc.) and visualize in Grafana."
        echo "  Warning:  Port 9090 conflicts with Cockpit. Add vexos.server.cockpit.port = 9091; if using both."
        ;;
      unbound)
        echo "  Service:  unbound.service"
        echo "  Port:     53 (DNS)"
        echo "  About:    Validating, recursive, caching DNS resolver for your local network."
        echo "  Note:     Point your router's or client's DNS server to this machine's IP."
        echo "  Warning:  Port 53 conflicts with AdGuard Home (adguard) — enable only one DNS service."
        ;;
      zigbee2mqtt)
        echo "  Service:  zigbee2mqtt.service"
        echo "  Web UI:   http://<server-ip>:8088"
        echo "  About:    Bridges Zigbee devices (lights, sensors, switches) to MQTT — no proprietary hub required."
        echo "  Serial:   Set vexos.server.zigbee2mqtt.serialPort to your Zigbee coordinator device path."
        echo "  MQTT:     Assumes an MQTT broker at localhost:1883. Install one (e.g. Mosquitto) separately."
        echo "  Pair:     Works with Home Assistant (MQTT integration) and Node-RED for automations."
        ;;
```

---

## Section 5: Implementation Notes and Verification Checklist

The implementation subagent MUST verify the following before writing the final module files:

### Nixpkgs 25.05 Option Verification

| Module | Option to Verify | Expected Name | Fallback |
|--------|-----------------|---------------|---------|
| paperless | bind address | `services.paperless.address` | Use `services.paperless.settings.PAPERLESS_ALLOWED_HOSTS` |
| code-server | host option | `services.code-server.host` | Use `extraArguments = ["--bind-addr" "0.0.0.0:..."]` |
| code-server | auth options | `services.code-server.auth`, `.hashedPasswordFile` | Use `extraArguments = ["--auth" "none"]` |
| photoprism | bind address | `services.photoprism.address` | May default to 0.0.0.0 already |
| photoprism | password file | `services.photoprism.passwordFile` | Remove and document manual setup |
| listmonk | bind address | `services.listmonk.settings.app.address` | Check nixpkgs module source for correct attr path |
| node-red | firewall | `services.node-red.openFirewall` | Use `networking.firewall.allowedTCPPorts = [1880]` |
| navidrome | settings path | `services.navidrome.settings.{Address,Port,MusicFolder}` | Check case sensitivity (may be camelCase) |

### Build Validation Steps (from copilot-instructions.md)
After implementation:
1. `nix flake check`
2. `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
3. `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`
4. `sudo nixos-rebuild dry-build --flake .#vexos-server-vm`

The server-role dry-builds MUST succeed — these modules are imported by both `server` and `headless-server` roles.

### Port Conflict Summary for Reviewer

| Service | Port | Conflict? | Mitigation |
|---------|------|-----------|------------|
| prometheus | 9090 | Yes, cockpit | Module comment + enable info note |
| unbound | 53 | Yes, adguard | Module comment + enable info note |
| nginx-proxy-manager | 80/443 | Yes, nginx/caddy/traefik | Module comment + enable info note |
| minio | 9000 | Yes, mealie | Module comment + `apiPort` option to override |
| loki | 3100 | No | — |
| netdata | 19999 | No | — |
| navidrome | 4533 | No | — |
| code-server | 4444 | No | — |
| node-red | 1880 | No | — |
| zigbee2mqtt | 8088 | No (standard 8080 avoided) | — |
| authelia | 9091 | No | — |
| photoprism | 2342 | No | — |
| listmonk | 9025 | No (standard 9000 avoided) | — |
| dozzle | 8888 | No | — |
| portainer | 9443 | No | — |
| matrix-conduit | 6167 | No | — |

---

## Return Summary

**Spec file path:** `.github/docs/subagent_docs/server_services_expansion_spec.md`

### Services being added (17):
prometheus, loki, netdata, unbound, paperless, minio, matrix-conduit, navidrome, code-server, node-red, zigbee2mqtt, authelia, photoprism, listmonk, dozzle, portainer, nginx-proxy-manager

### Services skipped (3):
- **wireguard** — requires keys/interfaces/peers; too complex for a simple enable toggle
- **tubearchivist** — requires 3-container orchestration (app + Elasticsearch + Redis)
- **authentik** — replaced by Authelia (simpler); requires PostgreSQL + Redis + worker

### New module files to create (17):
```
modules/server/prometheus.nix
modules/server/loki.nix
modules/server/netdata.nix
modules/server/unbound.nix
modules/server/paperless.nix
modules/server/minio.nix
modules/server/matrix-conduit.nix
modules/server/navidrome.nix
modules/server/code-server.nix
modules/server/node-red.nix
modules/server/zigbee2mqtt.nix
modules/server/authelia.nix
modules/server/photoprism.nix
modules/server/listmonk.nix
modules/server/dozzle.nix
modules/server/portainer.nix
modules/server/nginx-proxy-manager.nix
```

### Existing files to modify (3):
```
modules/server/default.nix
template/server-services.nix
justfile
```
