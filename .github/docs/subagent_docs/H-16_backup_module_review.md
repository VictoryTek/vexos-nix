# H-16 — Review & Quality Assurance

Status: Phase 3 (Review) — includes one refinement cycle
Spec: `.github/docs/subagent_docs/H-16_backup_module_spec.md`

## Modified Files

- `modules/server/backup.nix` (new) — `vexos.server.backup` option set,
  `servicePaths` default table keyed by `_server_service_names`, PostgreSQL
  pre/cleanup hooks, wired to `services.restic.backups.main`.
- `modules/server/default.nix` — added `./backup.nix` import.
- `justfile` — added `backup` to `_server_service_names`, `_svc` description,
  `status` unit mapping, `services` `_check` list, the enable-time repository/
  password-file prompt, the post-enable info block, and a new `backup-now` recipe.

## Refinement Cycle 1

**Issue found during build validation (CRITICAL):** `services.restic.backups.<name>.passwordFile`
is typed `nullOr str` upstream (verified in `nixos/modules/services/backup/restic.nix`),
but `vexos.server.backup.passwordFile` was declared and passed through as `nullOr path`,
causing a type error the moment `vexos.server.backup.enable = true` was actually forced
(the default-off eval paths never exercised this line, so `nix flake show` alone didn't
catch it). Fixed by converting with `toString cfg.passwordFile` at the point it's handed
to `services.restic.backups.main`, keeping the nicer path-typed public option.

## Review Findings

1. **Specification Compliance** — matches the spec: default path table, postgres
   pre-hook gated on `services.postgresql.enable`, syncthing/proxmox documented
   exceptions, `extraPaths` escape hatch, justfile extension points, `backup-now` recipe.
2. **Best Practices** — follows restic's own documented `backupPrepareCommand`/
   `sudo -u postgres pg_dumpall` pattern from the upstream module's example.
3. **Consistency (Module Architecture Pattern)** — new file is a role-addition module
   (`modules/server/backup.nix`, imported by `modules/server/default.nix` alongside
   every other opt-in service module); no `lib.mkIf` added to any shared/base module.
4. **Maintainability** — `servicePaths` table carries a comment pointing at
   `justfile:_server_service_names` as the list to keep it in sync with, and documents
   the syncthing exclusion inline rather than silently omitting it.
5. **Completeness** — all spec items implemented.
6. **Performance** — no impact on any host with `vexos.server.backup.enable = false`
   (the default); the whole config block is behind `lib.mkIf`.
7. **Security** — password file path only (never a literal secret value); PostgreSQL
   dump file is created with owner `postgres`/mode `0700` directory and removed by
   `backupCleanupCommand` after each run so the plaintext dump doesn't linger on disk.
8. **API Currency** — `services.restic.backups.*` options verified directly against the
   pinned nixpkgs revision (local `/nix/store` source), which is what caught the
   `passwordFile` type mismatch above.
9. **Build Validation:**
   - `nix flake show --impure` — passed.
   - Required targets (`vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm`,
     `vexos-server-amd`, `vexos-headless-server-amd`, server modules touched) evaluated
     via `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`
     (the `sudo nixos-rebuild dry-build` substitute noted in the H-15 review — `sudo` is
     unavailable in this sandboxed session).
   - The default-disabled `backup.nix` config path evaluated cleanly on the first pass,
     but since `vexos.server.backup.enable` defaults to `false`, the interesting code
     (the `services.restic.backups.main` assignment) is lazy and wasn't actually forced
     until the module's `extendModules`-based branch test below — which is what caught
     the `passwordFile` type bug.
   - Forced-branch test: `vexos-server-amd.extendModules { vexos.server.backup.enable = true; ...attic.enable = true; services.postgresql.enable = true; }` — failed once
     (the bug above), passed after the fix.
   - A separate `dockerCompat conflicts with docker` assertion surfaced when combining
     `dockhand` + `podman` in one forced-branch test — confirmed via a control test with
     `backup.nix` completely absent that this conflict is pre-existing and unrelated to
     this change; not pursued further (out of scope for H-16).
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `flake.nix` — untouched; no new inputs. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same two pre-existing WARNs as the
     H-15 review (repo-wide nixpkgs-fmt drift; VexBoard's already-accepted plaintext
     placeholder string) — neither introduced by this change.
   - `just --list` — parses cleanly; `backup-now` appears.

No outstanding CRITICAL or RECOMMENDED issues after the refinement cycle.

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

- Build result: PASS (after 1 refinement cycle for the `passwordFile` type mismatch)
- **PASS**
