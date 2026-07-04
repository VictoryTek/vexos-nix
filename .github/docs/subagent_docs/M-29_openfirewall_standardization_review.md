# M-29 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-29_openfirewall_standardization_spec.md`

## Modified Files

28 `modules/server/*.nix` files, each gaining an `openFirewall` option (default
`true`) gating its `networking.firewall.allowedTCPPorts`/`allowedUDPPorts`
assignment:

`headscale`, `forgejo`, `minio`, `matrix-conduit`, `arcane`, `traefik`, `dozzle`,
`nextcloud`, `caddy`, `attic`, `paperless`, `grafana`, `dockhand`, `stirling-pdf`,
`code-server`, `kavita`, `navidrome`, `portainer`, `photoprism`, `ntfy`, `authelia`,
`nginx-proxy-manager`, `listmonk`, `homepage`, `nginx`, `uptime-kuma`, `unbound`,
`proxmox`.

Additional detail per file:
- `kavita`, `ntfy` — also gained a typed `port` option, replacing a hardcoded
  literal (5000, 2586) threaded through every place it previously appeared.
- `traefik` — combined the new toggle with the pre-existing `insecureDashboard`
  condition on `dashboardPort`.
- `nextcloud` — combined the new toggle with the pre-existing `https` /
  `allowInsecureHttp` conditions on ports 80/443.
- `proxmox` — in addition to gating its own added port (8007), threads
  `cfg.openFirewall` into the upstream `services.proxmox-ve.openFirewall` option
  (discovered during validation — see Review Findings #9) so the toggle actually
  covers all Proxmox ports (8006/111/80/443 + 8007), not just the one this repo's
  wrapper adds directly.
- `syncthing` — **not modified**; already conforms via its own correctly-scoped
  `openGuiFirewall` toggle (see spec's Current State section for why renaming it
  would be misleading).

## Review Findings

1. **Specification Compliance** — matches the spec; the one deviation
   (threading into `services.proxmox-ve.openFirewall`) was discovered during
   Phase 3 validation itself and is a strict improvement over the spec's
   original plan (which would have left `openFirewall = false` only partially
   effective for Proxmox).
2. **Best Practices** — every new option follows the exact existing convention
   (`lib.mkOption { type = lib.types.bool; default = true; description = "..."; }`)
   used by the 23 already-conforming modules; wrapping uses
   `lib.optional`/`lib.optionals`, matching `loki.nix`/`kiji-proxy.nix`.
3. **Consistency** — no new `lib.mkIf` role/display/gaming-flag gating introduced
   (out of scope for Option B rules — these are same-module enable-flag options,
   matching the M-27 carve-out); every module's own port variable(s) are reused
   rather than re-declared.
4. **Maintainability** — operators now have a uniform, discoverable way
   (`vexos.server.<name>.openFirewall`) to opt a service out of automatic firewall
   exposure across all 51 of the 58 server modules that have ports at all
   (23 pre-existing + 28 here; `syncthing` conforms via its own toggle; the
   remainder have no network-facing port to gate).
5. **Completeness** — all 29 modules identified in Phase 1 were addressed (28
   edited, 1 — `syncthing` — confirmed already correct).
6. **Performance** — no runtime cost; `lib.optional`/`lib.optionals` evaluate at
   build time only.
7. **Security** — net improvement: 28 previously always-exposed services
   (several sensitive — code-server, minio console, dockhand/arcane
   root-equivalent Docker access, Proxmox admin) now have an opt-out. No default
   behavior changed (`default = true` everywhere) — this is a strict superset of
   capability, not a behavior change.
8. **API Currency** — n/a, no new external dependency.
9. **Build Validation:**
   - `nix flake show --impure` — passed.
   - Per-target `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`
     for `vexos-desktop-amd`, `-nvidia`, `-vm` — all evaluated cleanly.
   - `vexos-server-amd` / `vexos-headless-server-amd` (server modules touched,
     per Phase 3 rules) — direct `nix eval` hits the pre-existing M-13 hostId
     placeholder assertion (expected on default configs, unrelated to this
     change); verified the actual module evaluates cleanly using
     `extendModules` with a real `hostId` override — succeeded.
   - **Behavioral regression check**: used `extendModules` to enable a
     representative sample (kavita, ntfy, unbound, minio, headscale, traefik,
     nextcloud, proxmox) at `openFirewall`'s default (`true`) and confirmed the
     resulting `networking.firewall.allowedTCPPorts`/`allowedUDPPorts` sets
     exactly match what each service opened before this change (nothing added,
     nothing dropped).
   - **Opt-out verification**: re-ran the same sample with
     `openFirewall = false` (and `insecureDashboard = true` for traefik, to
     prove the dashboard port is also suppressed) — every port from every
     sampled module disappeared, firewall state returned to the pre-service
     baseline. This is what caught the `proxmox` gap: 8006/111/80/443
     initially persisted because the upstream `proxmox-nixos` module manages
     them via its own `services.proxmox-ve.openFirewall` option, independent of
     this repo's wrapper. Fixed by threading `cfg.openFirewall` into it;
     re-verified the full-suppression test again afterward — clean.
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — present, unchanged, in all 6 `configuration-*.nix`
     files. ✓
   - `nixpkgs-fmt --check` on every touched file — flagged 4 files
     (`attic.nix`, `dockhand.nix`, `traefik.nix`, `proxmox.nix`) as needing
     reformatting; diffed each against `nixpkgs-fmt`'s output and confirmed
     every flagged line is pre-existing aligned-`=` style already present
     before this change — none of the newly added `openFirewall` option blocks
     appear in any diff. No new formatting debt introduced.
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs as
     every prior review this session (nixpkgs-fmt formatting backlog,
     `vexboard.nix` placeholder secret string, gitleaks not installed) —
     nothing new.

No CRITICAL issues found. One RECOMMENDED improvement was found and fixed during
this same review cycle (proxmox upstream-module threading) rather than deferred
to a refinement cycle.

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
