# Spec: Fix zigbee2mqtt — auto-enable local MQTT broker (Mosquitto)

**Feature name**: `zigbee2mqtt_mqtt`  
**File**: `modules/server/zigbee2mqtt_mqtt_spec.md`  
**Date**: 2026-05-16  

---

## 1. Problem Definition

`modules/server/zigbee2mqtt.nix` enables `services.zigbee2mqtt` and hard-codes
`mqtt.server = "mqtt://localhost:1883"` in its settings, but does NOT enable any
MQTT broker.  When the module is imported and `vexos.server.zigbee2mqtt.enable =
true`, the `zigbee2mqtt` systemd service starts, immediately attempts to connect
to `localhost:1883`, finds nothing listening, and crashes/restarts in a loop.

There is no `modules/server/mosquitto.nix` in the repository.  The broker must
therefore be configured inline in the same module.

---

## 2. Current State

### 2.1 Current file — `modules/server/zigbee2mqtt.nix`

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

### 2.2 Problems identified

| # | Issue | Severity |
|---|-------|----------|
| 1 | No MQTT broker is started; `zigbee2mqtt` crashes immediately on connection failure | Critical |
| 2 | No `After=` / `Requires=` systemd dependency on a broker service | Critical |
| 3 | Header comment says "this module *assumes* an MQTT broker is running" — incorrect expectation for a self-contained module | Minor |

---

## 3. Proposed Solution

### 3.1 Architecture

Mosquitto is the de-facto lightweight MQTT broker shipped with nixpkgs
(`services.mosquitto`).  Because this is a single self-contained module
and no shared `mosquitto.nix` exists in the repository, Mosquitto is
configured inline within `zigbee2mqtt.nix` whenever
`vexos.server.zigbee2mqtt.enable = true`.

Constraints:
- The listener binds to `127.0.0.1:1883` only — no external exposure.
- `allow_anonymous true` is acceptable because the listener is loopback-only.
- Port 1883 is NOT opened in `networking.firewall`.
- `zigbee2mqtt.service` gains `After=mosquitto.service` and
  `Requires=mosquitto.service` via `systemd.services` override.
- No new flake inputs are required; `services.mosquitto` is in nixpkgs.

### 3.2 NixOS `services.mosquitto` API reference (nixpkgs 25.05)

```nix
services.mosquitto = {
  enable = true;
  listeners = [
    {
      address = "127.0.0.1";
      port = 1883;
      settings.allow_anonymous = true;
      acl = [ "topic readwrite #" ];
    }
  ];
};
```

`services.mosquitto.listeners` is a list of listener attribute sets.
Each listener accepts:
- `address` — bind address (string)
- `port` — TCP port (int)
- `settings` — attrset of mosquitto.conf directives for that listener
- `acl` — list of ACL rule strings (optional; defaults to `["topic readwrite #"]`)

---

## 4. Exact Changes

### 4.1 Modified file: `modules/server/zigbee2mqtt.nix`

#### Before (full file)

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

#### After (full file)

```nix
# modules/server/zigbee2mqtt.nix
# Zigbee2MQTT — bridges Zigbee devices to MQTT, no proprietary hub required.
# Default frontend port: 8088 (non-standard to avoid conflict with port 8080 services)
# Set serialPort to your Zigbee coordinator device (e.g. /dev/ttyUSB0, /dev/ttyACM0).
# MQTT broker: Mosquitto is auto-enabled on 127.0.0.1:1883 (loopback only, not firewalled).
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
    # Local MQTT broker — bound to loopback only, not exposed through the firewall.
    services.mosquitto = {
      enable = true;
      listeners = [
        {
          address = "127.0.0.1";
          port = 1883;
          settings.allow_anonymous = true;
          acl = [ "topic readwrite #" ];
        }
      ];
    };

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

    # Ensure zigbee2mqtt starts only after Mosquitto is ready.
    systemd.services.zigbee2mqtt = {
      after = [ "mosquitto.service" ];
      requires = [ "mosquitto.service" ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
    # Port 1883 is intentionally NOT opened — Mosquitto is loopback-only.
  };
}
```

---

## 5. Change Summary (diff view)

```diff
-# MQTT broker: this module assumes an MQTT broker is running at localhost:1883.
+# MQTT broker: Mosquitto is auto-enabled on 127.0.0.1:1883 (loopback only, not firewalled).

+    # Local MQTT broker — bound to loopback only, not exposed through the firewall.
+    services.mosquitto = {
+      enable = true;
+      listeners = [
+        {
+          address = "127.0.0.1";
+          port = 1883;
+          settings.allow_anonymous = true;
+          acl = [ "topic readwrite #" ];
+        }
+      ];
+    };
+
+    # Ensure zigbee2mqtt starts only after Mosquitto is ready.
+    systemd.services.zigbee2mqtt = {
+      after = [ "mosquitto.service" ];
+      requires = [ "mosquitto.service" ];
+    };
+
+    networking.firewall.allowedTCPPorts = [ cfg.port ];
+    # Port 1883 is intentionally NOT opened — Mosquitto is loopback-only.
```

---

## 6. Mosquitto Listener Configuration Details

| Setting | Value | Rationale |
|---------|-------|-----------|
| `address` | `127.0.0.1` | Loopback only — no LAN/WAN exposure |
| `port` | `1883` | Default MQTT port; matches zigbee2mqtt hard-coded URL |
| `allow_anonymous` | `true` | Safe because listener is loopback-only |
| `acl` | `["topic readwrite #"]` | Allow all topics — local use only |
| Firewall | NOT opened | Port 1883 stays behind firewall |

The `networking.firewall.allowedTCPPorts` list already present in the module
is NOT modified to add 1883 — only the zigbee2mqtt frontend port (`cfg.port`,
default 8088) remains listed there.

---

## 7. Systemd Dependency Wiring

```nix
systemd.services.zigbee2mqtt = {
  after    = [ "mosquitto.service" ];
  requires = [ "mosquitto.service" ];
};
```

- `after` — ensures ordering: mosquitto is fully started before zigbee2mqtt
  attempts to connect.
- `requires` — if mosquitto stops or fails, zigbee2mqtt is stopped too,
  preventing a reconnect-loop.

NixOS's `services.zigbee2mqtt` module already defines an `after` list
internally (typically `[ "network.target" ]`).  The `systemd.services`
attrset merge appends to those lists rather than replacing them, so no
existing ordering is lost.

---

## 8. No New Flake Inputs

`services.mosquitto` is provided by nixpkgs via the `mosquitto` package.
It has been present in nixpkgs since NixOS 20.09.  No new flake input,
overlay, or pinned package is required.

---

## 9. Implementation Steps

1. Open `modules/server/zigbee2mqtt.nix`.
2. Replace the `# MQTT broker: this module assumes…` comment with the new comment.
3. Inside the `config = lib.mkIf cfg.enable { … }` block, insert the
   `services.mosquitto` attrset immediately before `services.zigbee2mqtt`.
4. After the `services.zigbee2mqtt` block, insert the
   `systemd.services.zigbee2mqtt` override block.
5. Add the inline comment after `networking.firewall.allowedTCPPorts`.
6. Run `nix flake check --impure` to validate.
7. Run `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` (or any server
   variant) to confirm the closure builds without errors.

---

## 10. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Another module also enables `services.mosquitto` on the same host with conflicting listener settings | Low | NixOS will merge the `listeners` lists; two listeners on different ports are fine. If both try to bind 127.0.0.1:1883, NixOS evaluation will error — fix by extracting a shared `mosquitto.nix` at that point. |
| `services.mosquitto` NixOS option shape changes between nixpkgs releases | Very low | `listeners` list API is stable since 22.05; no breaking changes in 25.05. |
| `systemd.services.zigbee2mqtt` override conflicts with the upstream NixOS module's own `after`/`requires` | Very low | Nix attrset merges append to list options; no conflict. |

---

## 11. Files Modified

| File | Change type |
|------|------------|
| `modules/server/zigbee2mqtt.nix` | Modified |

No other files are touched.  No new files are created.
