# GNOME VRR Toggle — Specification

## Current State Analysis

- `modules/gnome-desktop.nix` is the desktop-role GNOME addition file (Option B pattern),
  imported only by `configuration-desktop.nix`. It currently has no `options` declared
  and uses flat top-level attrs (`programs.dconf.profiles.user.databases`,
  `systemd.user.services.mute-mic-on-login`, `vexos.gnome.flatpakInstall`) as implicit config.
- `programs.dconf.profiles.user.databases` is a list-typed option; NixOS concatenates
  entries contributed by different config branches (verified pattern already used
  between `modules/gnome.nix` and `modules/gnome-desktop.nix`, which both append to it).
- GNOME/Mutter gates variable refresh rate behind the `experimental-features` list —
  `"variable-refresh-rate"` — which is off by default upstream. No existing option in
  this repo touches `org/gnome/mutter`.
- User's laptop (ASUS TUF A16, RTX 5070 Max-Q, HDMI wired directly to the NVIDIA dGPU
  per `card1 -> 0000:01:00.0`) is capped at ~60Hz on 1440p over HDMI; a USB-C DP Alt
  Mode cable is expected to unlock 1440p144 + G-Sync. User wants the Mutter VRR
  feature toggle added now, defaulted OFF, to flip on once the cable arrives.

## Problem Definition

No mechanism exists in this repo to enable GNOME/Mutter's experimental VRR feature.

## Proposed Solution

Add a self-contained, default-off toggle to the desktop-role GNOME module — this is
the module-architecture carve-out ("`lib.mkIf` guarding a config block by an option
the same module declares" is standard practice, not role-smuggling), since VRR is a
desktop/gaming-monitor concern and does not belong in the universal `gnome.nix`.

## Implementation Steps

1. In `modules/gnome-desktop.nix`:
   - Add `options.vexos.gnome.variableRefreshRate.enable = lib.mkEnableOption "GNOME Mutter variable refresh rate (VRR / G-Sync compatible) experimental feature";` (default `false` via `mkEnableOption`).
   - Restructure the file's existing flat top-level config attrs into an explicit
     `config = lib.mkMerge [ { <existing attrs, unchanged> } (lib.mkIf cfg.variableRefreshRate.enable { ... }) ];`
     to avoid mixing a declared `options` key with implicit flat config (unsafe in
     the module system once `options` is present).
   - Second `mkMerge` branch, gated by the new option, appends one more entry to
     `programs.dconf.profiles.user.databases`:
     ```nix
     { settings."org/gnome/mutter".experimental-features = [ "variable-refresh-rate" ]; }
     ```
2. No other files change. No new flake inputs, no new packages.

## Dependencies

None — internal-only NixOS/dconf option, no external library or Context7 lookup needed.

## Configuration Changes

New option: `vexos.gnome.variableRefreshRate.enable` (bool, default `false`).
To test after the DP cable arrives: set `vexos.gnome.variableRefreshRate.enable = true;`
in the host config and rebuild.

## Risks and Mitigations

- **Risk:** None beyond the dconf key itself — toggle is fully reversible (flip back
  to `false` and rebuild removes the experimental-features entry).
- **Risk:** Restructuring flat config into `config = lib.mkMerge [...]` could
  accidentally drop or duplicate an existing attr. Mitigation: move attrs verbatim,
  no behavior change to existing keys, verified via `nix eval --impure` / dry-build
  in Phase 3.
