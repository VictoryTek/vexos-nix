# Review — Hyprland / DMS bar trim + OS-logo dock launcher

Spec: `.github/docs/subagent_docs/hyprland_dms_bar_dock_trim_spec.md`
Modified files:
- `home/dank-material-shell.nix`
- `.github/docs/subagent_docs/hyprland_dms_bar_dock_trim_spec.md` (new)
- `.github/docs/subagent_docs/hyprland_dms_bar_dock_trim_review.md` (this file)

## Spec compliance

| Spec item | Implemented | Notes |
|-----------|-------------|-------|
| Remove `launcherButton` (left) | ✅ | `leftWidgets = [ "workspaceSwitcher" "focusedWindow" ]` |
| Remove `weather` (center) | ✅ | `centerWidgets = [ "music" "clock" ]` |
| Remove `clipboard`, `cpuUsage`, `memUsage`, `notificationButton` (right) | ✅ | `rightWidgets = [ "systemTray" "battery" "controlCenterButton" ]` |
| Keep `systemTray` | ✅ | present in `rightWidgets`; comment records why |
| `configVersion = 13` | ✅ | with per-bump re-check comment |
| Dock launcher, OS logo | ✅ | `dockLauncherEnabled = true; dockLauncherLogoMode = "os";` |
| Overlay layer left off | ✅ | `dockUseOverlayLayer` unset → DMS default `false`; comment records decision |
| Structural-subset barConfigs, appearance keys omitted | ✅ | 8 structural keys + 3 arrays only |
| No `hyprland.conf` change | ✅ | not touched; `$mod+Space/V/N` binds pre-exist |
| Single-file code change | ✅ | only `home/dank-material-shell.nix` |

## Best practices / consistency

- Change sits inside the existing `programs.dank-material-shell.settings` attrset,
  within the module's existing `lib.mkIf (osConfig.vexos.desktop.environment ==
  "hyprland")` gate. No new `lib.mkIf` in a shared module — Module Architecture
  Pattern (Option B) respected; `home/dank-material-shell.nix` is Hyprland-only
  by construction (same shape as `home/gnome-common.nix`).
- Comment style, box-rule headers, and "GNOME: …" provenance annotations match
  the surrounding file.
- Source rev (`069ddab`) cited in-code for every non-obvious constant
  (`configVersion = 13`, `position = 0`, the widget-list mechanism), so the next
  `inputs.dms` bump has explicit review anchors.
- No secrets, no world-writable paths, no server modules touched. Security N/A.
- No new dependency — Context7 not applicable. DMS option surface verified
  directly against the pinned `inputs.dms` source.

## Build validation (WSL — Nix 2.34.1; `nixos-rebuild` unavailable off-NixOS,
CI-equivalent `nix eval` used per CLAUDE.md)

| Step | Result |
|------|--------|
| `nix flake show --impure` | ✅ evaluates; only pre-existing `kernel-override* is not a derivation` warnings (unrelated) |
| `vexos-desktop-amd` full closure eval, **default (gnome)** branch | ✅ `EXIT 0` — confirms no regression on the non-hyprland path (DMS `settings` is `{}` there via `mkIf`) |
| `vexos-desktop-amd` `.extendModules { vexos.desktop.environment = "hyprland"; }` — full closure eval | ✅ `EXIT 0`, `/nix/store/84iz6rldy730ax565akwnb6279x4ijv0-nixos-system-vexos-26.05.drv` — the branch this change lives in |
| Generated `DankMaterialShell/settings.json` (hyprland branch) | ✅ builds; valid JSON; `barConfigs[0].rightWidgets == ["systemTray","battery","controlCenterButton"]`, `leftWidgets == ["workspaceSwitcher","focusedWindow"]`, `centerWidgets == ["music","clock"]`, `configVersion == 13`, `dockLauncherEnabled == true`, `dockLauncherLogoMode == "os"` |
| `git ls-files hardware-configuration.nix` | ✅ empty |
| `system.stateVersion` unchanged in `configuration-*.nix` | ✅ not touched |
| New flake inputs `follows` | ✅ N/A — no flake input change |
| GNOME/COSMIC roles unaffected | ✅ module gated to `environment == "hyprland"` |

Change touches only a Hyprland-desktop home module — server/headless/stateless/
htpc dry-builds not required per Phase 3 rules.

## Findings

None (CRITICAL / RECOMMENDED). The change is minimal, gated correctly, evaluates
clean, and matches the spec.

## Score table

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

**PASS** → proceed to Phase 6 (Preflight).
