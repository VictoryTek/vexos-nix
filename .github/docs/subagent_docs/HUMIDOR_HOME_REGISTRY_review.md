# humidor + home-registry server modules — Review

## Scope reviewed

- `modules/server/humidor.nix` (new)
- `modules/server/home-registry.nix` (new)
- `modules/server/default.nix` (2 new imports)
- `justfile` (6 edits: `_server_service_names`, `_service_catalog`, info-line
  case block, systemd-unit case block, quick-open URL case block, detailed
  `info` case block)
- `template/server-services.nix` (2 new commented toggle blocks + header list)
- `.github/docs/subagent_docs/HUMIDOR_HOME_REGISTRY_upstream_notes.md` (new)

Against spec: `.github/docs/subagent_docs/HUMIDOR_HOME_REGISTRY_spec.md`.

## Build validation — environment note

This machine has no `nix` on Windows PATH and is not a NixOS host, so
`sudo nixos-rebuild dry-build` cannot run here at all (no
`/etc/nixos/vexos-variant`, confirmed by `scripts/preflight.sh` stage
`[2/8]` itself reporting `WARN: Skipping dry-build`). Per this repo's own
documented CI-equivalent stand-in, validation was done via WSL Ubuntu's
Nix 2.34.1 using `nix eval --impure` to force
`config.system.build.toplevel.drvPath` for each required target — this
performs full module evaluation (catches option-type errors, missing
attributes, `mkIf`/`mkMerge` conflicts, and any attribute-path typo on the
hyphenated `home-registry` name) without triggering a build or violating
FORBIDDEN COMMANDS. **This is not a substitute for an actual dry-build**
and does not verify the store paths are buildable — only that the
configuration evaluates. That final confirmation is deferred to the user
running `sudo nixos-rebuild dry-build` on a real host, as required by
CLAUDE.md (Claude may not run this).

Both new modules touch server modules, so per Phase 3's rule
("If the change touches server or headless-server modules, additionally
run...") both `vexos-server-amd` and `vexos-headless-server-amd` were
included alongside the three baseline targets.

### Results (all via `path:` flake ref, since the new files are untracked)

| Target | Result |
|---|---|
| `nix flake show --impure` | PASS — structure unchanged, no eval errors |
| `vexos-desktop-amd` toplevel eval | PASS — drvPath resolved |
| `vexos-desktop-nvidia` toplevel eval | PASS — drvPath resolved |
| `vexos-desktop-vm` toplevel eval | PASS — drvPath resolved |
| `vexos-server-amd` toplevel eval | PASS — drvPath resolved |
| `vexos-headless-server-amd` toplevel eval | PASS — drvPath resolved |
| `git ls-files hardware-configuration.nix` | PASS — empty (not tracked) |
| `system.stateVersion` in all `configuration-*.nix` | PASS — unchanged, all `25.11` |
| New flake inputs declare `follows` | N/A — no flake inputs added |
| `scripts/preflight.sh` (full run, informational at Phase 3) | PASS overall; pre-existing WARNs only (vexboard placeholder secret string, `impermanence`/`dms` input age, missing `nixpkgs-fmt`/`gitleaks` locally, dry-build skip) — none introduced by this change |
| `just --list` / `just available-services` via `nix run nixpkgs#just` | PASS — justfile parses, catalog renders "Personal Trackers" group with both new entries correctly |

## Specification compliance

- Both modules follow `joplin.nix`'s exact structure: options block,
  `effectiveEnvFile` let-binding, network oneshot, secrets-init oneshot,
  `tmpfiles.rules` excluding `dataDir/postgres`, two `oci-containers`
  entries, `after`/`requires` wiring, `dumpTimer.mkDumpTimer` call with
  `offsetMinute`/`unitName` omitted (hash-derived, per instructions — these
  are new schedules with nothing to preserve).
- `DATABASE_URL` assembly in `secrets-init`, per the user's confirmed
  resolution to the joplin-pattern mismatch.
- home-registry's `postgres`/`home_inventory` hardcoded, per the user's
  confirmed resolution — no `dbUser`/`dbName` options added.
- Firewall: both use the standard global `networking.firewall.allowedTCPPorts`
  pattern (not `tailscale0`-scoped like joplin), per the user's confirmed
  answer that these should be LAN-reachable like most other modules, even
  though both will additionally sit behind NPM.
- `modules/server/default.nix`: both registered under a new
  `── Personal Trackers ──` category, placed after `── Food & Home ──`.
- justfile: all 6 locations updated; `home-registry` and `humidor` inserted
  alphabetically within each `case` block; catalog group `Personal
  Trackers` added after `Productivity` (mirrors the existing category
  naming used elsewhere in the justfile's own group comments, e.g.
  `template/server-services.nix`'s `── Food & Home ──`/`── Personal
  Trackers ──`).
- `template/server-services.nix`: new commented block matches joplin's
  comment style (port note + "no further config needed" note).
- Upstream notes file created per the user's explicit request, since these
  are the user's own apps.

## Best practices / consistency

- Nix attribute names with hyphens (`config.vexos.server.home-registry`,
  `systemd.services."docker-home-registry"`) — confirmed against
  `nginx-proxy-manager.nix`, which uses the identical unquoted-in-dotted-path
  convention throughout this repo; no quoting needed for bare
  `vexos.server.home-registry` (Nix identifiers permit `-`), and
  `"docker-home-registry-db"` correctly uses string-key syntax for
  `systemd.services` since that attrset is generated dynamically by
  `oci-containers` and always addressed via quoted strings elsewhere in
  this repo (matches joplin/grimmory's own pattern).
- No new `lib.mkIf` guards were added to any shared/universal module —
  both are net-new role-addition-style files, consistent with Module
  Architecture Pattern Option B. The `lib.mkIf (cfg.environmentFile ==
  null)` guards inside each new module gate on an option the same module
  declares, which is the explicit carve-out in CLAUDE.md, not the
  role-smuggling anti-pattern.
- `virtualisation.docker.enable`/`virtualisation.oci-containers.backend`
  use `lib.mkDefault` (grimmory's pattern) rather than joplin's unqualified
  assignment, so two of these modules (or grimmory) can coexist without a
  `mkMerge` conflict if a host enables more than one Docker-backed service.

## Completeness

All spec items implemented. No TODOs left in either module.

## Security

- No hardcoded secrets in either module — both generate random passwords
  via `openssl rand -hex 24` on first activation, matching joplin's
  pattern exactly.
- Secrets files created `0600`, `dataDir/secrets` directory `0700`.
- `tmpfiles.rules` correctly excludes `dataDir/postgres` from being
  re-chowned to root on every activation (would silently break the
  running Postgres container's file access).
- No plaintext credential assignments introduced in server modules —
  confirmed by preflight stage `[7b]` passing.

## Performance

No regressions — two new independent, opt-in modules; nothing shared is
modified in a way that affects other services' evaluation or runtime
behavior.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A (eval-verified; live dry-build/runtime deferred to user, see note above) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A (flake eval clean across all required targets; actual `nixos-rebuild dry-build` not runnable from this environment) |

**Overall Grade: A (98.75%)**

## Result: PASS

No CRITICAL or RECOMMENDED issues found. The only open item is
environmental, not a code defect: an actual `sudo nixos-rebuild dry-build`
on a real NixOS host is recommended before declaring this fully CI-ready,
since this session could only perform full-evaluation checks (which do
catch the overwhelming majority of failure modes: type errors, missing
options, module conflicts, hyphenated-attribute mistakes) rather than a
true build-closure dry-run.
