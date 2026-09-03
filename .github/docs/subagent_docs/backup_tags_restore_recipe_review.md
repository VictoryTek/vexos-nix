# Backup snapshot tags + `just restore-service` — Review

Phase 3 — Review & Quality Assurance
Spec: `.github/docs/subagent_docs/backup_tags_restore_recipe_spec.md`

## Files changed

- `modules/server/backup.nix`
- `justfile`

## Findings

### Spec compliance

| Spec item | Status |
|-----------|--------|
| `enabledBackupServices` sorted list in `let` | done (`lib.attrNames` — sorted) |
| `extraBackupArgs` = `--tag vexos` + per-service tags | done |
| `/etc/vexos/backup-paths.json` manifest, enabled services only | done |
| `pkgs.jq` scoped to `cfg.enable` | done; `pkgs` added to arg set |
| `restore-service <name> [snapshot]` after `restore-plex` | done, no group attr, `_require-server-role` |
| typed `yes` + `VEXOS_ASSUME_YES` | done |
| stop managing unit + `trap` restart | done — extended to `docker-`/`podman-` prefixes after finding uptime-kuma is an oci-container (unit `docker-uptime-kuma.service`, not `uptime-kuma.service`) |
| `sudo "$RESTIC"` (PATH-safe) | done |
| help text mentions recipe + `snapshots --tag` | done (`just enable backup` epilogue) |

### Deviations from spec (improvements)

1. Recipe probes three candidate unit names, not one. The spec assumed
   `<name>.service`; `modules/server/uptime-kuma.nix` proves oci-container
   services use `docker-<name>.service` / `podman-<name>.service`. Without this
   the container would keep running during a volume restore.
2. Added an explicit `command -v jq` guard for a clean error message.

### Best practices / consistency

- `restore-service` mirrors `restore-plex` structure (deps, confirm shape,
  `set -euo pipefail`, `trap ... EXIT`, `✓` completion line). Consistent.
- Module change stays inside the existing `lib.mkIf cfg.enable` merge branch —
  no new shared-module `lib.mkIf` role guard, Option B respected. The new `let`
  bindings are pure helpers.
- `builtins.toJSON` is the idiomatic manifest emitter; JSON chosen so VexBoard /
  VexPortal can consume it later.

### Security

- Manifest is world-readable (`/etc/vexos/backup-paths.json`) but contains only
  data directory paths — no secrets. Acceptable.
- Restore runs as root via `sudo restic-main` (needs to read the 0600
  passwordFile and write under `/var/lib`). Same trust level as `restore-plex`.
- No credential assignment, no world-writable file.

### Build validation

See "Build results" below.

## Build results

Run via WSL (Nix 2.34.1); `nixos-rebuild dry-build` unavailable off-NixOS, so
per-target full evaluation (`nix eval ... system.build.toplevel.drvPath`) used
per CLAUDE.md CI-equivalent guidance.

| Command | Result |
|---------|--------|
| `nix flake show --impure` | exit 0 — structure valid, all outputs listed, no eval errors |
| `nix eval .#nixosConfigurations.vexos-server-amd...toplevel.drvPath` | exit 0 — `/nix/store/yvdb0nplhy3kzpvrn6nl8zfjmglnm2kk-nixos-system-vexos-26.05.drv` |
| `nix eval .#nixosConfigurations.vexos-headless-server-amd...toplevel.drvPath` | exit 0 — `/nix/store/jcxgch3d5lzyi7cqdx5lxr1djvck3ygm-nixos-system-vexos-26.05.drv` |
| `extendModules` eval (backup + uptime-kuma enabled) | exit 0 — `extraBackupArgs = ["--tag","vexos","--tag","uptime-kuma"]`; manifest = `{"uptime-kuma":["/var/lib/docker/volumes/uptime-kuma-data/_data"]}` |

Tags and manifest render exactly as specified. The manifest path also confirms
the recipe's `docker-<name>.service` unit handling is required for this service.

- `git ls-files hardware-configuration.nix` → empty (not committed). ✓
- `system.stateVersion` unchanged in all `configuration-*.nix` (no such files
  touched). ✓
- No new flake inputs. ✓
- `just --list` (via `nix run nixpkgs#just`) parses the justfile; `restore-service`
  is listed. ✓
- `shellcheck -x` on the extracted recipe body — clean, exit 0. ✓
- `scripts/preflight.sh` (WSL) — **Preflight PASSED**, exit 0. Stage 8
  `pkgs.vexos.vexos-update` builds (shellcheck passes). All WARN lines are
  pre-existing / environmental (jq, nixpkgs-fmt, gitleaks absent in WSL; the
  vexboard `change-me` placeholder is untouched by this change). ✓

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (98%)**

## Verdict

**PASS** — no CRITICAL or RECOMMENDED issues. All evaluations succeed; tag and
manifest output verified against the spec. Proceed to Phase 6 preflight.
