# Align Hyprland session startup with Omarchy's model — Spec

## Current state analysis

`modules/hyprland-desktop.nix` (added in `6ab1ae2`) claims in its header comment
to use "the same stack combination used by Omarchy". Verified against Omarchy
upstream, that claim is inaccurate in two ways:

| | Omarchy | vexos `hyprland-desktop.nix` |
|---|---|---|
| Display manager / greeter | **none** | greetd + `dms-greeter` |
| Session start | `omarchy-seamless-login.service` on TTY1 → `uwsm start -- hyprland.desktop`; `getty@tty1` masked | greetd greeter → user picks session |
| Shell / bar | Waybar | DankMaterialShell (`programs.dms-shell`) |
| UWSM | yes | yes (matches) |

Separately, `modules/desktop-common.nix` sets, unconditionally for all three
DEs:

```nix
services.displayManager.autoLogin = { enable = true; user = ...; };
```

`services.displayManager.autoLogin` is implemented per-display-manager (GDM,
LightDM, SDDM, cosmic-greeter). **greetd does not consume it** — greetd
performs autologin through its own `initial_session` setting instead. So on a
Hyprland host this option is at best inert and at worst pulls display-manager
machinery into a configuration that is supposed to be greetd-only.

`nixos/modules/services/display-managers/greetd.nix` (nixpkgs 26.05) declares:

```nix
aliases = [ "display-manager.service" ];
```

with **no assertion** preventing greetd from being enabled alongside GDM. Two
display managers both claiming the `display-manager.service` alias is an
unguarded conflict.

## Problem definition

On a freshly installed `vexos-desktop-vm` Proxmox guest where GNOME/GDM works
correctly (proving KMS/GBM/EGL and native Wayland all function on this virtio-gpu
device), switching to `vexos.desktop.environment = "hyprland"` and running
`just switch` drops the console to a blank VT with a bare cursor at top-left —
no greeter, no session. The previously added
`WLR_RENDERER_ALLOW_SOFTWARE = "1"` had no effect, which is consistent with the
failure being in session/greeter startup rather than in renderer selection.

Because GNOME renders fine on the identical host, a 3D-acceleration or
software-rendering explanation is ruled out.

## Proposed solution architecture

Adopt Omarchy's login model — **no greeter, seamless autologin straight into
Hyprland under UWSM** — expressed the idiomatic NixOS way via greetd's
`initial_session`, which greetd runs automatically with no password prompt.
This is the declarative equivalent of Omarchy's `seamless-login` helper and
avoids reimplementing its custom C VT-handoff binary and getty masking.

Concretely:

1. Replace `services.displayManager.dms-greeter` with a greetd
   `initial_session` launching `uwsm start -- hyprland-uwsm.desktop`
   (`hyprland-uwsm.desktop` is the session entry NixOS generates when
   `programs.hyprland.withUWSM = true`).
2. Move `services.displayManager.autoLogin` out of the shared
   `modules/desktop-common.nix` into the two DE modules whose display managers
   actually implement it (`modules/gnome.nix` for GDM,
   `modules/cosmic-desktop.nix` for cosmic-greeter), so it is never applied on
   a greetd/Hyprland host.

`programs.dms-shell` (DankMaterialShell) is **retained**. Omarchy uses Waybar
instead, but the desktop shell is a product/aesthetic choice, not the cause of
this failure — swapping it out is a separate decision for the user, not part of
this fix.

## Implementation steps (Option B: common base + role additions)

- `modules/hyprland-desktop.nix`
  - Remove the `services.displayManager.dms-greeter` block.
  - Add `services.greetd` with `initial_session` running UWSM-managed Hyprland
    as `config.vexos.user.name`.
  - Correct the header comment's inaccurate "same stack as Omarchy" claim to
    describe what this module actually does.
- `modules/desktop-common.nix`
  - Remove the `services.displayManager.autoLogin` block and note in the header
    why it is DE-specific rather than shared.
- `modules/gnome.nix`
  - Add the `autoLogin` block inside the existing `lib.mkIf isGnome` config.
- `modules/cosmic-desktop.nix`
  - Add the `autoLogin` block inside the existing `lib.mkIf isCosmic` config.

No new `lib.mkIf` role/display/gaming guard is introduced in a shared module —
content moves *into* modules that are already DE-gated, which is the pattern
established by `6ab1ae2`.

## Dependencies

None new. `services.greetd`, `programs.hyprland.withUWSM`, `pkgs.uwsm`, and
`programs.dms-shell` are all in nixpkgs 26.05 (already pinned). Context7 not
applicable — no external library API surface involved.

## Risks and mitigations

- **Risk:** Seamless autologin means no lock/auth prompt at boot on Hyprland
  hosts. **Mitigation:** This matches both Omarchy's default and the existing
  vexos behaviour on GNOME/COSMIC (`autoLogin.enable = true` was already on for
  every desktop host), so it is not a new posture for this project.
- **Risk:** The exact `uwsm start -- hyprland-uwsm.desktop` invocation and
  session-entry name cannot be verified from this environment (Windows dev
  machine, no `nix` binary). **Mitigation:** must be confirmed by
  `nixos-rebuild dry-build` plus a real boot on the target host before this is
  considered done; explicitly flagged in the review.
- **Risk:** Removing `dms-greeter` loses the graphical greeter for any future
  multi-user Hyprland host. **Mitigation:** greetd remains enabled, so a
  `default_session` greeter can be reintroduced later without rearchitecting.
- **Risk:** The root cause of the black screen has not been directly observed
  in logs (no `journalctl`/`systemctl` output was captured from the failing
  host). This change removes the most probable cause (greeter/display-manager
  conflict) but is not a confirmed diagnosis. **Mitigation:** stated plainly in
  the review; if the black screen persists, capture
  `systemctl status greetd.service` and `journalctl -b -u greetd.service`
  before iterating further.
