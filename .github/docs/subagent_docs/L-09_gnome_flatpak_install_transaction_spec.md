# L-09 — gnome-flatpak-install installs all apps in one transaction

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-09 (BUGS L9) · `modules/gnome-flatpak-install.nix:67-70`
(current file: the single-transaction install is lines 66-67; matches
the cited range)

## Current State

`modules/gnome-flatpak-install.nix:66-67`:
```nix
flatpak install --noninteractive --assumeyes flathub \
  ${lib.concatStringsSep " \\\n          " cfg.apps}
```

This installs every app in `cfg.apps` as arguments to a single `flatpak
install` invocation. Confirmed against `modules/flatpak.nix` (the
sibling module this repo already uses for the base/default app list,
imported alongside this one on every GNOME role) that the exact same
class of bug — and its fix — already exists there in two forms:

1. **Per-app isolation**: `flatpak.nix`'s `flatpak-install-apps` service
   (lines 147-160) loops `for app in ...; do ... flatpak install ...
   "$app"; done`, installing one app per invocation so one bad/renamed
   app ID can't block the rest.
2. **Failure-aware stamping**: a `FAILED=0`/`FAILED=1` flag tracks
   whether *any* per-app install failed; the completion stamp
   (`/var/lib/flatpak/.apps-installed-*`) is only written when
   `FAILED=0` (lines 162-177). On any failure, a
   `.last-failed-install` timestamp marker is written instead, and the
   stamp is deliberately left unwritten so the service naturally
   retries on the next boot (`wantedBy = multi-user.target`) — without
   making `nixos-rebuild switch` itself fail (a non-zero unit exit would
   surface as switch exit code 4 even though the NixOS activation
   itself succeeded).

`gnome-flatpak-install.nix` currently has **neither** of these
properties: it's one atomic `flatpak install` call, and — regardless of
whether that call fails — the script unconditionally proceeds to
`rm -f .../gnome-apps-installed-*` and `touch "$STAMP"` immediately
after it (lines 69-71), with no `FAILED` gate. So today, a single bad
app ID doesn't just block the other apps in the same run (L-09's
literal complaint) — it also permanently marks the run as "done" (the
per-hash stamp is written regardless), meaning the service will *never*
retry, even on next boot, until the app list itself changes and
produces a new hash. This is a strictly worse failure mode than what
L-09 describes, and mirroring `flatpak.nix`'s loop necessarily brings
its `FAILED`-gated stamping along, since the two are the same design:
splitting installs into a loop only isolates failures usefully if the
stamp write is also made conditional on none of them failing.

The `extraRemoves` migration-uninstall block (lines 60-65) is *already*
per-app (Nix-unrolled into one `if ... flatpak uninstall ... || true;
fi` block per app, each independently `|| true`-guarded) — it is not
part of this bug and is left untouched.

## Problem Definition

1. All `cfg.apps` are installed in a single `flatpak install` call — one
   invalid/renamed/unavailable app ID can prevent the rest of the list
   from installing in that run.
2. Regardless of (1), the completion stamp is written unconditionally,
   so a partially-failed run is never retried — the actual practical
   impact is larger than the literal bug title suggests.

## Proposed Solution

Mirror `modules/flatpak.nix`'s established pattern exactly: a per-app
shell loop for the install step, a `FAILED` flag, and stamp-writing
gated on `FAILED=0`, with a failure-timestamp marker on the failure
path. Use a module-local marker filename
(`/var/lib/flatpak/.gnome-last-failed-install`) distinct from
`flatpak.nix`'s own `/var/lib/flatpak/.last-failed-install`, since both
services run on the same GNOME-role hosts against the same shared
`/var/lib/flatpak` state directory (confirmed via grep: `gnome.nix`
imports this module, and `gnome-desktop.nix`/etc. set
`vexos.gnome.flatpakInstall.apps` — both `flatpak-install-apps` and
`flatpak-install-gnome-apps` coexist as separate systemd units on the
same host).

## Implementation Steps

1. `modules/gnome-flatpak-install.nix` — replace the single
   `flatpak install ... ${lib.concatStringsSep ...}` line with a
   `FAILED=0` / per-app `for app in ...; do ...; done` loop identical in
   shape to `flatpak.nix:148-160` (skip-if-already-installed check,
   per-app install with a `WARNING` echo and `FAILED=1` on individual
   failure).
2. Gate the existing stamp-cleanup/`touch "$STAMP"` block behind
   `if [ "$FAILED" -eq 0 ]; then ... else ...; fi`, writing
   `/var/lib/flatpak/.gnome-last-failed-install` on the failure branch
   (mirroring `flatpak.nix:162-177`, with the marker filename adjusted
   to avoid colliding with the sibling service's own marker).
3. Leave the `extraRemoves` block, the free-space check, the stamp
   variable/hash, and the unit's `unitConfig`/`serviceConfig` untouched
   — none of them are part of this bug.

## Configuration Changes

None — no new NixOS options; `vexos.gnome.flatpakInstall.apps`/
`extraRemoves` are unchanged in shape and meaning.

## Risks and Mitigations

- **Risk:** changing from "always stamp" to "stamp only on full success"
  changes observable behavior for any role currently relying on (even
  accidentally) the old always-stamped behavior after a partial
  failure.
  **Mitigation:** the old behavior was itself the bug (silently marking
  a partially-failed install permanently "done") — the new behavior
  (retry on next boot until fully successful) matches
  `flatpak.nix`'s already-accepted, already-shipped design for the base
  app list, so this brings the GNOME-specific list in line with an
  existing, working precedent rather than inventing new behavior.
- **Risk:** two independent `.last-failed-install`-style markers
  (`flatpak.nix`'s and this module's) could confuse an operator
  debugging failures if not clearly named.
  **Mitigation:** use a distinct, clearly-scoped filename
  (`.gnome-last-failed-install`) so both are independently visible via
  `ls /var/lib/flatpak/.{last-failed-install,gnome-last-failed-install} 2>/dev/null`.
- **Risk:** `serviceConfig.Restart = "on-failure"` /
  `unitConfig.StartLimitIntervalSec`/`StartLimitBurst` on this unit
  currently have no effect either before or after this fix, since the
  script (matching `flatpak.nix`'s deliberate design) never exits
  non-zero — systemd only triggers `Restart=on-failure` on a non-zero
  exit, and both this module and `flatpak.nix` intentionally always
  exit 0 to avoid failing `nixos-rebuild switch`. This is a pre-existing
  characteristic shared with the reference implementation, not a
  regression introduced here, and is out of scope for L-09 (it is not
  part of the "one bad ID fails everything" bug being fixed).
