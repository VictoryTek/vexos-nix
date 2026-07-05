# M-33 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-33_caddy_proxy_spec.md`

**Process note:** implementation was committed locally (not pushed) before
this Phase 3 review ran. Verified via `git log origin/main..HEAD` that the
commit exists locally only, so this review is happening in the normal
pre-push position for this one.

## Modified Files

- `modules/server/proxy.nix` (new) — `vexos.server.proxy.enable`, ~45-entry
  service table, generates `services.caddy.virtualHosts` entries for every
  currently-enabled service.
- `modules/server/default.nix` — registered the new module.

## Review Findings

1. **Specification Compliance** — matches the spec exactly, including the
   user-confirmed scope decision to exclude Avahi/mDNS publication entirely.
2. **Best Practices** — attaches to the existing `caddy.nix` instance (via
   an unconditional assertion) rather than starting a second Caddy service;
   follows `caddy.nix`'s own documented example
   (`services.caddy.virtualHosts."jellyfin.local".extraConfig = "reverse_proxy ..."`)
   almost verbatim, just generated instead of hand-written.
3. **Consistency** — every port value was cross-checked against its actual
   source (vexos wrapper option default, or upstream NixOS module default
   for the six services — `jellyfin`, `plex`, `tautulli`, `home-assistant`,
   `node-red`, `komga` — that don't expose a vexos-level port option) rather
   than assumed from memory.
4. **Maintainability** — the file's own header comment documents the
   hand-maintained-table tradeoff explicitly (a new server module needs a
   one-line addition here), so a future contributor isn't surprised by the
   drift risk.
5. **Completeness** — covers effectively every server module with a genuine
   browser-facing web UI; explicitly excludes reverse-proxy/infra modules
   (`caddy`, `nginx`, `traefik`, `nginx-proxy-manager`, `unbound`) and
   non-HTTP services (`matrix-conduit`, `papermc`, `rustdesk`) with reasoning
   documented in the spec.
6. **Performance** — n/a, static config generation only.
7. **Security** — no new firewall ports (reuses `caddy.nix`'s existing
   `httpPort`/`httpsPort`); Caddy's automatic internal-CA behavior for
   non-public hostnames means `.local` names get real (if self-signed) TLS
   rather than plaintext HTTP.
8. **API Currency** — n/a, no external dependency; Caddy's non-public-hostname
   TLS behavior is existing, stable Caddy behavior already implicitly relied
   on by `caddy.nix`'s own pre-existing example comment.
9. **Build Validation:**
   - `nix flake show --impure` — passed.
   - **Integration check** via `extendModules`: enabled `caddy`, `proxy`,
     `jellyfin`, `grafana`, `arr` (+ `qbittorrent`/`bazarr` sub-toggles), and
     `minio` together on `vexos-server-amd`. Resulting
     `services.caddy.virtualHosts` contained exactly the 10 expected
     entries (`bazarr.vexos.local` → `6767`, `grafana.vexos.local` → `3030`,
     `jellyfin.vexos.local` → `8096`, `lidarr`/`radarr`/`prowlarr`/`sonarr`
     → their arr-stack ports, `minio.vexos.local` → `9001` (console port,
     not the API port — correct per the table), `qbittorrent.vexos.local`
     → `8081`, `sabnzbd.vexos.local` → `8080`) — every disabled service
     correctly absent from the output.
   - **Assertion check**: enabled `proxy.enable` without `caddy.enable` —
     evaluation correctly fails with the expected assertion message.
   - Per-target `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`
     for `vexos-desktop-amd`, `-nvidia`, `-vm` — evaluated cleanly.
   - `vexos-server-amd` / `vexos-headless-server-amd` (server module
     touched) — evaluated cleanly via `extendModules` with a real `hostId`.
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs
     as every prior review this session — nothing new.

No CRITICAL or RECOMMENDED issues found.

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Returns

- Build result: PASS
- **PASS**
