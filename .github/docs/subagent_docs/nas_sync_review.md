# NAS-to-NAS Mirror Sync — Review

## Scope Reviewed

- `modules/server/nas-sync.nix` (new)
- `modules/server/default.nix` (import added)
- `modules/server/backup.nix` (noBackupNeeded entry added)

Against `.github/docs/subagent_docs/nas_sync_spec.md`.

## 1. Specification Compliance

Matches the spec exactly: option shape (`enable`, `jobs.<name>.{source,destination,
deleteOnDestination,extraRsyncOptions,mediaMounts,timerConfig}`), the rsync flag
mapping table (`-a --delete --partial --protect-args -v`, `--progress` deliberately
omitted), `Nice=19`/`IOSchedulingClass=idle`, `notify-failure@` wiring,
`RequiresMountsFor` via the shared storage-mount-ordering lib, and the two
one-line side-edits (default.nix import, backup.nix noBackupNeeded). No
deviation from the spec found.

## 2. Best Practices (Nix/NixOS/nixpkgs)

- Uses `pkgs.rsync` from nixpkgs, no ad-hoc `pkgs.writeShellScriptBin` needed.
- `lib.escapeShellArgs` used for the user-supplied source/destination/extra
  options — avoids shell-injection via path strings containing spaces or
  shell metacharacters, since `ExecStart` is a systemd command line built by
  string concatenation.
- `Type = "oneshot"` is correct for a one-shot rsync invocation triggered by
  a timer (matches the `snapraid-sync`/restic precedent in this repo).
- `attrsOf submodule` + `mapAttrs'` for job → unit expansion mirrors the
  existing `parityDisks` (listOf submodule) / `servicePaths` (attrsOf)
  idioms already in the codebase — no new pattern introduced.

## 3. Consistency (Module Architecture Pattern — Option B)

- `modules/server/nas-sync.nix` is a self-contained optional-service module
  gated only by its own `vexos.server.nasSync.enable` — no `lib.mkIf`
  guarding by role, display flag, or gaming flag. Compliant.
- The one `lib.mkIf cfg.enable` in the file gates the module's own top-level
  option, which is the standard NixOS toggle pattern (same carve-out
  documented in CLAUDE.md for `vexos.btrfs.enable` etc.) — not the
  role-smuggling anti-pattern.
- Registered in `modules/server/default.nix` next to the other storage-tier
  modules (`mergerfs.nix`, `snapraid.nix`, `storage-remote.nix`), matching
  existing grouping/comment style.

## 4. Maintainability

- Header comment explains the rsync flag rationale and the `--progress`
  deviation inline, consistent with the comment density of neighboring
  modules (`snapraid.nix`, `cloudflare-ddns.nix`).
- Every option has a `description`; `source`/`destination` include an
  `example` showing the exact trailing-slash semantics, preventing the most
  likely misconfiguration (wrong slash → copies into a nested subdirectory
  instead of mirroring contents).

## 5. Completeness

All spec items implemented: module, default.nix registration, backup.nix
opt-out. Confirmed via `nix eval` (see Build Validation below) that a
populated job produces the exact expected `ExecStart`, timer config, and
`unitConfig.RequiresMountsFor`.

## 6. Performance

`Nice = 19` / `IOSchedulingClass = "idle"` keeps a large recursive rsync
from starving other services sharing the host, matching the existing
`kernel-builder.nix` precedent for background bulk work. No regression to
existing modules — `jobs` defaults to `{ }`, so `nasSync.enable = false`
(the default) produces zero additional units.

## 7. Security

- No secrets/credentials introduced — this module only shells out to
  `rsync` between two already-mounted local paths; no plaintext credential
  assignment.
- `lib.escapeShellArgs` prevents shell injection from configured
  source/destination/extraRsyncOptions strings.
- No world-writable files created; no new firewall openings (rsync runs
  local-to-local against already-mounted paths, not over the network).

## 8. API Currency

Not applicable — no external library/API integration, just the `rsync`
CLI already packaged in nixpkgs. Context7 not required per CLAUDE.md's
Dependency Policy (internal change, no new dependency).

## 9. Build Validation

Run via WSL Ubuntu (Nix 2.34.1) against `path:.` (repo has untracked new
files, so `git+file://` resolution was avoided per prior session notes).
`sudo nixos-rebuild dry-build` is unavailable on this Windows host — per
CLAUDE.md's Resource Constraints, forcing
`config.system.build.toplevel.drvPath` via `nix eval --impure` is the
documented stand-in.

| Step | Result |
|---|---|
| `nix flake show --impure` (structure) | ✅ all `nixosConfigurations`/`nixosModules`/`packages` outputs enumerate without error |
| Force `toplevel.drvPath`: `vexos-desktop-amd` | ✅ `.drv` produced |
| Force `toplevel.drvPath`: `vexos-desktop-nvidia` | ✅ `.drv` produced |
| Force `toplevel.drvPath`: `vexos-desktop-vm` | ✅ `.drv` produced |
| Force `toplevel.drvPath`: `vexos-server-amd` (required — change touches `modules/server/`) | ✅ `.drv` produced |
| Force `toplevel.drvPath`: `vexos-headless-server-amd` (required — change touches `modules/server/`) | ✅ `.drv` produced |
| Same, with `nasSync.enable = true` + a populated `jobs.tv` (extendModules) | ✅ `.drv` produced |
| Generated `ExecStart` for `jobs.tv` | ✅ `rsync -a --delete --partial --protect-args -v /goliath/data/media/tv/ /megatron/data/media/tv/` — matches spec exactly |
| Generated `systemd.timers."nas-sync-tv".timerConfig` | ✅ `{ OnCalendar = "daily"; Persistent = true; }` |
| Generated `systemd.services."nas-sync-tv".unitConfig` | ✅ `RequiresMountsFor = "/goliath /megatron"` (merged correctly with `Description`/`OnFailure` from the service-level options) |
| `nasSync.enable = true` + `backup.enable = true` together (assertion check) | ✅ evaluates cleanly — `noBackupNeeded` entry prevents the "unregistered service" assertion from firing |
| `git ls-files hardware-configuration.nix` | ✅ empty — not tracked |
| `system.stateVersion` in all `configuration-*.nix` | ✅ unchanged (`25.11` in all 6 files; this change touches none of them) |
| New flake inputs / `follows` declarations | N/A — no new flake inputs added |

No evaluation errors or missing-attribute failures encountered.

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
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Result

**PASS** — no CRITICAL or RECOMMENDED issues found. No Phase 4 refinement
needed.
