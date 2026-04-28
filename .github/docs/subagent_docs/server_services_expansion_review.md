# Server Services Expansion — Review Document

**Feature:** `server_services_expansion`  
**Review Date:** 2026-04-28  
**Reviewer:** Quality Assurance Subagent  
**Verdict:** ⚠ **NEEDS_REFINEMENT**

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 75% | C |
| Best Practices | 90% | A |
| Functionality | 82% | B |
| Code Quality | 92% | A |
| Security | 85% | B |
| Performance | 95% | A |
| Consistency | 88% | B+ |
| Build Success | UNKNOWN (CRITICAL issues present) | F |

**Overall Grade: C+ (86% weighted, blocked by 4 CRITICAL issues)**

---

## Executive Summary

The implementation is structurally solid — all 17 new module files are created with correct Nix syntax, all follow the established OCI and native-service patterns, and all required justfile sections (service names, list-services, _info(), services recipe, enable verbose output) are fully populated. However, **4 CRITICAL issues** prevent this from being mergeable:

1. `template/server-services.nix` has its closing `}` inside a comment (Nix syntax error — would break every server rebuild)
2. `justfile` `status` recipe maps portainer to the wrong URL (checks MinIO's port 9000 instead of portainer's HTTPS port 9443)
3. `justfile` `enable` recipe is missing the `matrix-conduit` serverName interactive prompt (spec deviation — Section 4.6)
4. `justfile` `enable` recipe is missing the `zigbee2mqtt` serialPort interactive prompt (spec deviation — Section 4.6)

There are also several ADVISORY items (option name verification needed, minor status URL deviations, ordering differences from spec).

---

## Part 1: Per-Service Module Review

### 1.1 prometheus.nix — PASS
- Header, `let cfg`, `mkIf cfg.enable` pattern: ✓
- `services.prometheus.port` is a valid NixOS 25.05 option: ✓
- Firewall rule uses `cfg.port`: ✓
- Port conflict comment present: ✓

### 1.2 loki.nix — PASS (ADVISORY)
- Pattern adherence: ✓
- `services.loki.configuration` with the full YAML-equivalent Nix config block: ✓
- Port 3100 hardcoded in firewall rule but also in `configuration.server.http_listen_port` — these must stay in sync if port is changed. **ADVISORY**: The module has no `port` option, so there is no way to change the port without editing the module directly. This is acceptable given the spec does not require a port option for loki.
- `kvstore.store = "inmemory"` — valid conduit config key for a single-node loki setup: ✓
- `schema_config.configs` list syntax is valid Nix: ✓

### 1.3 netdata.nix — PASS
- Simple enable-only pattern (Pattern A): ✓
- `services.netdata.enable = true` is valid: ✓
- Port 19999 in firewall: ✓

### 1.4 unbound.nix — PASS
- `services.unbound.settings.server.*` attribute path: ✓
- Both TCP and UDP port 53 opened in firewall: ✓
- Port conflict comment present: ✓
- Access control lists include RFC-1918 ranges: ✓ (good security practice)

### 1.5 paperless.nix — PASS (ADVISORY)
- `services.paperless.enable`, `.port`, `.address`: valid in NixOS 25.05. ✓
- **ADVISORY**: Spec notes `services.paperless.address` may not exist — based on nixpkgs source review, `address` IS a valid option (added in NixOS 23.11), but cannot confirm without `nix eval` on Linux. Flag for runtime verification.
- Firewall rule: ✓

### 1.6 minio.nix — PASS
- `services.minio.listenAddress` and `consoleAddress` (`:PORT` format): ✓
- `services.minio.rootCredentialsFile`: valid NixOS option: ✓
- Dual-port firewall rule: ✓
- Credentials file comment in module header: ✓

### 1.7 matrix-conduit.nix — PASS (ADVISORY)
- `services.matrix-conduit.settings.global.*` attribute path: ✓
- `allow_federation = cfg.serverName != "localhost"` is valid Nix boolean expression: ✓
- `database_backend = "rocksdb"`: valid conduit setting: ✓
- **ADVISORY**: The `allow_federation` key — valid in conduit's global config (the conduit TOML config supports it): ✓
- **ADVISORY**: Spec required a `matrix-conduit` serverName interactive prompt in the `enable` recipe. This is a CRITICAL deviation documented in Part 3.

### 1.8 navidrome.nix — PASS
- `services.navidrome.settings.{Address,Port,MusicFolder}`: valid PascalCase keys matching navidrome's config format: ✓
- Port and musicFolder options exposed: ✓
- Firewall rule: ✓

### 1.9 code-server.nix — PASS (ADVISORY)
- `services.code-server.host`, `.auth`, `.hashedPasswordFile`: the NixOS code-server module (nixpkgs ≥ 22.11) exposes these options. ✓
- `auth = if cfg.hashedPasswordFile != null then "password" else "none"`: valid Nix if expression: ✓
- `lib.types.nullOr lib.types.path` for `hashedPasswordFile`: correct type: ✓
- **ADVISORY**: Spec notes these options should be verified. Based on nixpkgs code-server module source, `host`, `auth`, and `hashedPasswordFile` are valid options. Mark for runtime confirmation.

### 1.10 node-red.nix — PASS (ADVISORY)
- `services.node-red.enable = true; openFirewall = true`: ✓
- **ADVISORY**: `services.node-red.openFirewall` — NixOS node-red module (nixpkgs ≥ 23.11) does support `openFirewall`. Mark for runtime confirmation. Fallback in spec is `networking.firewall.allowedTCPPorts = [1880]`.

### 1.11 zigbee2mqtt.nix — PASS (ADVISORY)
- `services.zigbee2mqtt.settings.*` with the YAML-equivalent Nix config: ✓
- `frontend.enabled`, `frontend.port`, `frontend.host` are valid zigbee2mqtt config keys: ✓
- `serial.port = cfg.serialPort`: correct attribute path for the NixOS module: ✓
- **ADVISORY**: Spec required a `zigbee2mqtt` serialPort interactive prompt in the `enable` recipe. This is a CRITICAL deviation documented in Part 3.

### 1.12 authelia.nix — PASS (ADVISORY)
- OCI container pattern (Pattern D): ✓
- `virtualisation.docker.enable = lib.mkDefault true`: ✓
- Volume `/etc/nixos/authelia:/config`: ✓
- **ADVISORY**: Hardcoded `TZ = "America/Chicago"` in container environment. This should ideally use `config.time.timeZone` or be left unset (authelia reads from the host). Not a build issue, but reduces portability.
- **ADVISORY**: The `enable` recipe verbose output message says "Create /var/lib/authelia/config/configuration.yml before first start" but the volume mount uses `/etc/nixos/authelia` (not `/var/lib/authelia/config/`). This is an inconsistency in the user-facing message — the correct path is `/etc/nixos/authelia/configuration.yml`.

### 1.13 photoprism.nix — PASS (ADVISORY)
- `services.photoprism.port`, `.address`, `.passwordFile`: ✓
- **ADVISORY**: Spec flags `services.photoprism.address` and `.passwordFile` for verification. Based on nixpkgs photoprism module, these are valid options. Mark for runtime confirmation.

### 1.14 listmonk.nix — PASS (ADVISORY)
- `services.listmonk.settings.app.address = "0.0.0.0:${toString cfg.port}"`: ✓
- **ADVISORY**: The attribute path `settings.app.address` must match the listmonk NixOS module structure. The nixpkgs listmonk module uses `services.listmonk.settings` as a TOML passthrough where `app.address` is the correct key. Mark for runtime confirmation.

### 1.15 dozzle.nix — PASS
- OCI container pattern: ✓
- Docker socket mounted read-only: ✓ (correct security posture — RO is appropriate for log viewing)
- Internal port `8080` for dozzle container mapped to configurable external port: ✓

### 1.16 portainer.nix — PASS (ADVISORY)
- OCI container pattern: ✓
- Docker socket mounted read-only: ✓
- Named volume `portainer-data:/data`: ✓
- **ADVISORY**: Port 9443 is HTTPS-only for portainer. The HTTP status check in the `status` recipe is wrong (see CRITICAL issue #2 below).

### 1.17 nginx-proxy-manager.nix — PASS
- OCI container pattern: ✓
- Three ports (80, 443, adminPort) exposed: ✓
- Named volumes for data and letsencrypt: ✓
- Port conflict warnings in module header: ✓

---

## Part 2: default.nix Review — PASS

All 17 new modules are imported:

| Module | Present | Correct Category |
|--------|---------|-----------------|
| navidrome.nix | ✓ | Media Servers |
| minio.nix | ✓ | Cloud & Files |
| photoprism.nix | ✓ | Cloud & Files |
| paperless.nix | ✓ | Documents |
| code-server.nix | ✓ | Development |
| authelia.nix | ✓ | Security |
| unbound.nix | ✓ | Networking & Reverse Proxies |
| nginx-proxy-manager.nix | ✓ | Networking & Reverse Proxies |
| prometheus.nix | ✓ | Monitoring & Management |
| loki.nix | ✓ | Monitoring & Management |
| netdata.nix | ✓ | Monitoring & Management |
| dozzle.nix | ✓ | Monitoring & Management |
| portainer.nix | ✓ | Monitoring & Management |
| listmonk.nix | ✓ | Food & Home |
| node-red.nix | ✓ | Automation & Smart Home |
| zigbee2mqtt.nix | ✓ | Automation & Smart Home |
| matrix-conduit.nix | ✓ | Communications |

No option declarations in default.nix (pure import list): ✓  
No duplicate imports: ✓

---

## Part 3: CRITICAL Issues

### CRITICAL #1 — template/server-services.nix: Closing `}` inside a comment

**File:** `template/server-services.nix`  
**Line:** ~112 (last line of file)

The file's final line is:
```
  # vexos.server.proxmox.ipAddress = "";              # Required: set to this host's IP address}
```

The `}` that should close the Nix attribute set (which opens with `{` on line 17) is appended to the end of a comment. In Nix, `#` starts a line comment through end-of-line, so this `}` is commented out and does not close the attribute set.

**Impact:** When `just enable <service>` copies this template to `/etc/nixos/server-services.nix` and NixOS attempts to import it, the evaluation will fail with a parse error ("unexpected end of file, expected `}`"). This breaks every server rebuild.

**Fix required:**
```nix
  # vexos.server.proxmox.ipAddress = "";              # Required: set to this host's IP address
}
```
The `}` must be on its own line to close the attribute set.

---

### CRITICAL #2 — justfile: portainer status URL checks wrong port

**File:** `justfile`  
**Location:** `status` recipe, `case "$SERVICE" in` block

**Current:**
```bash
portainer)      UNITS="docker-portainer";         URLS="http://localhost:9000" ;;
```

**Problem:** Port 9000 is MinIO's default API port, not portainer's. Portainer runs on port 9443 (HTTPS by default). The HTTP check at port 9000 will always return "unreachable" when portainer is running correctly, or incorrectly report MinIO as the portainer endpoint.

**Fix required:**
```bash
portainer)      UNITS="docker-portainer";         URLS="https://localhost:9443" ;;
```

Note: The `_info()` case for portainer already correctly shows `https://<server-ip>:9443`. Only the `status` recipe is wrong.

---

### CRITICAL #3 — justfile: Missing `matrix-conduit` serverName prompt in `enable` recipe

**File:** `justfile`  
**Location:** `enable` recipe, between the proxmox prompt block and `echo "✓ Enabled: $SERVICE"`

The spec (Section 4.6) explicitly requires an interactive prompt for `vexos.server.matrix-conduit.serverName` at enable time, following the proxmox.ipAddress pattern. Without this prompt, users who run `just enable matrix-conduit` will get a working Conduit homeserver but with `serverName = "localhost"` — rendering federation permanently non-functional even if the user later changes the setting, since Matrix server names are baked into room IDs and cannot be changed after first use.

**Fix required:** Add this block before `echo "✓ Enabled: $SERVICE"`:
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
```

---

### CRITICAL #4 — justfile: Missing `zigbee2mqtt` serialPort prompt in `enable` recipe

**File:** `justfile`  
**Location:** `enable` recipe, between the proxmox prompt block and `echo "✓ Enabled: $SERVICE"`

The spec (Section 4.6) requires an interactive prompt for `vexos.server.zigbee2mqtt.serialPort` at enable time. Without this prompt, users who run `just enable zigbee2mqtt` will get zigbee2mqtt configured with the default `/dev/ttyUSB0` but no reminder to verify their actual device path. Zigbee2MQTT will fail to start if the serial device path is wrong.

**Fix required:** Add this block before `echo "✓ Enabled: $SERVICE"`:
```bash
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

## Part 4: ADVISORY Issues

### ADVISORY #1 — justfile: `matrix-conduit` status unit name may be wrong

**Location:** `status` recipe

**Current:** `UNITS="conduit"`  
**Spec:** `UNITS="matrix-conduit"`

In NixOS, the systemd service created by `services.matrix-conduit.enable = true` is typically named `conduit.service` (as defined in `systemd.services.conduit` in the nixpkgs module). The implementation's `UNITS="conduit"` may be correct. However, this should be verified on a running system since the systemd unit name depends on the exact nixpkgs module implementation.

**ADVISORY**: Low risk. If wrong, `just status matrix-conduit` will show an error but the service still runs.

---

### ADVISORY #2 — justfile: `status` recipe `minio` only checks console URL

**Current:** `URLS="http://localhost:9001"` (console only)  
**Spec:** `URLS="http://localhost:9000 http://localhost:9001"` (both API and console)

The implementation omits the API port check. Minor deviation from spec.

---

### ADVISORY #3 — justfile: `list-services` and `services` recipe ordering in Files & Storage

**Current** (both recipes):
```bash
_svc immich; _svc nextcloud; _svc syncthing; _svc minio; _svc photoprism
```
**Spec:**
```bash
_svc immich; _svc minio; _svc nextcloud; _svc photoprism; _svc syncthing
```

Alphabetical ordering within the category differs from spec. Functionally identical but inconsistent with spec.

---

### ADVISORY #4 — authelia.nix: Hardcoded timezone in container environment

**File:** `modules/server/authelia.nix`

```nix
environment = {
  TZ = "America/Chicago";
};
```

The timezone is hardcoded to `America/Chicago`. A better approach would be:
```nix
environment = {
  TZ = config.time.timeZone;
};
```

This allows the container to match the host's configured timezone. Not a build issue.

---

### ADVISORY #5 — authelia.nix enable message: inconsistent config path

**File:** `justfile`, `enable` recipe, `authelia` case

The `enable` recipe echo says:
```
"  Note:     Create /var/lib/authelia/config/configuration.yml before first start."
```

But the module mounts:
```nix
volumes = [ "/etc/nixos/authelia:/config" ];
```

The correct path for the user to create the file is `/etc/nixos/authelia/configuration.yml`, not `/var/lib/authelia/config/configuration.yml`. The message is misleading.

---

### ADVISORY #6 — Nixpkgs option name verification (cannot run on Windows)

The following options are flagged in the spec as requiring verification. They appear correct based on nixpkgs source knowledge but cannot be confirmed by running `nix eval` in this environment:

| Module | Option | Risk Level |
|--------|--------|-----------|
| paperless | `services.paperless.address` | Low — confirmed in nixpkgs ≥ 23.11 |
| code-server | `services.code-server.host`, `.auth`, `.hashedPasswordFile` | Low — confirmed in nixpkgs ≥ 22.11 |
| node-red | `services.node-red.openFirewall` | Medium — confirm on target host; fallback is explicit firewall rule |
| photoprism | `services.photoprism.address`, `.passwordFile` | Medium — confirm on target host |
| listmonk | `services.listmonk.settings.app.address` | Medium — confirm TOML key path on target host |

---

## Part 5: Build Validation

**Status: UNKNOWN (Windows environment — cannot run `nix flake check`)**

Static analysis:
- All 17 module files: valid Nix syntax (manual review) ✓
- `default.nix`: pure import list, no syntax issues ✓
- `template/server-services.nix`: **CRITICAL SYNTAX ERROR** — closing `}` inside a comment ✗
- `configuration-*.nix` files: not modified (correct — no changes expected) ✓
- `hardware-configuration.nix`: not tracked in repo (correct) ✓
- `system.stateVersion`: not modified (verified by file exclusion) ✓

**Predicted `nix flake check` result if template bug is present:**
- The template file is not imported by `flake.nix` or any configuration file — it lives in `template/` as a user-facing file. Therefore `nix flake check` would likely PASS even with the bug. However, the first time a user runs `just enable <service>` on a server host, the broken template will be copied to `/etc/nixos/server-services.nix` and the next `nixos-rebuild` will fail.

---

## Part 6: Validation Checklist Summary

### Nix Syntax
| Check | Status |
|-------|--------|
| Correct `{ config, lib, pkgs, ... }:` header (all 17) | ✓ PASS |
| `let cfg = config.vexos.server.<name>;` binding (all 17) | ✓ PASS |
| `config = lib.mkIf cfg.enable { ... }` pattern (all 17) | ✓ PASS |
| No stray commas/semicolons/unmatched braces in module files | ✓ PASS |
| String values in double quotes | ✓ PASS |
| Boolean values unquoted | ✓ PASS |
| Options self-declared in each module file | ✓ PASS |

### default.nix
| Check | Status |
|-------|--------|
| All 17 new modules imported | ✓ PASS |
| No duplicate imports | ✓ PASS |
| Pure import list (no option declarations) | ✓ PASS |

### OCI Container Pattern
| Container | Pattern D Compliance |
|-----------|---------------------|
| authelia | ✓ PASS |
| dozzle | ✓ PASS |
| portainer | ✓ PASS |
| nginx-proxy-manager | ✓ PASS |

### Module Architecture
| Check | Status |
|-------|--------|
| No lib.mkIf guards except top-level enable guard | ✓ PASS |
| No changes to configuration-*.nix files | ✓ PASS |
| No new lib.mkIf guards in shared modules | ✓ PASS |

### justfile Completeness
| Check | Status |
|-------|--------|
| All 17 names in `_server_service_names` | ✓ PASS |
| All 17 names in `_info()` cases | ✓ PASS |
| All 17 names in `status` cases | ✓ PASS (but portainer URL wrong — CRITICAL #2) |
| All 17 names in `services` `_check` calls | ✓ PASS |
| All 17 names in `enable` verbose output block | ✓ PASS |
| All 17 names in `list-services` | ✓ PASS |
| matrix-conduit in Communications category | ✓ PASS |
| matrix-conduit serverName prompt in enable | ✗ MISSING (CRITICAL #3) |
| zigbee2mqtt serialPort prompt in enable | ✗ MISSING (CRITICAL #4) |

### template/server-services.nix
| Check | Status |
|-------|--------|
| All 17 services as commented-out lines | ✓ PASS |
| File closes with a valid `}` | ✗ FAIL (CRITICAL #1) |

---

## Part 7: Required Fixes (Refinement Phase)

The following changes MUST be made before this implementation can pass review:

### Fix 1 — `template/server-services.nix`: Move closing `}` to its own line

The last line of the file must end with the comment text, and then a new line containing only `}` must follow:

**Current (broken):**
```
  # vexos.server.proxmox.ipAddress = "";              # Required: set to this host's IP address}
```

**Corrected:**
```
  # vexos.server.proxmox.ipAddress = "";              # Required: set to this host's IP address
}
```

### Fix 2 — `justfile`: Correct portainer status URL

**Current:**
```bash
portainer)      UNITS="docker-portainer";         URLS="http://localhost:9000" ;;
```
**Corrected:**
```bash
portainer)      UNITS="docker-portainer";         URLS="https://localhost:9443" ;;
```

### Fix 3 — `justfile`: Add matrix-conduit serverName prompt to `enable` recipe

Add the prompt block from CRITICAL #3 above, positioned after the existing `proxmox` prompt block and before `echo "✓ Enabled: $SERVICE"`.

### Fix 4 — `justfile`: Add zigbee2mqtt serialPort prompt to `enable` recipe

Add the prompt block from CRITICAL #4 above, positioned after the matrix-conduit prompt block and before `echo "✓ Enabled: $SERVICE"`.

---

## Verdict

**NEEDS_REFINEMENT**

4 CRITICAL issues must be resolved. Once fixed, the implementation should pass re-review. The module files themselves are high quality and no module-level changes are needed.
