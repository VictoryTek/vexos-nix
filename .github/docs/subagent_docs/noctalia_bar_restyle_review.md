# Noctalia bar restyle — review

## Scope

Single-file edit: `home/noctalia.nix` `bar.default` block
(`home/noctalia.nix:149-176` after edit). No other files modified.

## Environment note

`sudo nixos-rebuild dry-build` is unavailable in this sandbox
(`sudo: The "no new privileges" flag is set, which prevents sudo from running
as root`). Substituted `nix eval --impure
".#nixosConfigurations.<cfg>.config.system.build.toplevel.drvPath"` per the
project's documented Test Commands — this forces the identical full
evaluation `dry-build` would perform, without requiring `sudo` or building
derivations, and is explicitly listed as CI-equivalent.

## Findings

1. **Specification Compliance** — implementation matches
   `noctalia_bar_restyle_spec.md` exactly: `capsule = false`, `capsule_group`
   removed, bare widget tokens in `start`/`center`/`end`, `network`/
   `bluetooth`/`volume`/`battery` added to `end`, `thickness` 34→30,
   `padding` 14→10, `background_opacity = 0.85` added, edge-corner settings
   unchanged.
2. **Best Practices / Consistency** — matches upstream's own default shape
   (verified against `noctalia-shell v5.1.0` `example.toml`); no new
   `lib.mkIf` role/display/gaming guards introduced; change stays inside the
   existing role-gated `lib.mkIf (osConfig.vexos.desktop.environment ==
   "hyprland")` block, consistent with Module Architecture Pattern.
3. **Completeness** — all four requested widgets present; label defaults
   (network SSID/iface, battery %, volume %, bluetooth icon-only) confirmed
   against upstream docs, no extra per-widget overrides needed.
4. **Security** — no secrets, no service/permission changes; NetworkManager/
   upower/pipewire (consumed by the new widgets) were already enabled
   elsewhere in the repo for this role.
5. **Build validation**:
   - `nix flake show --impure`: passes, all 30 `nixosConfigurations` list
     correctly (only pre-existing unrelated warnings on
     `packages.x86_64-linux.kernel-override{,Derivation}`, not touched by
     this change).
   - `nix eval --impure` toplevel drvPath (dry-build equivalent) for
     `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm`: all
     three evaluate successfully to a `.drv` path.
   - `git ls-files hardware-configuration.nix`: empty (not tracked). ✔
   - `stateVersion`: no changes in any `configuration-*.nix`. ✔
   - `flake.nix`: no diff (no new inputs). ✔

No CRITICAL or RECOMMENDED issues found.

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

**PASS** — proceeding to Phase 6 (Preflight).
