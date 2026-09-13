# Hyprland Noctalia Bar/Shell Tweaks — Review

## Summary

Reviewed against the Phase 1 spec (`hyprland_noctalia_bar_tweaks_spec.md`).
All 5 actionable implementation steps completed as specified. Item 3
(autologin) deliberately shipped no change per spec, pending live retest.

## Specification Compliance

1. `bar.default.end` now leads with `"launcher"` — ✅ confirmed in the
   rendered `noctalia-config.toml` (`end = ["launcher", "tray", "network",
   "bluetooth", "volume", "battery", "session"]`).
2. `dock.icon_size = 35` — ✅ confirmed in rendered TOML.
3. No change — as specified.
4. `widget.tray.hide_passive = false` — ✅ confirmed in rendered TOML.
   `tail-tray` package + `systemd.user.services.tail-tray` added to
   `home/dank-material-shell.nix` — ✅ confirmed resolved
   `ExecStart = "/nix/store/...-tail-tray-0.2.34/bin/tail-tray"` on the forced
   Hyprland branch, and the package **actually builds** (pulled prebuilt from
   cache.nixos.org — no source compile needed, no build risk).
5. `shell.panel.session_placement = "floating"` /
   `session_position = "center"` — ✅ confirmed in rendered TOML.
6. `shell.panel.open_near_click_control_center = true` — ✅ confirmed in
   rendered TOML.

## Best Practices / Consistency

- `tail-tray`'s systemd user service matches the existing
  `mute-mic-on-login` unit's shape exactly (`Unit.After`/`PartOf` = 
  `graphical-session.target`, `Install.WantedBy` = same) and sits alongside
  the pre-existing `hyprpolkitagent`/`udiskie` "GNOME provided this
  implicitly" services in the same file — no new pattern introduced.
- All Noctalia settings additions verified field-by-field against the actual
  pinned source (`config_schema.cpp`, not memory or the existing file's
  possibly-stale conventions) before being written — per this project's own
  stated methodology in `home/noctalia.nix`'s header comment.
- No Module Architecture Pattern concerns — both files are Home Manager
  modules (not the system NixOS module layer this repo's Option B pattern
  governs), already gated by the existing single `isHyprland`-equivalent
  `mkIf`, unchanged.

## Completeness

All 6 user-reported items addressed: 5 implemented, 1 (autologin)
deliberately deferred with the user's own confirmation that it needs a live
retest — not silently dropped.

## Security

No secrets, no new privileged services. `tail-tray` runs as an unprivileged
systemd **user** service, no `capSysAdmin`/setuid/root — same trust level as
`udiskie`/`mute-mic-on-login` already running in the same file.

## Performance

Negligible — one small Qt tray helper process, already available as a
nixpkgs binary-cache hit (no compile-time cost on rebuild).

## Build Validation

Same substitution as the prior review — `sudo nixos-rebuild dry-build` is
unavailable in this execution environment (sandbox blocks `sudo`
escalation). Used the CI-equivalent safe commands plus direct inspection of
the generated config artifact (stronger verification than eval alone, since
it proves the *exact bytes* Noctalia will read):

| Check | Command | Result |
|---|---|---|
| Flake structure | `nix flake show --impure` | ✅ all outputs list |
| Default (gnome) branch unaffected | `nix eval --impure` toplevel drvPath — `vexos-desktop-amd` | ✅ **identical drvPath** to before this change (`jr27392lw4wb...`) — proves zero effect on non-Hyprland hosts |
| Forced hyprland branch, full closure | `nix eval --impure` via `extendModules { vexos.desktop.environment = "hyprland"; }` toplevel drvPath | ✅ `nixos-system-vexos-26.05.drv` produced |
| Generated Noctalia config content | `nix build` the resolved `home-manager.users.nimda.xdg.configFile."noctalia/config.toml".source` derivation, then `cat`/`grep` the actual output file | ✅ all 6 changed keys present with exact expected values (see spec) |
| `tail-tray` systemd unit resolution | `nix eval` `home-manager.users.nimda.systemd.user.services.tail-tray.{Service.ExecStart,Install.WantedBy}` | ✅ resolves to a real store path, correct target |
| `tail-tray` actually builds | `nix build` the package directly | ✅ succeeded — prebuilt, pulled from cache.nixos.org |
| `hardware-configuration.nix` not committed | `git ls-files hardware-configuration.nix` | ✅ empty (unchanged from prior check, no new files added) |
| `system.stateVersion` unchanged | `git diff -- configuration-*.nix` | ✅ no diff (files untouched this round) |
| No new/changed flake inputs | `git diff --stat -- flake.nix flake.lock` | ✅ empty — `tail-tray` is plain nixpkgs, no new input |

**Caveat:** as before, this cannot confirm the *visual/runtime* result
(whether Sunshine's tray icon status is actually `Passive`, whether
`tail-tray` successfully authenticates/connects, whether the session panel
visually centers as expected) without a live reboot on real hardware — a
structural limitation of the sandboxed environment, not a gap in the
verification performed.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 90% | A- (config-verified byte-for-byte; runtime/visual result unverified — sandbox limitation, flagged to user) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A (package build itself verified directly, not just evaluated) |

**Overall Grade: A (99%)**

## Result

**PASS.** No CRITICAL issues. No refinement cycle needed.
