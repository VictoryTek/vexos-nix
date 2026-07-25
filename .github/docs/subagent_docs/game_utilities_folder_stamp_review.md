# Review: Game Utilities app-folder stamp bump

## Change reviewed

`home-desktop.nix`: `vexos-init-app-folders` oneshot stamp bumped
`.dconf-app-folders-initialized-v3` → `-v4`. One-line change, no other files
touched.

## Findings

1. **Spec compliance** — matches spec exactly: single stamp bump, no other
   modifications.
2. **Best practices** — follows the established repo pattern (this exact
   file has bumped this stamp 4 times before for the same reason: payload
   changed, force one re-run).
3. **Consistency** — Module Architecture Pattern (Option B) not implicated;
   this is a home-manager systemd user service, not a NixOS module split. No
   new `lib.mkIf` role-gating introduced.
4. **Correctness of root cause** — confirmed via `git log -p` that
   `fc9e771` changed the Game-Utilities `apps` list to Flatpak `.desktop` IDs
   without bumping the stamp, breaking re-application on already-provisioned
   systems. Confirmed via grep that no nixpkgs Discord/Vesktop references
   remain anywhere in the repo — the nixpkgs→Flatpak migration itself
   (`modules/gaming.nix`) is correct and unrelated to this bug.
5. **Security** — no secrets, no permission changes.
6. **Scope** — touches only the desktop role's home-manager stamp; htpc/
   server/stateless stamps (`-v2`) are unrelated (they don't reference
   Discord/Vesktop) and correctly left untouched.

## Build validation (vexos-nix specific — sudo unavailable in this sandbox)

- `nix flake show --impure`: passed, all 30 outputs listed.
- `sudo nixos-rebuild dry-build` unavailable (`sudo` blocked by sandbox
  "no new privileges" flag) — substituted with the CI-equivalent full
  evaluation:
  - `nix eval --impure .#nixosConfigurations.vexos-desktop-amd...toplevel.drvPath` → success
  - `nix eval --impure .#nixosConfigurations.vexos-desktop-nvidia...toplevel.drvPath` → success
  - `nix eval --impure .#nixosConfigurations.vexos-desktop-vm...toplevel.drvPath` → success
- `git ls-files hardware-configuration.nix` → empty (not tracked). Pass.
- `system.stateVersion` unchanged in all `configuration-*.nix` (still
  `25.11` everywhere). Pass.
- No new flake inputs added. N/A.

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
| Build Success | 100%* | A |

\* `nixos-rebuild dry-build` could not be executed directly due to sandbox
`sudo` restriction; evaluated via `nix eval --impure` on the toplevel
derivation for all three required desktop variants instead, per CLAUDE.md's
documented equivalence. The user should run the actual `dry-build` (or
`switch`) locally to fully confirm, since it is user-initiated only.

**Overall Grade: A (100%)**

## Result: PASS
