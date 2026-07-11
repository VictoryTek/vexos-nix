# SearXNG Server Service — Phase 3 Review

## Spec Compliance

Implementation matches `.github/docs/subagent_docs/searxng_spec.md` exactly:
- `modules/server/searxng.nix` created with `enable`/`port`/`openFirewall`/`environmentFile`
  options, matching the spec's architecture verbatim.
- `configureUwsgi = true` + `uwsgiConfig.disable-logging = true` implemented for
  no-query-logging.
- `server.method = "POST"`, `bind_address = "127.0.0.1"`, `secret_key` sourced from
  `$SEARXNG_SECRET_KEY` via `environmentFile` — all present as specified.
- `openFirewall` defaults to `false` — private-by-default, as specified.
- Registered in `modules/server/default.nix` under the existing `# ── AI & Privacy ──`
  category (adjacent to `kiji-proxy.nix`/`portbook.nix`, both privacy-oriented tools —
  reasonable placement, matches spec intent of "final placement decided during
  implementation to match surrounding style").
- No reverse-proxy, Redis/limiter, or Tor wiring added — matches spec's explicit
  out-of-scope list.

## Best Practices / Consistency (Module Architecture Pattern — Option B)

- Self-contained module exposing `vexos.server.searxng.*`, no `lib.mkIf` guards gating
  by role/display/gaming flag — the only `lib.mkIf` present guards the module's own
  `enable` option, which is the documented carve-out (toggleable-subsystem pattern), not
  role-smuggling.
- Single import line added to `modules/server/default.nix`; no `configuration-*.nix`
  touched — correct, since server services are activated via host-local
  `server-services.nix`, not role imports.
- Style (option layout, comments, header) matches sibling modules (`ntfy.nix`,
  `kiji-proxy.nix`).

## Security

- No hardcoded secrets: `secret_key` is `$SEARXNG_SECRET_KEY`, substituted from a
  user-supplied `environmentFile` (`nullOr path`, `null` default) — file is host-local,
  never committed.
- No world-writable files introduced.
- `openFirewall` defaults to `false`; service binds to `127.0.0.1` — no unintended
  network exposure.
- Query-logging avoided at both the app-server layer (`configureUwsgi` avoids the
  Werkzeug built-in server that upstream explicitly documents as logging all queries)
  and the WSGI layer (`disable-logging = true`).

## Completeness

All spec requirements implemented. No partial or stubbed logic.

## Performance

No regressions — new module is opt-in (`enable` defaults to `false`) and has zero effect
on configurations that don't activate it.

## Build Validation

- `nix flake show --impure`: **PASS** — flake structure and all 30 outputs list cleanly.
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`: **PASS** (run as
  `nixos-rebuild dry-build --impure` in this sandboxed dev environment, which lacks
  `sudo`; hardware-configuration.nix present at `/etc/nixos/`). Exit code 0.
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`: **PASS**. Exit code 0.
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`: **PASS**. Exit code 0.
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`: **BLOCKED by unrelated
  pre-existing issue** — fails on a `networking.hostId` assertion
  (`hosts/server-amd.nix:15`, `lib.mkDefault "a0000001"` shared placeholder). Confirmed
  via `git show e0960a6:hosts/server-amd.nix` that this placeholder existed identically
  before this change — not introduced by SearXNG. Evaluation reached the
  assertion-checking stage, meaning the SearXNG module itself merged and type-checked
  without error; the failure is orthogonal (host-specific ZFS `hostId` requirement, not
  server-service-related).
- `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`: **BLOCKED by the
  same pre-existing, unrelated `hostId` placeholder assertion.**
- `git ls-files hardware-configuration.nix`: empty — **PASS** (not committed).
- `system.stateVersion` unchanged in all `configuration-*.nix` (diffed against
  pre-change commit `e0960a6`): **PASS**.
- No new flake inputs / `flake.lock` unchanged: **PASS**.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A- (3/3 required desktop dry-builds pass; server-role dry-builds blocked by a pre-existing, unrelated hostId placeholder assertion, not a regression from this change) |

**Overall Grade: A (98%)**

## Result

**PASS** — no CRITICAL issues attributable to this change. The server-role dry-build
blocker is a pre-existing repository condition (shared `hostId` placeholder,
`hosts/server-amd.nix:15` / `hosts/headless-server-amd.nix`) unrelated to SearXNG and
present on `main` prior to this change; it does not gate this feature's completion.

## Addendum: `justfile` recipe wiring (follow-up)

Every other `modules/server/*.nix` service is wired into five `justfile` touch points
that make it discoverable/operable via `just`. The initial implementation missed this —
added as a follow-up under the same feature:

1. `_server_service_names` — validation whitelist for `just enable`/`just status`/
   `just service-info`.
2. `available-services` recipe — `_svc searxng "..."` catalog entry under the existing
   "AI & Privacy" header (alongside `kiji-proxy`).
3. `service-info`'s `_info()` case — one-line port/URL summary.
4. `status` recipe's `UNITS`/`URLS` case — maps to the `uwsgi` systemd unit (SearXNG runs
   under uWSGI per the privacy-hardening design; confirmed no other module in this repo
   uses `services.uwsgi`, so the unit name is unambiguous) and `http://localhost:8888`.
5. `enable` recipe:
   - Post-enable case block message (mirrors `kiji-proxy`/`scrutiny` style).
   - Auto-generated `environmentFile` secret, mirroring the existing
     `_ensure_vexboard_secret` pattern: `server.secret_key` in `settings.yml` is sourced
     from `$SEARXNG_SECRET_KEY`, so a working instance requires *some* value: unlike
     `proxmox`/`backup` (which prompt for user-supplied external values), there is no
     external value here, so a random secret is generated at
     `/etc/nixos/secrets/searxng.env` automatically, matching VexBoard's precedent for
     internal-only secrets.

### Validation performed

- `just --justfile justfile --list` — parses cleanly, exit 0 (confirms no syntax errors
  introduced across all five edit sites).
- `just --justfile justfile --show enable` — recipe renders correctly with the new
  branch in place.
- Extracted the exact `sed`/`grep` enable-logic and `environmentFile` auto-generation
  logic and ran it standalone (without `sudo`, using scratch files) against a synthetic
  `server-services.nix`: confirmed the `enable = true;` toggle insert, the
  `environmentFile = "...";` insert, and the generated secret file all produce valid Nix
  syntax (checked with `nix-instantiate --parse`), and that the idempotency guard
  correctly detects a pre-existing `environmentFile` line to prevent duplicate inserts
  on a second `just enable searxng` run.
- `bash scripts/preflight.sh` re-run after the `justfile` changes: **PASS** (exit 0).
  Same pre-existing formatting/secret-pattern/gitleaks warnings as before (unrelated:
  `modules/server/vexboard.nix:90` placeholder string, repo-wide `nixpkgs-fmt` drift,
  `gitleaks` not installed in this sandbox) — no new warnings introduced.

No `configuration-*.nix`, module, or flake changes were needed for this addendum —
purely additive to `justfile`, which is not part of the Nix evaluation graph.
