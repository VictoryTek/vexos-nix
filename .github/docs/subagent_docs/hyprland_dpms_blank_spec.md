# Hyprland: screen-off-on-idle (DPMS), no lock — Spec

## Current state analysis

- `modules/system-nosleep.nix` (imported in all role configs) blocks suspend/hibernate
  and sets `logind.settings.Login.IdleAction = "ignore"` — this is intentional and
  stays unchanged. It only controls system sleep/suspend, not display DPMS state.
- `modules/hyprland-desktop.nix` (lines 133-136) explicitly omits `hypridle`:
  > "hypridle is likewise omitted: DMS ships its own lock screen and idle handling,
  > and a second idle manager risks double-locking. Revisit only if idle-to-lock
  > turns out not to work."
  In practice DMS's idle handling does not blank the display — there is currently
  no idle daemon running at all on the Hyprland role, so the screen never turns off.
- `home/dank-material-shell.nix` is the home-manager module scoped to
  `osConfig.vexos.desktop.environment == "hyprland"` — the correct layer for a
  user-session idle daemon (matches where `services.hyprpolkitagent` and
  `services.udiskie` are declared).
- Confirmed via MCP nixos server: Home Manager exposes `services.hypridle` with
  `enable`, `settings` (hyprlang-style attrs), `package`, `systemdTarget`,
  `importantPrefixes`. `hypridle` 0.1.8 is present in nixpkgs.

## Problem definition

User wants the display to blank (DPMS off) after 5 minutes of inactivity on the
Hyprland role — **display blank only, no session lock**. This is a user decision
(confirmed): no `lock_cmd`, no `dms ipc call lock lock` on timeout — only
`hyprctl dispatch dpms off` / `dpms on`.

## Proposed solution

Add a `services.hypridle` block to `home/dank-material-shell.nix`, inside the
existing `lib.mkIf (osConfig.vexos.desktop.environment == "hyprland")` config block
(same gate already used for the rest of the file — no new conditional needed).

```nix
services.hypridle = {
  enable = true;
  settings = {
    general = {
      # No lock_cmd: this daemon only blanks the display, it never locks.
      before_sleep_cmd = "";
      after_sleep_cmd  = "";
    };
    listener = [
      {
        timeout    = 300; # 5 minutes
        on-timeout = "hyprctl dispatch dpms off";
        on-resume  = "hyprctl dispatch dpms on";
      }
    ];
  };
};
```

Notes:
- `systemdTarget` is left at its Home Manager default (`graphical-session.target`),
  which is the same target UWSM activates for `dms.service` per the existing
  comment in `modules/hyprland-desktop.nix` — no override needed.
- No `general.lock_cmd` is set, so hypridle never invokes a lock even implicitly
  (`before_sleep_cmd`/`after_sleep_cmd` are left empty no-ops since
  `system-nosleep.nix` already blocks sleep targets; kept explicit for clarity,
  matching the "no lock, ever" requirement).
- This does not touch `modules/system-nosleep.nix` or any suspend/idle-lock
  policy — sleep/suspend stays fully disabled as-is.
- Package for `hypridle` comes from the `services.hypridle.package` default
  (nixpkgs `hypridle`), no override required — it's not currently installed
  elsewhere, so no duplicate/version conflict.

## Implementation steps (Module Architecture Pattern)

This is a Home Manager (user-layer) change, not a shared NixOS module, so the
Option B common-base/role-addition pattern doesn't directly apply — but the
existing precedent in this exact file (gating Hyprland-only home config behind
`osConfig.vexos.desktop.environment == "hyprland"`) is followed, not a new
`modules/*.nix` file.

1. Edit `home/dank-material-shell.nix`: add the `services.hypridle` block shown
   above inside the existing `config = lib.mkIf (...) { ... }` body.
2. Update the file's header comment area (around the existing hypridle
   note at `modules/hyprland-desktop.nix:133-136`) to reflect that hypridle is
   now used for DPMS-only blanking, not locking — so a future reader doesn't
   reintroduce a duplicate idle daemon or add locking without realizing this was
   a deliberate choice.

## Dependencies

- `hypridle` (nixpkgs, already available, confirmed via MCP nixos server,
  version 0.1.8) — no new flake input, no Context7 lookup needed (internal
  Home Manager option, not a versioned external library API).

## Configuration changes

- `home/dank-material-shell.nix` only.

## Risks and mitigations

- **Risk:** A second idle daemon double-locking. **Mitigation:** no lock command
  is configured anywhere in the hypridle block — it is DPMS-only by construction.
- **Risk:** `hyprctl dispatch dpms off/on` requires Hyprland's IPC socket to be
  reachable from the hypridle systemd user unit. **Mitigation:** binding to
  `graphical-session.target` (the HM default) ensures hypridle starts only after
  the compositor is up, same as `dms.service`.
- **Risk:** Conflicting with `system-nosleep.nix`'s `IdleAction = "ignore"`.
  **Mitigation:** logind's IdleAction is independent of hypridle/DPMS — DPMS is a
  Wayland/compositor-level display state, not a systemd-logind sleep action, so
  no conflict.
