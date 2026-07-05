# M-32 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-32_arr_qbittorrent_bazarr_spec.md`

## Modified Files

- `modules/server/arr.nix` — added `qbittorrent.enable` / `bazarr.enable`
  nested options, wired `services.qbittorrent` (webuiPort 8081, torrentingPort
  6881, openFirewall) and `services.bazarr` (openFirewall), extended
  `extraGroups`, added two unconditional prerequisite assertions.

## Review Findings

1. **Specification Compliance** — matches the spec exactly: both options
   nested under `vexos.server.arr` as the MASTER_PLAN's exact requested
   paths, qBittorrent's port conflict resolved, torrenting port fixed rather
   than left `null`.
2. **Best Practices** — assertions placed outside the `lib.mkIf cfg.enable`
   block (via `lib.mkMerge`) so they actually fire when a sub-toggle is set
   without the parent — verified this catches the case in Phase 3, not just
   assumed.
3. **Consistency** — matches the existing per-service `openFirewall = true`
   inline-comment-port style already used for the other five services in
   this same file; sub-toggle nesting pattern doesn't introduce a new
   abstraction, just extends the existing options set.
4. **Maintainability** — the port-shift rationale (8080 → 8081) and the
   torrentingPort fix are both documented inline, matching this repo's
   existing convention (e.g. `dockhand.nix`'s own port-shift comment) for
   explaining non-obvious port choices.
5. **Completeness** — both services requested by the plan are present, each
   individually toggle-able, each correctly firewalled.
6. **Performance** — n/a.
7. **Security** — no new secrets; qBittorrent gets its own service user via
   the upstream module's defaults, same as every other arr-stack service.
8. **API Currency** — verified both `services.qbittorrent` and
   `services.bazarr` option names/defaults directly against nixpkgs source
   rather than assuming from memory — this is what surfaced the
   `webuiPort` collision and the `torrentingPort = null` default.
9. **Build Validation:**
   - `nix flake show --impure` — passed.
   - **Integration check** via `extendModules`: enabled `arr`, `qbittorrent`,
     and `bazarr` together on `vexos-server-amd` — confirmed
     `webuiPort = 8081`, `torrentingPort = 6881`, `bazarr.listenPort = 6767`,
     all three (plus qbittorrent's torrenting port) present in
     `networking.firewall.allowedTCPPorts`, both `qbittorrent`/`bazarr`
     present in the primary user's `extraGroups`, and the whole
     configuration still evaluates to a real `system.build.toplevel`
     derivation.
   - **Assertion check**: enabled `qbittorrent.enable` without
     `arr.enable` — evaluation correctly fails with the expected assertion
     message.
   - Per-target `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`
     for `vexos-desktop-amd`, `-nvidia`, `-vm` — evaluated cleanly.
   - `vexos-server-amd` / `vexos-headless-server-amd` (server module
     touched) — evaluated cleanly via `extendModules` with a real `hostId`.
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs
     as every prior review this session — nothing new. (A pre-existing,
     unrelated `sabnzbd.configFile` deprecation warning surfaced during the
     `extendModules` integration check — not introduced by this change,
     out of scope.)

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
