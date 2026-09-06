# Display Manager: Don't Restart On Switch — Review

## Scope

- `modules/gnome.nix` — `systemd.services.display-manager.restartIfChanged = false;`
  added inside the existing `lib.mkIf isGnome` config block, next to
  `services.displayManager.gdm.enable`.
- `modules/hyprland-desktop.nix` — `systemd.services.greetd.restartIfChanged = false;`
  added inside the existing `lib.mkIf isHyprland` config block, next to the
  `programs.dank-material-shell.greeter` declaration.

## Findings

- **Spec compliance:** matches `dm_no_restart_on_switch_spec.md`.
- **Module Architecture (Option B):** both lines sit in each module's own
  whole-file DE-flag `config` gate — a pre-existing accepted pattern for these
  two files, not a new per-role `mkIf` inside shared content. GNOME line applies
  uniformly to desktop / stateless / htpc. No new files, options, or conditionals.
- **Correctness of unit names:** `nix eval` confirms
  `nixosConfigurations.vexos-stateless-amd.config.systemd.services.display-manager.restartIfChanged`
  evaluates to `false`. `greetd` is only defined when `isHyprland`, so it is
  absent (and correctly so) from the default GNOME outputs.
- **Behaviour:** deferred DM config now applies on next boot; consistent with the
  `just switch` reboot prompt and with commit `bd3ac93` (DE changes already go
  through `nixos-rebuild boot`). `systemctl restart display-manager` remains
  available for a manual live restart.
- **Security / performance:** none affected. No secrets, no world-writable files.
- **Surgical:** pre-existing repo-wide `nixpkgs-fmt` drift left untouched; the
  normalised diff of each file vs HEAD is exactly the added lines, and
  `nixpkgs-fmt` does not reformat them.

## Build Validation

| Check | Result |
|-------|--------|
| `nix flake show --impure` | PASS (rc 0) |
| `nix eval …vexos-stateless-amd…toplevel.drvPath` | PASS |
| `nix eval …vexos-desktop-nvidia…toplevel.drvPath` | PASS |
| `nix eval …vexos-desktop-amd…toplevel.drvPath` | PASS |
| `nix eval …vexos-htpc-amd…toplevel.drvPath` | PASS |
| `nix eval` hyprland-extended `…greetd.restartIfChanged` + toplevel | PASS — see note |
| `display-manager.restartIfChanged` on stateless | `false` (verified) |
| `hardware-configuration.nix` tracked | No |
| `system.stateVersion` changed | No |
| New flake inputs | None |
| `bash scripts/preflight.sh` | PASS (rc 0) |

(`sudo nixos-rebuild dry-build` unavailable in sandbox — "no new privileges";
per-target `nix eval` of `toplevel.drvPath` substituted, the CI-equivalent.)

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

## Verdict

PASS
