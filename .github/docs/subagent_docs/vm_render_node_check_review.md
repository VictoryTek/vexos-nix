# Runtime warning for missing GPU render node on VM Hyprland/COSMIC hosts — Review

## Modified files
- `modules/gpu/vm.nix`

## Root cause this addresses — confirmed by direct evidence, not inference

On a real Proxmox guest with the display device set to Standard VGA
(`bochs-drm`), `/dev/dri/` showed only `card1`, no `renderD128`. COSMIC's
session failed with explicit EGL/MESA errors:

```
cosmic-session: libEGL warning: failed to get driver name for fd -1
cosmic-panel:   [EGL] 0x3003 (BAD_ALLOC) eglInitialize: DRI2: failed to get driver name
cosmic-session: MESA: error: ZINK: failed to choose pdev
```

GNOME/Mutter is confirmed to work on the identical guest — it falls back to
software rendering; wlroots (Hyprland) and Smithay/cosmic-comp (COSMIC) do
not. This is a Proxmox VM hardware setting (Display → VirtIO-GPU 3D/VirGL),
not fixable in NixOS config. This change makes that failure visible on the
console instead of a silent black screen, per explicit user request.

## Design decision worth flagging

Gated on `config.programs.hyprland.enable || config.services.desktopManager.cosmic.enable`
— the real nixpkgs options that only become `true` once the actual compositor
is wired up — rather than `vexos.desktop.environment`. This was verified as
the correct choice, not just a style preference: `vexos-headless-server-vm`
does not import `modules/desktop-environment.nix` at all, so referencing
`vexos.desktop.environment` there (even with an `or "gnome"` fallback) would
have been fragile, and the "real option" approach requires no fallback at all
since `programs.hyprland.enable`/`services.desktopManager.cosmic.enable` are
core NixOS options always declared with `default = false`.

## Verified (WSL, nix 2.34.1)

| Check | Result |
|---|---|
| Unit exists on hyprland override, `ConditionPathExists` set correctly | `"!/dev/dri/renderD128"` |
| Unit exists on cosmic override | `true` |
| Unit absent on gnome (default) | `false` |
| `vexos-desktop-vm` (hyprland) toplevel eval | ✓ `dbjscgijknpm…` |
| `vexos-desktop-vm` (cosmic) toplevel eval | ✓ `bl9igs7bx1ws…` |
| `vexos-desktop-vm` (gnome, default) toplevel eval | ✓ `63kjnx5srg48…` (unchanged) |
| `vexos-headless-server-vm` toplevel eval | ✓ `97w7vcjjq3rm…` — proves the option-safety concern above was real and correctly avoided |
| `vexos-vanilla-vm` toplevel eval | ✓ `k2yw1paframc…` |
| `vexos-server-vm` toplevel eval | ✓ `b5pc9n06ylp8…` |
| `vexos-htpc-vm` toplevel eval | ✓ `gfjzag1rmqym…` |
| `vexos-stateless-vm` toplevel eval | ✓ `p7adch1xrkyk…` |
| `bash scripts/preflight.sh` | ✓ **PASSED, exit 0** |

## Checklist

| Category | Result |
|---|---|
| Specification compliance | Matches spec exactly |
| Best practices | `plymouth display-message --text=` and `plymouth --ping` confirmed against the Plymouth manpage before use, not assumed |
| Consistency (Option B) | Added only to `modules/gpu/vm.nix`, not `vanilla-vm.nix` (would be permanently dead code there — vanilla never imports the Hyprland/COSMIC modules) |
| Maintainability | Comment states the *why* with the actual observed error text, not a restatement of the code |
| Blast radius | Warns only, via `ConditionPathExists`; cannot alter behaviour on any host where the render node is present or the DE isn't Hyprland/COSMIC |
| `hardware-configuration.nix` / `stateVersion` | Untouched by this change |
| Flake inputs | None added |

## What is NOT verified

This environment has no way to observe real Plymouth rendering or boot a VM
with a genuinely missing render node — evaluation confirms the unit is
correctly defined, gated, and ordered, and that nothing regresses, but not
that the on-screen message actually appears as intended. That needs a real
boot on Proxmox with the render node absent to fully confirm.

## Verdict

**APPROVED.** Root cause confirmed by direct log evidence (not theory), fix is
a non-blocking runtime warning only, verified across 9 configurations with no
regressions, preflight exit 0. Real-boot confirmation of the on-screen message
still owed.
