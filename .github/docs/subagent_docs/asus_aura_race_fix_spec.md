# Spec: Fix intermittent ASUS keyboard backlight (asus-aura-init race condition)

## Current State Analysis

`modules/asus-opt.nix` contains a `systemd.services.asus-aura-init` oneshot service that
runs `asusctl aura effect static -c ffffff` to set the keyboard to static white on boot.

Current service definition:

```nix
systemd.services.asus-aura-init = {
  description = "Set ASUS keyboard Aura to static white";
  after    = [ "asusd.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type            = "oneshot";
    RemainAfterExit = true;
    ExecStart       = "${pkgs.asusctl}/bin/asusctl aura effect static -c ffffff";
  };
};
```

## Problem Definition

User reports: backlight always lights up in firmware, goes off during kernel/asusd init,
then only *sometimes* comes back on under the OS. This is a classic race condition.

Root cause — two gaps in the current service:

1. **No hard dependency on asusd.** `after = ["asusd.service"]` is ordering-only. If
   asusd is not active, `asus-aura-init` still starts. Without `requires`, systemd has
   no obligation to keep asusd running before this service executes.

2. **No retry.** `ExecStart` runs `asusctl` once. If asusd has registered its systemd
   unit as active but hasn't yet finished initialising its Aura/HID subsystem (which
   involves USB device enumeration and firmware handshake), `asusctl` gets a D-Bus error
   or "device not ready" response, exits non-zero, and the service fails silently.
   The keyboard stays dark.

The prior spec assumed that `after = ["asusd.service"]` with asusd being `Type=dbus`
guarantees D-Bus readiness. In practice, asusd can register its D-Bus name before its
keyboard hardware scan is complete, so the Aura command arrives before the device is
ready to accept it.

## Proposed Solution

Two targeted changes to `systemd.services.asus-aura-init` in `modules/asus-opt.nix`:

### Change 1: Add `requires`

Add `requires = [ "asusd.service" ]`. This makes asusd a hard dependency — if asusd
is not running, asus-aura-init will not start. Combined with the existing `after`, this
gives the correct dependency pair that systemd recommends for service ordering with
readiness requirements.

### Change 2: Add retry loop via `pkgs.writeShellScript`

Replace the single `asusctl` call with a shell script that:
1. Waits up to 30 s for the `org.asuslinux.Daemon` D-Bus name to appear using
   `busctl wait --system` (part of systemd, always present on NixOS). This catches the
   gap between asusd's systemd activation and its D-Bus registration.
2. Retries `asusctl aura effect static -c ffffff` up to 5 times with 2 s sleep between
   attempts. This catches the gap between D-Bus registration and Aura subsystem readiness.
3. Exits 1 if all attempts fail (lets systemd log it; does not block boot since the
   service is not `PartOf` any critical target).

`busctl` is referenced via its full store path (`${pkgs.systemd}/bin/busctl`) per
NixOS convention for systemd services with minimal PATH.

## Implementation Steps

1. In `modules/asus-opt.nix`, modify `systemd.services.asus-aura-init`:
   - Add `requires = [ "asusd.service" ];` alongside the existing `after`
   - Replace the `ExecStart` string with a `pkgs.writeShellScript` call containing
     the busctl-wait + retry loop

## Affected Files

- `modules/asus-opt.nix`

## Dependencies

No new packages. `pkgs.systemd` (busctl) and `pkgs.asusctl` are already present.
No new flake inputs.

## Risks and Mitigations

- **Risk:** `busctl wait` not available in older systemd.
  **Mitigation:** NixOS 26.05 ships systemd 256+; `busctl wait --timeout` is supported
  since systemd 250. No mitigation needed.

- **Risk:** `org.asuslinux.Daemon` D-Bus name is wrong.
  **Mitigation:** Confirmed from asusd GitHub source (asus-linux/asusctl). The `|| true`
  on the busctl call ensures the retry loop still runs even if the wait fails.

- **Risk:** All 5 retry attempts fail (asusd is broken).
  **Mitigation:** Service exits 1; boot continues. This is the same failure mode as
  today, just logged more visibly in journald.
