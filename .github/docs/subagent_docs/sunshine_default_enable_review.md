# Sunshine default-enable — review

## Spec compliance
All four steps from the spec were implemented exactly as designed:
`modules/sunshine.nix` option default flipped to `true`, `configuration-vanilla.nix`
overrides it back to `false` via `lib.mkDefault` (matching the existing flatpak
precedent), `template/features.nix` comments updated, `justfile`'s `_check` helper
made default-aware and `sunshine` passed `on`.

## Build validation

- `nix flake show --impure` (via WSL Nix 2.34.1): all 30+ outputs, including
  `vexos-desktop-*`, `vexos-server-*`, `vexos-htpc-*`, `vexos-vanilla-*`, evaluate
  cleanly. No errors.
- `sudo nixos-rebuild dry-build` unavailable — no NixOS host in this environment
  (Windows primary, WSL has Nix but not a NixOS system). Per-target
  `nix eval --impure` used as the closest available substitute (documented prior
  limitation, unchanged by this session).
- Targeted eval of `config.vexos.features.sunshine.enable` per role:
  - `vexos-desktop-amd` → `true`
  - `vexos-server-amd` → `true`
  - `vexos-htpc-amd` → `true`
  - `vexos-vanilla-amd` → `false`
  All four match the spec's intent exactly.
- `git ls-files hardware-configuration.nix` → empty (not tracked).
- `system.stateVersion` unchanged in all `configuration-*.nix` (still `"25.11"`
  everywhere it was before).
- No new flake inputs added — `follows` check N/A.
- `justfile` `_check` block extracted and syntax/behavior verified standalone with
  `bash -n` and a live run: reports `sunshine` as on-by-default when unset,
  correctly reports explicit `true`/`false` overrides.

## Consistency (Module Architecture Pattern — Option B)
- No new `lib.mkIf` role/display/gaming guards added to any shared module.
- The `lib.mkEnableOption ... // { default = true; }` change is in the same module
  that declares the option (`modules/sunshine.nix`) — the standard, explicitly
  documented carve-out for a module's own toggle default, not role-smuggling.
- The vanilla opt-out uses the exact same `lib.mkDefault false` override technique
  already established in the same file for `vexos.flatpak.enable`.

## Security
No new open ports, credentials, or world-writable files beyond what
`modules/sunshine.nix` already declared (`openFirewall`, `capSysAdmin`, `uinput`
group) — those apply now by default instead of opt-in, which is the intended
change, not a new exposure surface.

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
| Build Success | 95% | A (dry-build unavailable in this environment; flake-show + per-role eval substituted) |

**Overall Grade: A (99%)**

## Result: PASS
