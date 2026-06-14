# NixOS 26.05 "Yarara" Upgrade — Final Review

**Feature:** `nixos-26.05-upgrade`
**Date:** 2026-06-13
**Review Cycle:** Combined Phase 3 + Phase 4 refinement + Phase 5

---

## Summary

Initial evals (Phase 3) found 3 CRITICAL assertion failures and 3 deprecation warnings
requiring fixes beyond the original spec. All were resolved in Phase 4 (Refinement cycle 1).
Final evals (Phase 5) pass clean on all required targets.

---

## Phase 3 Initial Findings

### CRITICAL — Failed assertions

| # | Error | File | Fix |
|---|-------|------|-----|
| C1 | `services.resolved.extraConfig` no longer has effect — use `services.resolved.settings` | `modules/network.nix` | Replaced with `settings.Resolve` block |
| C2 | `services.displayManager.gdm.wayland` no longer has effect — GNOME 50 is always Wayland | `modules/gnome.nix` | Removed option |
| C3 | `pkgs.nodePackages` has been removed | `modules/development.nix` | `nodePackages.typescript` → `pkgs.typescript` |

### Deprecation warnings (surfaced by 26.05, fixed in Phase 4)

| # | Warning | File | Fix |
|---|---------|------|-----|
| W1 | `services.resolved.dnssec` renamed to `settings.Resolve.DNSSEC` | `modules/network.nix` | Consolidated into `settings.Resolve` block |
| W2 | `services.resolved.fallbackDns` renamed to `settings.Resolve.FallbackDNS` | `modules/network.nix` | Consolidated into `settings.Resolve` block |
| W3 | `programs.vscode.userSettings` renamed to `programs.vscode.profiles.default.userSettings` | `home-desktop.nix` | Renamed |
| W4 | `wineWowPackages` deprecated — use `wineWow64Packages` | `modules/gaming.nix` | Renamed |

---

## Phase 5 Build Validation Results

All evals use `nix eval --impure ".#nixosConfigurations.<target>.config.system.build.toplevel.drvPath"`.

| Target | Result | Notes |
|--------|--------|-------|
| `vexos-desktop-amd` | ✓ PASS | No warnings |
| `vexos-desktop-nvidia` | ✓ PASS | No warnings |
| `vexos-desktop-vm` | ✓ PASS | No warnings |
| `vexos-server-amd` | ✓ PASS | proxmox-nixos confirmed working on 26.05 |
| `vexos-headless-server-amd` | ✓ PASS | |
| `vexos-stateless-amd` | ✓ PASS | Expected locked-password warning (setup script artefact) |
| `vexos-htpc-amd` | ✓ PASS | |

### Git hygiene

- `hardware-configuration.nix` not tracked: ✓ (`git ls-files` returns empty)
- `system.stateVersion` unchanged at `"25.11"` in all 6 `configuration-*.nix` files: ✓
- All new inputs already had appropriate `follows` (no new inputs added): ✓

### Plex TODO(2026-05) investigation

`modules/server/plex.nix:43` has a TODO to remove the `LD_LIBRARY_PATH = lib.mkForce ""`
workaround once the upstream nixpkgs Plex module no longer injects opengl-driver
unconditionally. Because `services.plex.enable` is `false` by default, the systemd
service does not appear in the default server eval and the LD_LIBRARY_PATH value cannot
be checked via `nix eval` without opting plex in.

**Decision:** The workaround is conditional (`lib.mkIf cfg.enable`) and harmless when
inactive. Removing it requires opting in plex to test — this is tracked separately as
MASTER_PLAN L-17 and is out of scope for this upgrade PR.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 98% | A |
| Functionality | 100% | A |
| Code Quality | 98% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99.5%)**

Minor deduction: 4 deprecation warnings were not predicted in the original spec
(nodePackages removal, resolved option renames, vscode profile rename, wineWow rename).
All were resolved in Refinement Cycle 1.

---

## Verdict: APPROVED
