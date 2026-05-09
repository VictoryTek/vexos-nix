# Server Port Conflicts — Review & Quality Assurance

**Feature:** server_port_conflicts
**Date:** 2025-05-09
**Reviewer:** Phase 3 Review
**Verdict:** NEEDS_REFINEMENT

---

## 1. File-by-File Review

### 1.1 `modules/server/unbound.nix` — DNS port 53 → 5353

**Status: PASS**

- Port 5353 correctly set via `settings.server.port = 5353`
- Firewall rules updated: TCP and UDP both set to 5353
- Comment accurately explains the change rationale
- No leftover port 53 references
- Clean Nix syntax, proper `lib.mkIf cfg.enable` guard

### 1.2 `modules/server/caddy.nix` — HTTP/HTTPS 80/443 → 8880/8443

**Status: PASS**

- `httpPort` option: `lib.types.port`, default 8880
- `httpsPort` option: `lib.types.port`, default 8443
- `globalConfig` correctly interpolates: `http_port ${toString cfg.httpPort}` / `https_port ${toString cfg.httpsPort}`
- Firewall uses `[ cfg.httpPort cfg.httpsPort ]`
- Clean Nix syntax, matches spec exactly

### 1.3 `modules/server/nginx.nix` — Added httpPort/httpsPort options (defaults 80/443)

**Status: PASS**

- `httpPort` default 80, `httpsPort` default 443 (unchanged defaults per spec)
- Uses `defaultHTTPListenPort` and `defaultSSLListenPort` (NixOS 25.05+ feature)
- Firewall dynamically references `cfg.httpPort` and `cfg.httpsPort`
- Recommended Nginx settings preserved (gzip, optimisation, proxy, TLS)
- Clean Nix syntax, matches spec exactly

### 1.4 `modules/server/nginx-proxy-manager.nix` — HTTP/HTTPS 80/443 → 8881/8444

**Status: PASS**

- `httpPort` default 8881, `httpsPort` default 8444, `adminPort` default 81
- Container port mapping correct: `"${toString cfg.httpPort}:80"`, `"${toString cfg.httpsPort}:443"`, `"${toString cfg.adminPort}:81"`
- Firewall includes all three ports
- Header comment updated with new port values
- Clean Nix syntax, matches spec exactly

### 1.5 `modules/server/traefik.nix` — web/websecure/dashboard 80→8882, 443→8445, 8080→8079

**Status: CRITICAL ISSUE**

- `httpPort` default 8882, `httpsPort` default 8445, `dashboardPort` default 8079 — options correct
- `web.address` and `websecure.address` correctly use `toString cfg.httpPort` / `cfg.httpsPort`
- Firewall correctly opens all three configured ports

**CRITICAL — Entrypoint name `dashboard` must be `traefik`:**

The implementation defines:
```nix
entryPoints = {
  web.address = ":${toString cfg.httpPort}";
  websecure.address = ":${toString cfg.httpsPort}";
  dashboard.address = ":${toString cfg.dashboardPort}";  # ← BUG
};
```

When `api.insecure = true`, Traefik serves the API/dashboard on a special internal entrypoint named **`traefik`**, which defaults to `:8080`. Defining a custom entrypoint called `dashboard` does NOT redirect the API there. Traefik will:

1. Create the `dashboard` entrypoint on port 8079 (unused by the API)
2. Auto-create the default `traefik` entrypoint on port **8080**
3. Serve the dashboard on port 8080, **not** 8079

**Consequences:**
- Port 8080 conflict with SABnzbd **persists** at runtime
- Port 8079 is opened in the firewall but the dashboard is not served there
- The justfile `status traefik` check (`http://localhost:8079/dashboard/`) will fail

**Fix:** Rename the entrypoint from `dashboard` to `traefik`:
```nix
entryPoints = {
  web.address = ":${toString cfg.httpPort}";
  websecure.address = ":${toString cfg.httpsPort}";
  traefik.address = ":${toString cfg.dashboardPort}";
};
```

> Note: The spec itself contains this bug (Section 5.5). The implementation faithfully follows the spec, but the spec is incorrect.

### 1.6 `modules/server/grafana.nix` — Port 3000 → 3030

**Status: PASS**

- `port` option: `lib.types.port`, default 3030
- `http_port = cfg.port` correctly references the option
- Firewall uses `[ cfg.port ]`
- Comment updated to mention default 3030
- Clean Nix syntax, matches spec exactly

### 1.7 `modules/server/jellyseerr.nix` — Default port 5055 → 5056

**Status: PASS**

- Default changed to 5056
- Uses `services.jellyseerr.port = cfg.port` and `openFirewall = true`
- Comment updated: "Default port: 5056 (Overseerr uses 5057, Seerr uses 5055)"
- Clean Nix syntax, matches spec

### 1.8 `modules/server/overseerr.nix` — Default port 5055 → 5057

**Status: PASS**

- Default changed to 5057
- Uses `services.overseerr.port = cfg.port` and `openFirewall = true`
- Comment updated: "Default port: 5057 (Jellyseerr uses 5056, Seerr uses 5055)"
- Clean Nix syntax, matches spec

### 1.9 `modules/server/scrutiny.nix` — Port 8080 → 8078

**Status: PASS (with INFO note)**

- `port` option added: `lib.types.port`, default 8078
- Port configured via `settings.web.listen.port = cfg.port`
- `openFirewall = true` retained — NixOS scrutiny module should open the correct port based on settings
- Comment updated to mention default 8078
- Clean Nix syntax, matches spec

> INFO: The `openFirewall` behavior depends on the NixOS scrutiny module reading `settings.web.listen.port` for its firewall rule. This is standard NixOS module behavior and should work correctly in nixpkgs 25.05.

### 1.10 `modules/server/stirling-pdf.nix` — Default port 8080 → 8077

**Status: PASS**

- Default changed to 8077
- Container port mapping correct: `"${toString cfg.port}:8080"` (maps host port to container's internal 8080)
- Firewall opens `cfg.port`
- Clean Nix syntax, matches spec

### 1.11 `modules/server/mealie.nix` — Port 9000 → 9010

**Status: PASS**

- `port` option added: `lib.types.port`, default 9010
- `services.mealie.port = cfg.port` correctly references the option
- `listenAddress = "0.0.0.0"` preserved
- Firewall uses `[ cfg.port ]`
- Clean Nix syntax, matches spec exactly

### 1.12 `modules/server/prometheus.nix` — Default port 9090 → 9092

**Status: PASS**

- Default changed to 9092
- `services.prometheus.port = cfg.port`
- Firewall uses `[ cfg.port ]`
- Comment updated to note the conflict avoidance with Cockpit
- Clean Nix syntax, matches spec

### 1.13 `modules/server/headscale.nix` — Metrics 9090 → 9093

**Status: PASS**

- `metrics_listen_addr` changed from `"127.0.0.1:9090"` to `"127.0.0.1:9093"`
- Main HTTP port (8085) unchanged
- Firewall unchanged (metrics is localhost-only)
- Clean Nix syntax, matches spec

> INFO: The module header comment says "Default port: 8080" but the actual default port option is 8085. This is a pre-existing issue, not introduced by this change set.

### 1.14 `justfile` — Updated service-info and status port references

**Status: PASS**

All `service-info` entries verified:

| Service | Expected Port | justfile Port | Match |
|---------|---------------|---------------|-------|
| caddy | 8880, 8443 | `:8880, :8443` | ✅ |
| grafana | 3030 | `:3030` | ✅ |
| jellyseerr | 5056 | `:5056` | ✅ |
| mealie | 9010 | `:9010` | ✅ |
| nginx-proxy-manager | 8881, 8444, 81 | `:8881, :8444`, `:81` | ✅ |
| overseerr | 5057 | `:5057` | ✅ |
| prometheus | 9092 | `:9092` | ✅ |
| scrutiny | 8078 | `:8078` | ✅ |
| stirling-pdf | 8077 | `:8077` | ✅ |
| traefik | 8882, 8445, 8079 | `:8882, :8445`, `:8079` | ✅ |
| unbound | 5353 | `:5353` | ✅ |
| nginx | 80, 443 | `:80, :443` | ✅ |

All `status` entries verified:

| Service | Expected URL | justfile URL | Match |
|---------|-------------|-------------|-------|
| caddy | localhost:8880 | `http://localhost:8880` | ✅ |
| grafana | localhost:3030 | `http://localhost:3030` | ✅ |
| jellyseerr | localhost:5056 | `http://localhost:5056` | ✅ |
| mealie | localhost:9010 | `http://localhost:9010` | ✅ |
| overseerr | localhost:5057 | `http://localhost:5057` | ✅ |
| prometheus | localhost:9092 | `http://localhost:9092` | ✅ |
| scrutiny | localhost:8078 | `http://localhost:8078` | ✅ |
| stirling-pdf | localhost:8077 | `http://localhost:8077` | ✅ |
| traefik | localhost:8079 | `http://localhost:8079/dashboard/` | ✅ (but see traefik CRITICAL) |

> Note: The traefik status URL (`http://localhost:8079/dashboard/`) will fail at runtime due to the entrypoint naming bug in traefik.nix (see §1.5).

---

## 2. Issues Found

### CRITICAL

| # | File | Issue | Impact |
|---|------|-------|--------|
| C1 | `modules/server/traefik.nix` | Dashboard entrypoint named `dashboard` instead of `traefik`. Traefik's `api.insecure = true` serves the API on the internal `traefik` entrypoint (default `:8080`). A custom-named entrypoint does not redirect it. Port 8080 conflict with SABnzbd persists; dashboard unreachable on 8079. | Port conflict remains at runtime; dashboard served on wrong port |

### RECOMMENDED

| # | File | Issue | Impact |
|---|------|-------|--------|
| R1 | `template/server-services.nix` | Not updated — contains ~12 stale port references in comments. Examples: caddy says "Ports 80/443" (should be 8880/8443), grafana says "Port 3000" (should be 3030), scrutiny says "Port 8080" (should be 8078), mealie says "Port 9000" (should be 9010), prometheus says "Port 9090 (⚠ conflicts with cockpit)" (should be 9092, no longer conflicts), overseerr/jellyseerr say "Port 5055" (should be 5057/5056), traefik says "80/443 + 8080" (should be 8882/8445 + 8079), NPM says "80/443" (should be 8881/8444), unbound conflict warning is now obsolete (port 5353 ≠ 53) | Users see incorrect port numbers in the service toggle template; confusing but not functional breakage |
| R2 | `modules/server/minio.nix` | Stale conflict warnings — file comment says "⚠ conflicts with Mealie" and option description says "⚠ Conflicts with Mealie on port 9000", but Mealie has moved to port 9010. No conflict remains. | Misleading documentation |

### INFO

| # | File | Issue |
|---|------|-------|
| I1 | `modules/server/headscale.nix` | Header comment says "Default port: 8080" but actual default is 8085. Pre-existing issue. |
| I2 | `modules/server/scrutiny.nix` | `openFirewall = true` relies on NixOS module reading `settings.web.listen.port` for firewall rules. Expected to work correctly in nixpkgs 25.05 but worth verifying against module source. |
| I3 | `server_port_conflicts_spec.md` §5.5 | The spec itself contains the Traefik entrypoint naming bug. Spec should be corrected alongside the implementation fix. |

---

## 3. Cross-Service Port Uniqueness Verification

Verified the complete post-change port map from spec §9 against all module implementations. **All ports are unique** — with the exception of the Traefik CRITICAL bug (C1), which causes port 8080 to remain occupied by both SABnzbd and Traefik's auto-created `traefik` entrypoint.

After fixing C1, the full port map will have zero conflicts.

---

## 4. Architecture Compliance

All 14 modified files follow the project's **Option B: Common base + role additions** pattern:

- ✅ Each module uses `lib.mkIf cfg.enable` — per-service toggle, not a role gate
- ✅ Options declared under `vexos.server.<service>.*`
- ✅ Port options use `lib.types.port`
- ✅ No `lib.mkIf` guards gating by role, display flag, or gaming flag
- ✅ Consistent `cfg = config.vexos.server.<service>` pattern throughout

---

## 5. Build Validation

Build commands not executed (no sudo access per review instructions). Code-level analysis:

- ✅ All Nix syntax is valid (proper attribute sets, string interpolation, option declarations)
- ✅ All `lib.mkOption` / `lib.mkEnableOption` / `lib.mkIf` usage is correct
- ✅ All `toString` calls applied where integers are interpolated into strings
- ✅ No missing semicolons, unbalanced braces, or import errors detected
- ⚠️ Runtime behavior for Traefik will cause port 8080 conflict (C1)

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 98% | A+ |
| Best Practices | 88% | B+ |
| Functionality | 82% | B |
| Code Quality | 93% | A |
| Security | 95% | A |
| Performance | 98% | A+ |
| Consistency | 88% | B+ |
| Build Success | 88% | B+ |

**Overall: 91% (A-) — NEEDS_REFINEMENT**

**Rationale:** The implementation faithfully follows the spec across 13 of 14 files. Code quality, syntax, and architectural compliance are strong. However, CRITICAL issue C1 (Traefik entrypoint naming) means the port 8080 conflict persists at runtime, which defeats the primary purpose of this change set. Additionally, the `template/server-services.nix` file (R1) was not included in the modified file list but contains ~12 stale port comments that should be updated for user clarity.

---

## 7. Required Actions Before PASS

1. **[CRITICAL C1]** In `modules/server/traefik.nix`, rename entrypoint `dashboard` to `traefik`:
   ```nix
   entryPoints = {
     web.address = ":${toString cfg.httpPort}";
     websecure.address = ":${toString cfg.httpsPort}";
     traefik.address = ":${toString cfg.dashboardPort}";
   };
   ```

2. **[RECOMMENDED R1]** Update `template/server-services.nix` with corrected port numbers in all comments.

3. **[RECOMMENDED R2]** Remove stale "⚠ conflicts with Mealie" warnings from `modules/server/minio.nix` (file comment line 3 and option description line 19).

4. **[INFO I3]** Correct the spec document (`server_port_conflicts_spec.md` §5.5) to use `traefik` instead of `dashboard` as the entrypoint name.
