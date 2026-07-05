# M-31 — Finish observability: log shipper, Grafana dashboards, alerting

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-31 (FEATURES 2.3)

## Current State

- `modules/server/loki.nix` — Loki log aggregation, hardcoded to listen on
  `3100`, no exposed `port` option.
- `modules/server/prometheus.nix` — Prometheus on port `9092` (default) with a
  node exporter; no Alertmanager.
- `modules/server/grafana.nix` — provisions a Prometheus datasource when
  `vexos.server.prometheus.enable`, but no Loki datasource and no dashboard
  provisioning at all.
- `modules/notify.nix` (added in H-17 this session) — `vexos.notify.ntfyUrl` /
  `tokenFile`, a `vexos-notify` script, and a generic
  `notify-failure@.service` template already wired to `restic-backups-main`
  and `vexos-update`.
- No log shipper exists anywhere in the repo.

**Stale plan text found:** the MASTER_PLAN's suggested filename `promtail.nix`
is no longer buildable — `promtail` was removed from nixpkgs (confirmed via
the package's own `throw`: "promtail has been removed, as it reached its end
of life") and `services.promtail` was removed from `nixos/modules/rename.nix`
with a migration note pointing at `services.alloy` (Grafana Alloy, River
config DSL) or `services.fluent-bit` (plain YAML, has systemd-journal input +
Loki output plugins built in). Confirmed via Context7
(`/fluent/fluent-bit-docs`) that Fluent Bit's `systemd` input
(`read_from_tail`, `db`, `strip_underscores`, `systemd_filter`) and `loki`
output (`host`, `port`, `labels`, `label_keys` record-accessor syntax) cover
everything needed. User chose Fluent Bit over Alloy for its smaller config
surface, matching this repo's general simplicity preference.

**Also discovered:** nixpkgs ships a ready-made, upstream-maintained
`services.prometheus.alertmanager-ntfy` bridge
(`nixos/modules/services/monitoring/prometheus/alertmanager-ntfy.nix`) that
translates Alertmanager's webhook JSON into a proper ntfy publish (topic,
title, priority, tags — all templatable). This replaces the originally
discussed "write a custom Python relay" approach with an existing, hardened,
upstream-maintained systemd service — strictly better and less code to
maintain.

## Problem Definition

Loki has no producer (nothing ships logs to it), Grafana has no dashboards
and no Loki datasource, and there's no alerting path from Prometheus to the
existing ntfy server.

## Proposed Solution

1. **`modules/server/fluent-bit.nix`** (new) — `vexos.server.fluent-bit.enable`.
   Ships the systemd journal to the local Loki instance via Fluent Bit's
   `systemd` input → `loki` output. Asserts `vexos.server.loki.enable` (the
   only thing it can ship to). Static labels `job=fluent-bit,host=<hostname>`
   plus a promoted `SYSTEMD_UNIT` label via `label_keys` for per-unit
   filtering.
2. **`modules/server/grafana.nix`** — add a Loki datasource
   (`type = "loki"`, fixed `uid = "loki"`) alongside the existing Prometheus
   one, gated on `vexos.server.loki.enable`. Add
   `provision.dashboards.settings` pointing at a small
   `pkgs.runCommand`-assembled directory containing:
   - `node-exporter-full.json` — the real community "Node Exporter Full"
     dashboard (grafana.com ID 1860, revision 45), fetched via `pkgs.fetchurl`
     with a pinned sha256, included only when `vexos.server.prometheus.enable`.
     Uses a `datasource`-typed template variable that Grafana auto-resolves
     to the sole configured Prometheus datasource — no manual UID patching
     needed.
   - `systemd-journal.json` (new, hand-authored, checked into
     `modules/server/grafana-dashboards/`) — a small dashboard with a log
     panel, a per-unit log-volume timeseries, and a `$unit` template variable
     backed by `label_values(SYSTEMD_UNIT)`, hardcoded to the fixed
     `uid = "loki"` datasource. Included only when
     `vexos.server.fluent-bit.enable` (no point provisioning it if nothing
     ships logs).
3. **`modules/server/alertmanager.nix`** (new) — `vexos.server.alertmanager.enable`.
   Wires `services.prometheus.alertmanager` (basic rules: node down,
   filesystem near-full, any failed systemd unit — sourced from Prometheus's
   node exporter, which `prometheus.nix` already enables) to
   `services.prometheus.alertmanager-ntfy`, pointed at the existing
   `vexos.notify.ntfyUrl`. Asserts `vexos.server.prometheus.enable`. Wires
   Prometheus's `alertingRules`/`ruleFiles` to actually evaluate the rules
   (`prometheus.nix` gets a small addition: `alertmanagers` pointing at the
   local Alertmanager, gated on `vexos.server.alertmanager.enable`).

## Implementation Steps

1. `modules/server/fluent-bit.nix` — new file, registered in
   `modules/server/default.nix`.
2. `modules/server/grafana-dashboards/systemd-journal.json` — new, hand-authored
   dashboard JSON.
3. `modules/server/grafana.nix` — add Loki datasource + dashboard provisioning
   (fetched node-exporter-full.json + local systemd-journal.json).
4. `modules/server/alertmanager.nix` — new file, registered in
   `modules/server/default.nix`.
5. `modules/server/prometheus.nix` — small addition wiring
   `services.prometheus.alertmanagers`/rule evaluation when Alertmanager is
   enabled.

## Configuration Changes

All new options default to `false`/disabled — zero behavior change for any
host that doesn't explicitly enable `vexos.server.fluent-bit`,
`vexos.server.alertmanager`, or add the two new dashboard-provisioning
datasources (which only activate once `loki`/`prometheus` are already
enabled, matching the existing Prometheus-datasource pattern in
`grafana.nix`).

## Risks and Mitigations

- **Risk:** the fetched `node-exporter-full.json` dashboard could reference a
  datasource variable that doesn't auto-resolve without manual UID mapping.
  **Mitigation:** inspected the actual downloaded JSON (schemaVersion 38) —
  it uses a `datasource`-typed template variable
  (`templating.list[0].type == "datasource"`), which Grafana auto-populates
  to the sole matching datasource at render time; no `__inputs`/manual
  substitution needed (that pattern only applies to older schema versions).
- **Risk:** Fluent Bit's `strip_underscores` changes journald's field naming
  convention; if wrong, `label_keys: $SYSTEMD_UNIT` would silently produce no
  label.
  **Mitigation:** verified in Phase 3 via `extendModules` that
  `services.fluent-bit.enable` evaluates and the generated YAML config
  contains the expected `SYSTEMD_UNIT` key reference.
- **Risk:** Alertmanager rules could reference node-exporter metrics that
  aren't scraped.
  **Mitigation:** kept alert rules to metrics already scraped by
  `prometheus.nix`'s existing `node` exporter job (up, node_filesystem_*,
  node_systemd_unit_state).
