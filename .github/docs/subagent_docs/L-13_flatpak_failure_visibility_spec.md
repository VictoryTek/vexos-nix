# L-13 — flatpak-install-apps exits 0 on failure, invisible in systemctl status

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-13 (BUGS L17) · `modules/flatpak.nix:143-158`
(current file: the failure branch is lines 162-177; matches the cited
range's intent)

## Current State

`modules/flatpak.nix:162-177`:
```nix
if [ "$FAILED" -eq 0 ]; then
  rm -f /var/lib/flatpak/.apps-installed /var/lib/flatpak/.apps-installed-*
  touch "$STAMP"
  echo "flatpak: sync complete"
else
  # Do NOT exit 1 — a non-zero exit would cause nixos-rebuild switch to
  # report failure (exit code 4) even though the NixOS config applied fine.
  date -u +%FT%TZ > /var/lib/flatpak/.last-failed-install
  echo "flatpak: one or more apps failed — will retry on next boot"
fi
```

The unit always exits 0, by deliberate, correct design (a non-zero exit
here would make `nixos-rebuild switch` itself report failure for a
purely cosmetic app-install issue unrelated to the actual system
activation — this constraint must be preserved, not reverted). The
consequence the plan describes is real: `systemctl status
flatpak-install-apps` shows `active (exited)` — green — even after a
100%-failed install, and the only trace of the failure is a timestamp
file (`.last-failed-install`) nobody is prompted to check.

This repo already built exactly the infrastructure this gap calls for,
in a later, unrelated feature (`modules/notify.nix`, added by H-17
earlier this session's predecessor work): a `vexos-notify` script
(no-op when `vexos.notify.ntfyUrl` is unset; posts to an ntfy topic
when configured) plus a generic `notify-failure@<name>.service`
template other units opt into via `onFailure = [ "notify-failure@<name>.service" ]`.

That `onFailure=` mechanism **cannot** apply here directly — systemd
only invokes a unit's `onFailure=` when the unit itself transitions to
a `failed` state (non-zero exit or being killed/timed out), and this
unit is specifically designed to never do that. The plan's own two
suggested mechanisms (`systemd-cat`-visible warning, or a marker unit)
predate this repo's `vexos-notify` infrastructure; now that it exists,
calling it **directly** from inside the `FAILED` branch — the same way
`pkgs/vexos-update/default.nix:249` already calls
`vexos-notify "Update applied on $(hostname)"` as a plain command from
within its own script — is a better fit than either literal suggestion:
a `systemd-cat` line would just add another journal entry (this script
already logs to the journal via `echo`; the actual problem is nobody
is watching the journal, not that the message isn't loud enough there),
whereas `vexos-notify` proactively pushes the failure to whatever
`vexos.notify.ntfyUrl` the operator has configured, matching the exact
observability gap `notify-failure@` was built to close for the backup
service.

Confirmed `vexos-notify` is callable as a bare command from any
systemd-executed script without needing to add it to this unit's own
`path = [ pkgs.flatpak ];` — NixOS systemd units include
`/run/current-system/sw/bin` (where every `environment.systemPackages`
entry, including `vexos-notify`, is symlinked) in their default `PATH`
regardless of a unit's own `path` list; `pkgs/vexos-update/default.nix`
already relies on exactly this without listing `vexos-notify` in any
explicit `path`/`runtimeInputs` beyond its own package output.

**Same gap, same fix needed in the sibling module:**
`modules/gnome-flatpak-install.nix`'s `flatpak-install-gnome-apps`
service was given the identical per-app `FAILED`-flag pattern earlier
this session (L-09), including the identical
"always exit 0, write a `.gnome-last-failed-install` marker on
failure" design — so it has the exact same "green even on 100% failure"
gap. Since L-09 already made this file mirror `flatpak.nix`'s pattern
one step, mirroring this next step too (in the same session, on the
same freshly-touched pair of files) keeps them from re-diverging
immediately.

## Problem Definition

A fully-failed Flatpak app install is invisible in `systemctl status`
(always shows success) and only discoverable by an operator who
already knows to check for a specific marker file — there is no
proactive signal.

## Proposed Solution

Call `vexos-notify` directly from the `FAILED` branch in both
`modules/flatpak.nix` and `modules/gnome-flatpak-install.nix`, using
the same infrastructure already wired for backup failures (H-17). This
is a no-op when `vexos.notify.ntfyUrl` is unset (matching every other
`vexos-notify` call site's behavior) and requires no new options.

## Implementation Steps

1. `modules/flatpak.nix` — in the `else` branch (currently lines
   167-177, after the existing `date -u ... > .last-failed-install` /
   `echo` lines), add a `vexos-notify "..." "VexOS Flatpak"` call.
2. `modules/gnome-flatpak-install.nix` — same addition in its
   equivalent `else` branch (added by L-09 this session), using a
   distinct message so operators can tell which install stream failed.
3. No changes to `unitConfig`/`serviceConfig`/exit-code behavior in
   either file — the "always exit 0" design is correct and preserved.

## Configuration Changes

None — reuses the existing `vexos.notify.ntfyUrl`/`tokenFile` options;
no new options.

## Risks and Mitigations

- **Risk:** `vexos-notify` performing a network call (`curl`) inside a
  `oneshot` systemd service during early boot, potentially before
  network is fully up.
  **Mitigation:** confirmed `vexos-notify`'s own implementation already
  handles this — `curl -sf ... || true` plus a final unconditional
  `exit 0`, so a failed/timed-out notification attempt cannot itself
  fail this service or block boot. This is the exact same call this
  repo already makes from `vexos-update` and via `notify-failure@` for
  backups, both of which already accept this same tradeoff.
- **Risk:** duplicate/confusing notifications if both `flatpak.nix` and
  `gnome-flatpak-install.nix` fail in the same boot on a GNOME role.
  **Mitigation:** each carries a distinct message (base app list vs.
  GNOME app list), so an operator can tell them apart rather than being
  confused by an identical, ambiguous alert.
