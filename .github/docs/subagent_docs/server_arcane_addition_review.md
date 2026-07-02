# Arcane server service — Review

## Spec Compliance

Implementation matches `server_arcane_addition_spec.md` exactly:
- `modules/server/arcane.nix` created with the specified options (`enable`, `port`,
  `appUrl`, `environmentFile`), Docker-backend OCI container, assertions on `appUrl`
  and `environmentFile`, firewall port opened unconditionally (matches Portainer
  precedent).
- `modules/server/default.nix` — one import line added (`./arcane.nix`), placed next
  to `./dockhand.nix` under "Container Runtime", as specified.
- `template/server-services.nix` — `arcane` added to the "Available services" list and
  a commented toggle block added under "Container Runtime", as specified.
- Vaultwarden and Headscale confirmed already present, already wired into
  `modules/server/default.nix`, and already documented/toggled in
  `template/server-services.nix` — correctly required no changes.

## Best Practices / Nix Conventions

- Follows Option B (no `lib.mkIf` role-gating inside the module; the whole file's
  content applies unconditionally once imported and `cfg.enable` is set).
- One service per file, `vexos.server.<service>.enable` mkEnableOption pattern,
  matches sibling modules (`portainer.nix`, `vaultwarden.nix`, `dockhand.nix`).
- Secrets handled via `environmentFile` (systemd EnvironmentFile), never inlined as
  plaintext option defaults — consistent with `vexboard.nix`/`vaultwarden.nix`.

## Consistency

- Matches `portainer.nix` pattern (Docker backend, `virtualisation.oci-containers`)
  rather than `dockhand.nix`'s Podman pattern — correct choice since the user asked
  for "the docker management app" and Arcane requires the native Docker socket.
- No new `lib.mkIf` guards added to shared/universal modules.

## Completeness

All three requested services addressed: Vaultwarden (pre-existing, verified wired),
Headscale (pre-existing, verified wired), Arcane (net-new module, spec'd + implemented).

## Security

- No hardcoded secrets; `ENCRYPTION_KEY`/`JWT_SECRET` required via `environmentFile`,
  enforced by assertion.
- Docker socket mount is root-equivalent host access — documented explicitly in the
  module header comment, matching the existing risk disclosure style used elsewhere
  in this repo (e.g. `dockhand.nix`'s "authentication is DISABLED" warning).
- Placeholder `appUrl` rejected by assertion (same pattern as `vaultwarden.nix`).

## Build Validation

- `nix flake show --impure` — passed, all 30+ outputs list cleanly.
- `git ls-files hardware-configuration.nix` — empty (not committed). Confirmed.
- `system.stateVersion` — unchanged in all `configuration-*.nix` files. Confirmed.
- No new flake inputs added — no `follows` declarations needed.
- **Note:** `sudo` is unavailable in this execution environment ("no new privileges"
  flag set), so `sudo nixos-rebuild dry-build` could not be run directly. Used the
  CI-equivalent safe alternative instead: `nix eval --impure
  ".#nixosConfigurations.<name>.config.system.build.toplevel.drvPath"` for all
  required targets, which forces full module evaluation (assertions, option merging,
  and derivation construction) without invoking `sudo` or building the closure.
- **Blocker encountered and resolved:** the new `modules/server/arcane.nix` file was
  initially untracked by git; Nix flakes only read git-tracked files, so
  `vexos-server-amd`/`vexos-headless-server-amd` evaluation failed with "path does
  not exist" even though the file existed on disk. Per CLAUDE.md, `git add`/`git
  commit` are user-only operations — the user was asked and staged/committed the
  files themselves. Re-ran evaluation after confirming `git status` was clean.
- Results (drvPath forced, no errors):
  - `vexos-desktop-amd` — pass
  - `vexos-desktop-nvidia` — pass
  - `vexos-desktop-vm` — pass
  - `vexos-server-amd` — pass (server role touched by this change)
  - `vexos-headless-server-amd` — pass (server role touched by this change)

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 95% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

Security scored 95% rather than 100% only because the docker-socket-mount risk is
inherent to the app's purpose (same as Portainer, already accepted in this repo) —
not a defect, just a residual risk worth naming.

## Result

**PASS** — no CRITICAL issues. Proceeding to Phase 6 (Preflight).
