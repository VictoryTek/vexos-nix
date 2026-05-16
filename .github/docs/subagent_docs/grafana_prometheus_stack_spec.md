# Grafana + Prometheus Stack Spec (Minimal)

## Scope
Resolve the full_code_analysis bug entry:
- Grafana has no auto-provisioned Prometheus datasource.
- Prometheus has no default scrape target.

Target files:
- modules/server/grafana.nix
- modules/server/prometheus.nix

## Current State Analysis

### Repository wiring (server role)
- `configuration-server.nix` and `configuration-headless-server.nix` both import `./modules/server`.
- `modules/server/default.nix` imports `./grafana.nix` and `./prometheus.nix`.
- `flake.nix` conditionally imports `/etc/nixos/server-services.nix` for `server` and `headless-server` via `serverServicesModule`.
- `template/server-services.nix` exposes toggles `vexos.server.grafana.enable` and `vexos.server.prometheus.enable`.

### Exact current behavior when both are enabled
When both toggles are set in `/etc/nixos/server-services.nix`:
1. `modules/server/prometheus.nix` enables Prometheus and sets `services.prometheus.port = 9092`.
2. Prometheus firewall opens only port `9092`.
3. No `services.prometheus.scrapeConfigs` are defined in repo code, so NixOS default applies (`[]`).
4. No `services.prometheus.exporters.node.enable` is set, so node exporter is not enabled.
5. `modules/server/grafana.nix` enables Grafana on `3030` with server settings and opens firewall port `3030`.
6. No `services.grafana.provision.*` datasource config is set, so Grafana starts without an auto-provisioned Prometheus datasource.

Net effect: both services start, but the stack is functionally inert by default (no useful scrape target + no datasource linkage).

## Problem Definition
The current default experience for enabling both services does not produce a usable monitoring stack:
- Prometheus has no target to scrape.
- Grafana has no datasource to query.

This creates a broken first-run experience that conflicts with user expectations implied by enabling both toggles.

## Proposed Solution Architecture
Keep the fix local to the two existing role-specific modules, with no new module files and no new top-level role wiring:

1. In `modules/server/prometheus.nix`:
- Enable node exporter by default when Prometheus is enabled.
- Add a default scrape job named `node` targeting localhost node exporter.

2. In `modules/server/grafana.nix`:
- Auto-provision a Prometheus datasource only when Prometheus toggle is enabled.
- Datasource URL should derive from configured Prometheus port option, not a hardcoded port.

3. Keep user option surface minimal:
- Do not add new `vexos.server.*` options for this fix.
- Reuse existing `vexos.server.prometheus.port` and `vexos.server.grafana.port`.

## Exact Implementation Steps (File-by-File)

### 1) modules/server/prometheus.nix
Current config block:
- Enables `services.prometheus` and sets `port`.

Planned changes:
- Extend Prometheus service config to include:
  - `exporters.node.enable = true;`
  - `scrapeConfigs = [ { job_name = "node"; static_configs = [ { targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ]; } ]; } ];`

Notes:
- Keep node exporter firewall closed by default (`openFirewall` remains default `false`) to avoid exposing it externally.
- Preserve existing Prometheus firewall behavior (`cfg.port` only).

### 2) modules/server/grafana.nix
Current config block:
- Enables Grafana and server settings only.

Planned changes:
- Add conditional datasource provisioning (only when `config.vexos.server.prometheus.enable`):
  - `services.grafana.provision.enable = true;`
  - `services.grafana.provision.datasources.settings = {`
    - `apiVersion = 1;`
    - `datasources = [ {`
      - `name = "Prometheus";`
      - `type = "prometheus";`
      - `access = "proxy";`
      - `url = "http://localhost:${toString config.vexos.server.prometheus.port}";`
      - `editable = false;`
    - `} ];`
  - `};`

Notes:
- Use `access = "proxy"` to match Grafana/NixOS expectation for Prometheus datasource.
- Do not change existing Grafana server port/firewall behavior.

### 3) template/server-services.nix
- No functional change required.
- Existing toggles already sufficient for activation flow.

### 4) Aggregation/wiring files
- No change required in:
  - `modules/server/default.nix`
  - `configuration-server.nix`
  - `configuration-headless-server.nix`
  - `flake.nix`

## Risks and Mitigations

1. Risk: datasource provisioning could conflict with user-managed Grafana provisioning paths.
- Mitigation: keep provisioning block narrowly scoped and only activate when both Grafana and Prometheus toggles are active.

2. Risk: enabling node exporter changes runtime surface area.
- Mitigation: rely on default exporter firewall behavior (`openFirewall = false`) and scrape via localhost.

3. Risk: Prometheus port customization could desync datasource URL.
- Mitigation: derive datasource URL from `config.vexos.server.prometheus.port`.

4. Risk: behavior drift between GUI server and headless-server roles.
- Mitigation: both roles share `modules/server` import and `server-services` flow; no role-specific branching added.

## Validation Plan

1. Static/eval checks:
- `nix flake check --impure`

2. Targeted dry-builds (role coverage):
- `nix build --dry-run --impure .#nixosConfigurations.vexos-server-amd.config.system.build.toplevel`
- `nix build --dry-run --impure .#nixosConfigurations.vexos-headless-server-amd.config.system.build.toplevel`

3. Optional runtime smoke (host with `/etc/nixos/server-services.nix` present):
- Enable both toggles in `/etc/nixos/server-services.nix`.
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- Verify Prometheus target `node` appears up, and Grafana has provisioned `Prometheus` datasource.

## Expected Modified Files
- modules/server/prometheus.nix
- modules/server/grafana.nix

## Sources (Research)
1. Nixpkgs Prometheus module (NixOS options and defaults, including `scrapeConfigs`):
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/monitoring/prometheus/default.nix
2. Nixpkgs Prometheus exporters framework (`openFirewall` default behavior and exporter option model):
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/monitoring/prometheus/exporters.nix
3. Nixpkgs node exporter module (default node exporter port and service wiring):
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/monitoring/prometheus/exporters/node.nix
4. Nixpkgs Grafana module (`services.grafana.provision.datasources.settings` and datasource schema):
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/monitoring/grafana.nix
5. Prometheus official configuration docs (`scrape_config`, `static_configs`):
   - https://prometheus.io/docs/prometheus/latest/configuration/configuration/#scrape_config
6. Prometheus official Node Exporter guide (recommended localhost target `localhost:9100`):
   - https://prometheus.io/docs/guides/node-exporter/
7. Grafana official provisioning docs (datasource provisioning format):
   - https://grafana.com/docs/grafana/latest/administration/provisioning/#data-sources
