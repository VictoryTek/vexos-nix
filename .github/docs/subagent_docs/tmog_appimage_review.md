# TMOG (TaskManagerOG) — AppImage Package Review

## Summary

Implementation matches the spec exactly. TMOG is packaged via `appimageTools.wrapType2`
(no `appimage-run`/FUSE at runtime — addresses the user's prior AppImage reliability
concern directly), wired into `modules/packages-desktop.nix` (desktop, htpc, server,
stateless — confirmed with the user to exclude headless-server, which has no display),
and added to the GNOME "Utilities" app-folder in both the system dconf defaults and the
live home-manager oneshot (with stamp version bumped in each of the 4 roles so existing
profiles re-run the write). A weekly GitHub Actions workflow keeps the pin current since
tmog.org has no releases API.

## Specification Compliance — 100%

All 6 implementation steps from `tmog_appimage_spec.md` completed as specified:
1. `pkgs/tmog/default.nix` — created
2. `pkgs/default.nix` — `tmog` added to overlay
3. `modules/packages-desktop.nix` — `vexos.tmog` added
4. 4x `modules/gnome-*.nix` — Utilities dconf default updated
5. 4x `home-*.nix` — Utilities live apps list + stamp bump
6. `.github/workflows/update-tmog-weekly-friday.yml` — created

## Best Practices

- Matches the `brave-origin` precedent for pre-built third-party binaries: pinned
  `version`/`hash`, comment block documenting manual re-pin steps, `meta` with
  `mainProgram`/`license`/`platforms`.
- `appimageTools.wrapType2` + `extractType2` is the standard nixpkgs pattern for
  packaging an AppImage — preferred here over `appimage-run` specifically because it
  avoids the runtime FUSE/binfmt dependency that caused prior issues (per user).

## Consistency — Module Architecture Pattern

- No new `lib.mkIf` guards added to any shared module.
- `modules/packages-desktop.nix` already scoped to exactly the roles that have a
  display server; adding `vexos.tmog` there is the Option B "role addition" pattern
  applied correctly — no conditional logic introduced.
- Utilities app-folder edits follow the exact existing pattern (system dconf default +
  home-manager oneshot + stamp bump) used for the prior `LocalSend.desktop` addition.

## Completeness

All requested behavior delivered:
- Installed on all roles except vanilla and headless-server (confirmed scope with user)
- Appears in the Utilities app grid on desktop/htpc/server/stateless
- Updates through the existing `just update` / "Up" GUI path (via `vexos-update`) once
  the weekly bump workflow lands a new pin — no separate manual re-download required

## Security

- No hardcoded secrets introduced.
- `fetchurl` pulls directly from the vendor's own domain (`tmog.org`) at build time,
  never vendored into the repo — same posture as `brave-origin`.
- `license = lib.licenses.unfree` correctly reflects TMOG's freeware (non-OSS) status.

## Performance

No regressions. Package closure size is comparable to other `appimageTools`-wrapped
FHS environments already in the tree (via `programs.appimage`'s dependencies).

## Build Validation

Executed (Windows host, no NixOS available — WSL used per established project
constraint; `sudo nixos-rebuild dry-build` cannot run outside a NixOS host):

| Check | Result |
|---|---|
| `nix build` of `pkgs.vexos.tmog` (unfree allowed, matching `modules/nix.nix`) | ✅ builds; `bin/tmog`, `.desktop` (Exec rewritten), 6 icon sizes all present |
| `nix flake show --impure` | ✅ passes, no structural errors |
| `nix eval` toplevel drvPath — `vexos-desktop-amd` | ✅ `/nix/store/fr5wh2gy7...-nixos-system-vexos-26.05.drv` |
| `nix eval` toplevel drvPath — `vexos-htpc-amd` | ✅ `/nix/store/sydhh48gp...-nixos-system-vexos-26.05.drv` |
| `nix eval` toplevel drvPath — `vexos-server-amd` | ✅ `/nix/store/1rdl95iid...-nixos-system-vexos-26.05.drv` |
| `nix eval` toplevel drvPath — `vexos-stateless-amd` | ✅ `/nix/store/a4qi32pd9...-nixos-system-vexos-26.05.drv` |
| `git ls-files hardware-configuration.nix` | ✅ empty (not tracked) |
| `system.stateVersion` unchanged in all `configuration-*.nix` | ✅ confirmed (`25.11` everywhere) |
| New flake inputs / `follows` | N/A — no new flake input added (TMOG fetched via `fetchurl`, not a flake input) |
| `scripts/preflight.sh` (Phase 6) | ✅ **PASSED**, exit code 0 |

Note: `nix eval`/`nix build` against `.#nixosConfigurations...` initially failed with
"path .../pkgs/tmog does not exist" because that flake reference filters the source
tree through `git ls-files`, and `pkgs/tmog/` is untracked (per CLAUDE.md, `git add` is
reserved for the user). Re-ran using a `path:` flake reference, which includes the full
working tree without requiring anything to be staged — a read-only workaround, no repo
state was changed to produce these results.

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

## Returns

- Summary: implementation complete, matches spec, no issues found
- Build result: all available checks pass (full per-role `nixos-rebuild dry-build`
  requires a NixOS host and must be run by the user before merging)
- **PASS**
