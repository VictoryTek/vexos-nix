# Hyprland: screen-off-on-idle (DPMS), no lock — Review

## Spec compliance

Implemented exactly as specified: `services.hypridle` added to
`home/dank-material-shell.nix` inside the existing
`lib.mkIf (osConfig.vexos.desktop.environment == "hyprland")` block. Single
listener, 300s timeout, `hyprctl dispatch dpms off` / `dpms on`, no `lock_cmd`
anywhere. `system-nosleep.nix` untouched.

## Build validation (vexos-nix specific steps)

Windows host has no `nix`; validated via WSL Ubuntu (Nix 2.34.1) per project
memory. `sudo nixos-rebuild dry-build` is unavailable there (no real NixOS host),
so equivalent-strength `nix eval --impure` forcing full toplevel evaluation was
used instead, with a CI-style stub `/etc/nixos/hardware-configuration.nix`
(matching `.github/workflows/ci.yml`'s fixture) to get past the host-generated
file requirement:

- `nix flake show --impure` → **PASS**, all 30 `nixosConfigurations` listed, no
  errors.
- Forced `vexos.desktop.environment = "hyprland"` via `extendModules` (default is
  `"gnome"`, so the new code path would otherwise never evaluate) and forced full
  evaluation of `config.system.build.toplevel.drvPath` for:
  - `vexos-desktop-amd` → **PASS**
  - `vexos-desktop-nvidia` → **PASS**
  - `vexos-desktop-vm` → **PASS**
- Directly forced `home-manager.users.<user>.home.activationPackage.drvPath` for
  `vexos-desktop-amd` (forced hyprland) → **PASS** — this evaluates the exact
  `services.hypridle` attrset added, confirming the option types/shape are valid
  Home Manager config (a malformed `settings` value would have thrown a module
  type error here).
- `git ls-files hardware-configuration.nix` → empty, confirmed not tracked.
- `system.stateVersion` unchanged in all `configuration-*.nix` (verified via
  `scripts/preflight.sh` stage [4/8] — all 6 pass).
- No new flake inputs added — no `follows` declarations needed.
- `bash scripts/preflight.sh` (via WSL, `nix shell nixpkgs#jq nixpkgs#nixpkgs-fmt`)
  → **exit 0 — PASSED**. Non-blocking pre-existing WARNs unrelated to this change:
  flake input freshness (`impermanence` 216 days, `dms` 36 days), repo-wide
  `nixpkgs-fmt` formatting drift (101/193 tracked files, present before this
  change), one placeholder-secret-pattern match in `modules/server/vexboard.nix`
  (pre-existing, unrelated file), `gitleaks` not installed. None are HARD
  failures and none were introduced by this change.
- **Caveat (per project memory):** stage `[2/8]` (`nixos-rebuild dry-build`)
  always SKIPs in this WSL environment — no `/etc/nixos/vexos-variant` on a
  non-NixOS host. A clean WSL preflight pass is not a substitute for running
  `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` (or the affected
  host's variant) on an actual NixOS machine before switching. Recommend the
  user run that once before rebuilding for real.

## Best practices / consistency / maintainability

- Matches Module Architecture Pattern: change lives in the same Home Manager
  file already gated by `osConfig.vexos.desktop.environment == "hyprland"`, no
  new `lib.mkIf` role-guard introduced in a *shared* module (this is the
  standard "option this same layer declares" pattern, not the anti-pattern the
  project's rules target).
- Comment added explains *why* no `lock_cmd` is set and cross-references the
  existing `hypridle`-omission rationale in `modules/hyprland-desktop.nix`, so a
  future reader won't reintroduce a duplicate idle daemon or add locking without
  realizing it was a deliberate choice.
- Diff is minimal and surgical: `git diff --stat` shows only
  `home/dank-material-shell.nix | 19 +++++++++++++++++++`, one file, additive
  only, nothing else touched.

## Security

No secrets, no plaintext credentials, no new attack surface — `hypridle` invokes
only `hyprctl dispatch dpms`, no shell-out to anything user-input-driven.

## Completeness vs. user's stated requirements

- Screen blanks after 5 minutes idle: yes (`timeout = 300`).
- No lock ever triggered by this daemon: yes (no `lock_cmd`, no lock listener).
- `system-nosleep.nix` behavior (suspend/hibernate always disabled) unchanged:
  confirmed, file not touched.

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
| Build Success | 95% | A (WSL eval PASS; real-hardware dry-build not independently verifiable from this environment — see caveat above) |

**Overall Grade: A (99%)**

## Result: **PASS**
