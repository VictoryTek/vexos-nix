# Display Manager: Don't Restart On `nixos-rebuild switch` — Spec

## Current State

- GNOME roles (desktop, stateless, htpc) get GDM from `modules/gnome.nix`
  (`config = lib.mkIf isGnome`), which sets `services.displayManager.gdm.enable`.
- The Hyprland DE (desktop role, `vexos.desktop.environment == "hyprland"`) uses
  `greetd`, wired by the upstream DMS greeter module and configured in
  `modules/hyprland-desktop.nix` (`config = lib.mkIf isHyprland`).
- Nothing sets `restartIfChanged` on either unit, so `switch-to-configuration`
  restarts `display-manager.service` / `greetd.service` whenever that unit or one
  of its dependencies changes in the new closure.

## Problem

When the display-manager unit changes during `just switch`, `nixos-rebuild
switch` restarts it under the live session. The graphical session is torn down
mid-rebuild and the user is dropped to a black VT with a blinking cursor until
the DM comes back — instead of staying in the session until the flow's final
"Reboot now?" prompt. Observed historically on multiple roles; the desktop GNOME
role currently avoids it only because its DM unit happens not to change on most
rebuilds.

## Proposed Solution

Set `restartIfChanged = false` on the display-manager unit for both stacks:

- `modules/gnome.nix` — `systemd.services.display-manager.restartIfChanged = false;`
  (inside the existing `lib.mkIf isGnome` config block; applies to all GNOME roles)
- `modules/hyprland-desktop.nix` — `systemd.services.greetd.restartIfChanged = false;`
  (inside the existing `lib.mkIf isHyprland` config block)

The changed DM configuration then takes effect on the next boot. This is
consistent with the `just switch` flow, which already prompts for a reboot on
completion, and with commit `bd3ac93` which already routes DE *changes* through
`nixos-rebuild boot`.

## Module Architecture (Option B) Compliance

- `modules/gnome.nix`: the line goes in the module's own `config` block, which is
  already `lib.mkIf isGnome` (DE-flag gate on the whole file — a pre-existing,
  accepted pattern for this file, not a new per-role `mkIf` inside shared
  content). Applies uniformly to every role that runs GNOME.
- `modules/hyprland-desktop.nix`: same — added to the existing whole-file
  `lib.mkIf isHyprland` config block, matching the file's established style.

No new files, options, or conditionals introduced.

## Dependencies

None. `systemd.services.<name>.restartIfChanged` is a core NixOS option.
`systemd.services.display-manager` (DM-agnostic alias) and
`systemd.services.greetd` are both defined by nixpkgs. No Context7 lookup needed
(no external library API).

## Configuration Changes

None to any `configuration-*.nix`. No `system.stateVersion` change.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| DM config changes silently deferred to next boot | Matches existing `just switch` reboot prompt; documented in-file |
| A future rebuild that *needs* a live DM restart won't get one | Rare; user reboots after switch anyway. `systemctl restart display-manager` remains available manually |
| Wrong unit name | `display-manager` is the nixpkgs DM-agnostic alias; `greetd` is the greetd unit — both verified in nixpkgs |
| COSMIC DE left unaddressed | Out of scope — not requested; COSMIC greeter can get the same treatment later if the symptom appears there |
