# Hyprland Greeter: ReGreet → GDM — Specification

## Current State Analysis

- `modules/hyprland-greeter.nix` enables `programs.regreet` (ReGreet, running
  under `cage` via `services.greetd`), themed with a bespoke VexOS
  Neo-Cyberpunk palette (CSS + a rasterized SVG background at
  `files/regreet/background.svg`). It sets
  `systemd.services.greetd.restartIfChanged = false`.
- `modules/gnome.nix` enables `services.displayManager.gdm.enable = true` for
  the GNOME role, with `systemd.services.display-manager.restartIfChanged =
  false`, `services.displayManager.autoLogin`, and
  `security.pam.services.gdm-autologin.enableGnomeKeyring = true`.
- `modules/hyprland-desktop.nix` already sets
  `services.displayManager.autoLogin` and `defaultSession = "hyprland-uwsm"`
  generically (these are consumed by whichever display manager is active) and
  separately sets `security.pam.services.greetd.enableGnomeKeyring = true`
  (greetd's PAM service name).
- `modules/branding-display.nix` writes the VexOS GDM login-screen logo via
  `programs.dconf.profiles.gdm`, gated to
  `config.vexos.desktop.environment == "gnome"` only, with a comment noting
  "Hyprland uses ReGreet; neither reads GDM's dconf profile."
- `modules/gpu/vm.nix` has a runtime DRM render-node check
  (`vexos-vm-render-node-check`) gated on
  `programs.hyprland.enable || services.desktopManager.cosmic.enable`, ordered
  `before = [ "greetd.service" ]` — this literal unit name only matches
  Hyprland's current greetd backend (COSMIC uses `cosmic-greeter`, which (like
  GDM) registers under the generic `display-manager.service` alias, not
  `greetd.service` — this ordering already did not cover COSMIC).
- Several comments (`modules/desktop-common.nix`, `modules/cosmic-desktop.nix`,
  `modules/gnome.nix`) state "greetd — used by the Hyprland DE — ignores
  `autoLogin`" — this becomes false once Hyprland moves to GDM.
- `flake.nix` has a comment documenting that Hyprland's greeter is ReGreet.
- Verified via the NixOS MCP docs (`services.displayManager.gdm.wayland`,
  default `true`): GDM does not require `services.xserver.enable` for a pure
  Wayland session — it runs its own Wayland compositor for the login screen
  and only needs Xwayland (already enabled via
  `programs.hyprland.xwayland.enable = true`) for X11 apps inside the session.
  No new dependency, so Context7 is not applicable (internal-only change, no
  new library).

## Problem Definition

User dislikes ReGreet's look and wants the Hyprland role's login greeter to
be GDM — already themed/branded for the GNOME role and considered "clean."
Both the plain "Hyprland" and "Hyprland (UWSM)" session entries must continue
to work correctly under the new greeter, and autologin must still land on the
UWSM session.

## Proposed Solution

Swap `modules/hyprland-greeter.nix`'s content from ReGreet/greetd to GDM,
mirroring `modules/gnome.nix`'s GDM block exactly (same options, same
`restartIfChanged = false` rationale). Extend `modules/branding-display.nix`'s
GDM-logo gate to also cover `hyprland` so the Hyprland role gets the same
branded login screen as GNOME. Fix the PAM service name and stale comments in
`modules/hyprland-desktop.nix` (greetd → gdm-autologin), and the now-incorrect
"greetd ignores autoLogin" comments in `modules/desktop-common.nix`,
`modules/cosmic-desktop.nix`, and `modules/gnome.nix`. Fix the render-node
check's unit ordering in `modules/gpu/vm.nix` (`greetd.service` →
`display-manager.service`, the alias both GDM and cosmic-greeter register
under). Update `flake.nix`'s stale ReGreet comment. Remove the now-orphaned
`files/regreet/` asset (only consumer was the file being rewritten).

No new flake input, no new package — `services.displayManager.gdm` is already
used by this repo (`modules/gnome.nix`). No Module Architecture Pattern
change: the file stays gated by the same `isHyprland = config.vexos.desktop.
environment == "hyprland"` carve-out it already uses (an option the same
module tree declares, per the standard toggleable-subsystem carve-out).

### Implementation Steps

1. `modules/hyprland-greeter.nix` — replace ReGreet config with:
   ```nix
   config = lib.mkIf isHyprland {
     services.displayManager.gdm.enable = true;
     systemd.services.display-manager.restartIfChanged = false;
   };
   ```
   Rewrite the file header comment (GDM instead of ReGreet, drop the
   dank-greeter/noctalia-greeter evaluation reference — historical, kept only
   in the superseded spec/review docs). Drop the palette/CSS/background
   derivation entirely.
2. `modules/branding-display.nix` — change the `programs.dconf.profiles.gdm`
   gate from `config.vexos.desktop.environment == "gnome"` to
   `builtins.elem config.vexos.desktop.environment [ "gnome" "hyprland" ]`;
   update the adjacent comment (COSMIC only, not Hyprland, skips GDM's dconf).
3. `modules/hyprland-desktop.nix` — change
   `security.pam.services.greetd.enableGnomeKeyring` to
   `security.pam.services.gdm-autologin.enableGnomeKeyring`; rewrite the two
   comment blocks (autoLogin wiring, PAM keyring) that describe greetd-specific
   mechanics to describe the now-identical-to-GNOME GDM mechanics.
4. `modules/gpu/vm.nix` — change `before = [ "greetd.service" ]` to
   `before = [ "display-manager.service" ]` in
   `vexos-vm-render-node-check`; update the comment referencing greetd.
5. `modules/desktop-common.nix`, `modules/cosmic-desktop.nix`,
   `modules/gnome.nix` — update the three "greetd ignores autoLogin" comment
   instances for accuracy (Hyprland no longer runs under greetd).
6. `flake.nix` — update the comment noting Hyprland's greeter is ReGreet to
   say GDM.
7. Delete `files/regreet/background.svg` (and the now-empty `files/regreet/`
   directory) — orphaned by step 1.

### Dependencies

None new. `services.displayManager.gdm` ships in nixpkgs and is already used
by `modules/gnome.nix` at the pinned `nixpkgs` input.

### Configuration Changes

None outside the files above — no new `vexos.*` options, no host-file changes
needed. Existing `vexos.desktop.environment = "hyprland"` hosts pick this up
automatically on rebuild.

### Risks and Mitigations

- **Risk:** GDM autologin into a non-GNOME Wayland session is less
  battle-tested in this repo than greetd's `initial_session`.
  **Mitigation:** `services.displayManager.autoLogin` +
  `defaultSession = "hyprland-uwsm"` is the same generic mechanism GNOME
  already uses successfully; GDM is documented to support arbitrary Wayland
  sessions via `/usr/share/wayland-sessions/*.desktop`, which
  `programs.uwsm.waylandCompositors.hyprland` already populates.
- **Risk:** `restartIfChanged = false` must target the right unit name.
  **Mitigation:** matched exactly to `modules/gnome.nix`'s existing
  `systemd.services.display-manager.restartIfChanged = false` (not
  `greetd`, which no longer applies).
- **Risk:** dry-build across GPU variants (amd/nvidia/vm) surfaces an
  evaluation error from the removed ReGreet derivation or a leftover
  reference. **Mitigation:** Phase 3 build validation runs dry-build for all
  three, plus the vm-specific render-node unit is exercised via `nix eval` on
  its `before` list.
