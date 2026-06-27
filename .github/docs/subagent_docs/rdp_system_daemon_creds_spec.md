# Spec: Fix RDP on server — configure system daemon credentials

## Problem

`grdctl rdp set-credentials` (no flags) targets the USER-level daemon
(`org.gnome.RemoteDesktop.User`, `WantedBy=gnome-session.target`).
On a server, the GNOME session target may not be reached (headless or no physical
output), so the user daemon never starts and nothing listens on port 3389.

The SYSTEM daemon (`gnome-remote-desktop-daemon --system`, `WantedBy=graphical.target`)
handles incoming RDP connections and creates headless sessions for login.
It is reached as long as GDM starts (graphical.target). It has its own D-Bus name
(`org.gnome.RemoteDesktop`) and is configured via `grdctl --system`.

`grdctl --help` confirms three mutually-exclusive modes:
  (default)    — session sharing user daemon
  --headless   — headless user daemon
  --system     — system daemon for remote login ← what server needs

The `gnome-remote-desktop-configuration.service` (system, `WantedBy=graphical.target`)
provides `org.gnome.RemoteDesktop.Configuration` on the system bus and allows
authenticated users to configure the system daemon. This is what `grdctl --system` calls.

## Current Behaviour

`modules/remote-desktop.nix` calls only user-mode commands:
  grdctl rdp enable
  grdctl rdp set-credentials <user> <pass>

On desktop (real display, full GNOME session): works — user daemon starts.
On server (headless or no physical output): fails — user daemon never starts,
system daemon has no credentials, nothing on port 3389.

## Proposed Fix

Add `--system` equivalents to the existing script in `modules/remote-desktop.nix`.
The user-mode calls are kept for desktop session sharing. The `--system` calls
configure the system daemon for server RDP login. Both coexist without conflict.

```bash
grdctl rdp enable
grdctl rdp set-credentials <user> <pass>
grdctl --system rdp enable
grdctl --system rdp set-credentials <user> <pass>
```

Failures of either block are non-fatal (no `set -e`), matching existing behaviour.

## Files Affected

- `modules/remote-desktop.nix`

## Risks

- `grdctl --system` communicates with `org.gnome.RemoteDesktop.Configuration` on the
  system bus. If the configuration daemon is not yet running when the user service
  fires, the call may fail silently. The system daemon will fall back to having no
  credentials and won't listen. This is acceptable — credentials can be re-applied by
  restarting the service (`systemctl --user restart vexos-rdp-setup.service`).
- No new dependencies. Context7 not required.
