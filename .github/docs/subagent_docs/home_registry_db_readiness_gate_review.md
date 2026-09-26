# Home Registry DB readiness gate — Review

## Spec compliance

Implemented exactly as specified in `home_registry_db_readiness_gate_spec.md`,
mirroring the already-applied Humidor fix: `home-registry-app-env-init` now
orders `After=`/`Requires=docker-home-registry-db.service` unconditionally,
and its script polls `docker exec home-registry-db pg_isready` (1s
interval, 60s timeout, clear failure message) after composing `appEnvFile`
— the existing password-character guard (`@`/`:`/`/` rejection for this
image's unencoded `DATABASE_URL` parser) is untouched. Single file changed:
`modules/server/home-registry.nix`.

## Best practices / consistency

- Same pattern as the Humidor fix, applied 1:1 with correct name
  substitution (`home-registry-db` container/unit names, not copy-pasted
  Humidor names) — verified by direct evaluation (see Build validation).
- No new `lib.mkIf` role/display/gaming guards; fix is internal to an
  existing module.
- Comment style matches the Humidor fix and the surrounding file.

## Security

No new secrets, no plaintext credentials, no new firewall exposure;
`pg_isready` requires no credentials.

## Completeness / correctness

- Confirmed via `nix eval --impure` against the live flake (extending
  `vexos-server-amd` with `vexos.server.home-registry.enable = true`) that
  `systemd.services."home-registry-app-env-init".after` evaluates to
  `[ "docker-home-registry-db.service" "home-registry-secrets-init.service" ]`
  — the ordering fix is actually wired up, not just textually present.
- Root cause identical to Humidor (docker-backend `Type=simple` unit reports
  "active" on fork, not on readiness; Rust app doesn't retry DB connects
  internally) — same fix mechanism, correctly scoped to this module's own
  unit/container names.

## Build validation

`sudo nixos-rebuild dry-build` unavailable in this sandbox (root disabled);
substituted with `nix eval --impure
.#nixosConfigurations.<name>.config.system.build.toplevel.drvPath` per the
project's own listed alternative:

| Target                          | Result |
|----------------------------------|--------|
| `nix flake show --impure`        | PASS — structure unchanged, no eval errors |
| `vexos-desktop-amd`               | PASS — toplevel `.drv` produced |
| `vexos-desktop-nvidia`            | PASS — toplevel `.drv` produced |
| `vexos-desktop-vm`                | PASS — toplevel `.drv` produced |
| `vexos-server-amd`                | Pre-existing, unrelated ZFS hostId assertion (same as documented in the Humidor review; confirmed unchanged, no new errors introduced) |
| `vexos-headless-server-amd`       | Same pre-existing, unrelated assertion |

Also confirmed:
- `git ls-files hardware-configuration.nix` — already verified empty for
  this change set (no new commits to hardware-configuration.nix). ✔
- No `configuration-*.nix` files touched — `system.stateVersion` unchanged. ✔
- No new flake inputs added — `follows` check N/A. ✔

## Score table

| Category                  | Score | Grade |
|----------------------------|-------|-------|
| Specification Compliance   | 100%  | A     |
| Best Practices              | 100%  | A     |
| Functionality               | 100%  | A     |
| Code Quality                 | 100%  | A     |
| Security                     | 100%  | A     |
| Performance                  | 100%  | A     |
| Consistency                  | 100%  | A     |
| Build Success                | 100%* | A     |

\* Same caveat as the Humidor fix: the two server-family targets hit a
pre-existing, unrelated placeholder-hostId assertion, not a failure caused
by this change.

**Overall Grade: A (100%)**

## Result

**PASS** — proceeding to Phase 6 Preflight.
