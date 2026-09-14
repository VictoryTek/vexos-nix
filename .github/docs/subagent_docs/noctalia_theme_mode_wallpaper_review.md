# Noctalia Light/Dark Wallpaper Switching — Review

## Summary

Reviewed against `noctalia_theme_mode_wallpaper_spec.md`. The single
implementation step was completed as specified. One file changed:
`home/noctalia.nix`.

## Specification Compliance

`programs.noctalia.settings.hooks.theme_mode_changed` added, rendering to:

```toml
[hooks]
theme_mode_changed = "/nix/store/…-noctalia-5.1.0/bin/noctalia msg wallpaper-set /home/nimda/Pictures/Wallpapers/vex-bb-$NOCTALIA_THEME_MODE.jxl"
```

✅ Absolute store path for the binary (not bare `noctalia`), as specified.
✅ `$NOCTALIA_THEME_MODE` preserved literally in the TOML string for shell
expansion at hook time — not escaped, interpolated, or mangled by the Nix →
TOML rendering.
✅ No wrapper script, no derivation, no shell conditional — the minimal form
the spec called for.

## Best Practices / Consistency

- Absolute-store-path binary reference matches the existing convention in
  `home/dank-material-shell.nix` (`${pkgs.wireplumber}/bin/wpctl`,
  `${pkgs.tail-tray}/bin/tail-tray`) rather than the bare-`noctalia` form used
  by the `ipc` attrset (which must stay bare because those same strings are
  consumed by the static `files/hypr/hyprland.conf`).
- The one genuinely non-obvious thing — that the env var's values are exactly
  the two filename stems — is called out in a comment, including *why*
  `directory_light`/`directory_dark` are not the mechanism, so a future reader
  does not "fix" this by setting those instead.
- Home Manager layer only; no Module Architecture Pattern surface touched.

## Completeness

Closes the specific GNOME-parity gap reported (light mode not swapping the
wallpaper). Palette follows automatically via the pre-existing
`theme.source = "wallpaper"`.

## Security

None applicable — one IPC call to the user's own shell, no privileges, no
secrets, no network.

## Performance

One process spawn per light/dark toggle. Nil.

## Build Validation

`sudo nixos-rebuild dry-build` remains unavailable in this environment
(sandbox blocks `sudo` escalation); used the established substitutes plus,
this time, **Noctalia's own validator** — the check `home/noctalia.nix`'s
header comment explicitly prescribes ("Re-run that check when editing … and
treat any warning as a defect").

| Check | Command | Result |
|---|---|---|
| Noctalia config validator | `noctalia config validate <generated config.toml>` | ✅ `✓ Config is valid`, exit 0, **zero warnings** |
| Validator negative control | same, against a copy with `theme_mode_changed` → `theme_mode_changedX` | ✅ `WARN … hooks.theme_mode_changedX: unknown setting` — proves a zero-warning result actually means the key is recognized at this pin, rather than the validator ignoring hook keys |
| Rendered TOML inspection | `nix build` the generated `config.toml` derivation, then read `[hooks]` | ✅ exact expected string, env var intact |
| Wallpaper files present for both modes | `ls ~/Pictures/Wallpapers/vex-bb-{light,dark}.jxl` | ✅ both present (home-manager symlinks) |
| Forced hyprland branch, full closure | `nix eval --impure` via `extendModules { vexos.desktop.environment = "hyprland"; }` | ✅ toplevel drv produced |
| Default (gnome) branch unaffected | `nix eval --impure` toplevel drvPath, `vexos-desktop-amd` | ✅ `jr27392lw4wb…` — byte-identical to the session baseline, so GNOME hosts are provably untouched |
| Flake structure / stateVersion / hw-config / flake inputs | `scripts/preflight.sh` | ✅ see Phase 6 |

**Caveat:** the validator proves the key is recognized and the command string
is well-formed; it cannot prove the wallpaper visibly swaps. That requires
toggling light mode on a live Hyprland session. The mechanism itself
(`theme_mode_changed` → `wallpaper-set`) is documented upstream rather than
inferred, and both file paths were confirmed to exist, so the remaining risk
is low but non-zero.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A (validator-confirmed + upstream-documented mechanism; live toggle unverified — sandbox limitation) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Result

**PASS.** No CRITICAL issues. No refinement cycle needed.
