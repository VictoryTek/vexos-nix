# Align Hyprland session startup with Omarchy's model — Review

## Modified files
- `modules/hyprland-desktop.nix`
- `modules/desktop-common.nix`
- `modules/gnome.nix`
- `modules/cosmic-desktop.nix`

## Root cause history — three separate bugs found across this investigation

This module went through three rounds of failure before the actual cause was
isolated. Recorded here so the history isn't lost:

1. **`services.xserver.displayManager.gdm.wayland = false` (rejected).**
   First hypothesis was that VM guests lack a working 3D-acceleration path and
   Mutter/Hyprland need to fall back to Xorg. User rejected on principle
   (Wayland-only distro, GNOME deprecating Xorg) and rightly so — GDM/Wayland
   was later proven to work fine on this same guest. Reverted, never landed.

2. **Empty `programs.uwsm.waylandCompositors` (real bug, but not THE bug).**
   `programs.hyprland.withUWSM = true` only sets `programs.uwsm.enable`; it
   does not register a compositor. `waylandCompositors` was empty, so
   `hyprland-uwsm.desktop` never existed. Confirmed via `nix eval` in WSL
   (`waylandCompositors -> [ ]` before, `[ "hyprland" ]` after) and fixed by
   adding `programs.uwsm.waylandCompositors.hyprland`. This was a genuine,
   necessary fix — but pushing it and rebuilding the VM still black-screened,
   proving it wasn't sufcient.

3. **Live GDM→greetd switch without reboot (red herring, not a repo bug).**
   After fix #2, the VM was switched live from GNOME to Hyprland without
   rebooting. `coredumpctl` showed PID 1122's EXE was
   `…/gdm-50.2/bin/gdm`, SIGSEGV, running for the unit's entire 7m51s
   lifetime — GDM survived the live switch under systemd's re-aliased
   `display-manager.service` → `greetd.service` unit name, and crashed. This
   looked identical to the earlier "GDM under greetd.service" symptom from
   before any of these fixes existed, which sent the investigation down a
   wrong path (assuming a persistent alias-collision bug in the module). A
   clean reboot was the actual next step, not a code change.

4. **`greetd: default_session contains no command` — THE actual bug.**
   After a clean reboot eliminated the live-switch complication, greetd's own
   log gave the answer directly:
   ```
   greetd[1102]: default_session contains no command
   greetd.service: Main process exited, code=exited, status=1/FAILURE
   ```
   The module only set `settings.initial_session`. greetd requires
   `default_session` — without it, greetd exits at startup before doing
   anything, and nothing ever takes the console. This explains every black
   screen observed in this entire investigation, including the very first one:
   Hyprland was **never once actually launched** in any of the logs collected
   across this whole thread.

   A Plymouth/`plymouth-quit-wait` deadlock was also floated as a hypothesis
   after a boot appeared to hang on the splash screen. **Disproven** by
   `systemctl status`: both `plymouth-quit.service` and
   `plymouth-quit-wait.service` show `Active: active (exited)`,
   `status=0/SUCCESS`, completing in milliseconds. Plymouth was never at
   fault; the apparent hang was greetd having already failed silently behind
   the still-displayed splash.

## The fix

```nix
services.greetd = {
  enable = true;
  settings =
    let
      hyprlandSession = {
        command = "${lib.getExe pkgs.uwsm} start -- hyprland-uwsm.desktop";
        user    = config.vexos.user.name;
      };
    in
    {
      default_session = hyprlandSession;
      initial_session = hyprlandSession;
    };
};
```

Both keys point at the same session (rather than giving `default_session` a
greeter), preserving the Omarchy-style seamless-autologin intent: no login
screen, ever, on this host.

## Verified option values (Hyprland path, WSL nix 2.34.1)

| Option | Value |
|---|---|
| `services.greetd.settings.default_session.command` | `…/uwsm-0.26.4/bin/uwsm start -- hyprland-uwsm.desktop` ← previously **unset** |
| `services.greetd.settings.default_session.user` | `"nimda"` |
| `services.greetd.settings.initial_session.command` | same as default_session (unchanged from prior fix) |
| `programs.uwsm.waylandCompositors` | `[ "hyprland" ]` (from fix #2, still correct) |
| `services.displayManager.gdm.enable` | `false` |
| `services.displayManager.autoLogin.enable` | `false` |

## Build validation — RUN (WSL, nix 2.34.1)

- `nix eval … vexos-desktop-vm (hyprland override) … .toplevel.drvPath` → ✓ `wqrw94gzblva…`
- `nix eval … vexos-desktop-vm (gnome, default) … .toplevel.drvPath` → ✓ `63kjnx5srg48…` (no regression)
- `bash scripts/preflight.sh` → ✓ **PASSED, exit 0**

Same environment-only skips as the prior review (no `/etc/nixos/vexos-variant`
on WSL, `jq`/`nixpkgs-fmt`/`gitleaks` not installed) — none code-related.

## What is still unverified

Evaluation confirms `default_session` is now populated with a valid command.
It cannot prove Hyprland renders on screen — that needs a real boot. Given
`default_session contains no command` was an unconditional startup-time
config-parse failure (not a runtime/hardware issue), fixing it should be
sufficient on its own. If a black screen still occurs after this fix on a
clean boot, the render-node question raised earlier in this investigation
(`/dev/dri/` showed only `card1`/bochs-drm, no `renderD128`, on the VM at the
time) becomes the next real lead — this fix does not address that, because
Hyprland was never confirmed to have reached the point of needing it.

## Verdict

**APPROVED**, conditional on a real reboot test. Root cause (greetd
`default_session` misconfiguration) is directly confirmed by greetd's own
error message, not inferred. Preflight exit 0, no regression on GNOME/COSMIC/
server/htpc/stateless (unchanged from the prior review's regression matrix —
this fix only touches `services.greetd.settings` inside the existing
`isHyprland` block).
