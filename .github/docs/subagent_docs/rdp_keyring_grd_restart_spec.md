# RDP Keyring / gnome-remote-desktop Restart — Specification

**Feature name:** `rdp_keyring_grd_restart`
**Module:** `modules/remote-desktop.nix`
**Date:** 2026-07-18

## Current State Analysis

`modules/remote-desktop.nix` defines a **root** systemd oneshot,
`vexos-rdp-setup.service`, that provisions GNOME Remote Desktop (RDP) on machines
using GDM auto-login. On every boot it:

1. Generates a self-signed TLS certificate (once per host) under `/var/lib/vexos-rdp`.
2. Waits for the user session D-Bus socket.
3. Runs `gnome-keyring-daemon --unlock --replace --components=secrets,pkcs11,ssh`
   (via `runuser` into the user session bus) to create/unlock the empty-password
   "login" keyring, because auto-login supplies no PAM password to unlock it.
4. Calls `grdctl rdp set-tls-cert` / `set-tls-key` / `enable`.
5. Calls `grdctl rdp set-credentials <user> <password>`.
6. Calls `grdctl rdp disable-view-only`.

The per-user `gnome-remote-desktop.service` (user unit) is started at
`graphical.target` and, at RDP-connect time, reads the stored RDP password from the
GNOME Keyring Secret Service (`org.freedesktop.secrets`). grd version in tree: **50.1**.

## Problem Definition

RDP connections to auto-login hosts (reproduced on `vexos-vmc`) fail: the client
connects at the TCP layer but the session hangs at "Connecting…" and never
authenticates. The daemon logs, on **every** connection attempt:

```
[RDP] Couldn't retrieve RDP credentials: The name is not activatable
```

Root cause (empirically verified):

- Step 3's `gnome-keyring-daemon --replace` **kills the keyring daemon that the
  already-running `gnome-remote-desktop` user daemon is bound to** and starts a new
  one. The grd daemon is never restarted, so its Secret Service connection points at
  the dead daemon. `org.freedesktop.secrets` is then either unowned or owned by a
  non-D-Bus-activatable daemon, so grd's credential lookup fails with
  "The name is not activatable" and the RDP connection is aborted before auth.
- The step is run from a **root** service via `runuser`, so the replacement keyring
  daemon lives in the `vexos-rdp-setup.service` cgroup rather than the session, which
  makes the dead-binding window worse on any service restart.

Verification performed:
- `xfreerdp +auth-only` against `vexos-vmc` hangs 25 s with no server response, vs
  the working desktop which responds in ~13 ms.
- Manually running `systemctl --user restart gnome-remote-desktop.service` on
  `vexos-vmc` **fixed** it (probe then responded in 13 ms).
- Re-running `vexos-rdp-setup.service` (which `--replace`s the keyring but does not
  restart grd) **re-broke** it.

The canonical auto-login RDP recipe
(<https://gist.github.com/ZetaTom/cd5cf7722c1c8c68416001d32ef3acac>) performs the
missing step: after unlocking the keyring and setting credentials it runs
`systemctl --user restart gnome-remote-desktop.service`. Our module omits it.

## Proposed Solution Architecture

Add the missing rebind step to `vexos-rdp-setup.service`: after the keyring is
unlocked and all `grdctl` configuration (including `set-credentials`) is applied,
**restart the user `gnome-remote-desktop.service`** in the user session so it rebinds
its Secret Service connection to the live (unlocked) keyring daemon.

This is the minimal change that resolves the verified root cause and matches the
upstream community recipe. It keeps the existing architecture (root service,
`--replace` unlock) intact — no change to credential storage, no switch to
`grdctl --system` remote-login (which would change the sharing model from
"share the auto-login session" to "spawn a fresh login session" and affects all
importing roles). Simplicity/surgical: one added command plus one path entry.

### Considered and rejected

- **Switch to `grdctl --system` remote-login** (system-level credentials, no user
  keyring): eliminates the keyring dependency entirely but changes RDP semantics for
  every importing role (desktop/server/htpc) from screen-sharing the live session to
  a separate headless login session. Out of scope; larger blast radius; not requested.
- **Drop `--replace` and delegate unlock to the session keyring daemon**: potentially
  more robust (session-owned daemon persists across service restarts) but the
  delegation/creation semantics of `--unlock` without `--replace` are version-
  dependent and unverified; higher risk to the currently-working desktop. Deferred.
- **Capture and re-export the keyring env from `--replace`**: unnecessary because all
  `grdctl` calls and the grd daemon use the same session bus
  (`DBUS_SESSION_BUS_ADDRESS`), so they resolve the same `org.freedesktop.secrets`
  owner. The missing piece is the grd rebind, not env propagation.

## Implementation Steps (Module Architecture Pattern — Option B)

`modules/remote-desktop.nix` is a universal base module imported by the roles that
need it; the change is unconditional within it (no new `lib.mkIf`, no role gating),
consistent with Option B.

1. Add `pkgs.systemd` to the service `path` so `systemctl` is available.
2. After the existing `grdctl rdp disable-view-only` call, add a final step that
   restarts the user gnome-remote-desktop daemon in the session:

   ```sh
   runuser -u <user> -- \
     env HOME="$home" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_RUNTIME_DIR="$runtime" \
     systemctl --user restart gnome-remote-desktop.service
   ```

3. Update the module header comment to document that the trailing grd restart is
   required so the daemon rebinds to the keyring the `--replace` step swapped in.

## Dependencies

None new. `pkgs.systemd` (already in the closure) provides `systemctl`. No external
libraries; Context7 not applicable (no new dependency).

## Configuration Changes

None to user-facing options. `vexos.remoteDesktop.passwordFile` unchanged. No
`configuration-*.nix` edits required — the fix is entirely inside the shared module.

## Risks and Mitigations

- **Risk:** Restarting grd briefly drops any in-progress RDP session during the setup
  run. **Mitigation:** the setup service runs once at boot before any client connects;
  a restart there is inconsequential. On the physical desktop it restarts grd shortly
  after login — harmless.
- **Risk:** `systemctl --user` unavailable if the user systemd manager isn't up yet.
  **Mitigation:** the service already waits for the session D-Bus socket
  (`/run/user/$uid/bus`); the user manager is up by then. `restart` also starts the
  unit if not already running.
- **Residual limitation (unchanged by this fix):** the replacement keyring daemon
  still lives in the root service cgroup, so a manual restart of
  `vexos-rdp-setup.service` still needs grd to rebind — which this change now performs
  automatically as the service's final step. Documented in the header comment.

## Addendum (2026-07-19): restart ordering was still wrong

Live testing after the initial fix shipped showed a *different* failure:
`grdctl status --show-credentials` on `vexos-vmc` reported a stale password from an
earlier cycle, not the value most recently set via `just setup-rdp`. Root cause: the
initial fix restarted `gnome-remote-desktop.service` as the **last** step, after
`grdctl rdp set-credentials` had already run. At the moment `set-credentials`
executes, the daemon is still bound to its pre-existing (stale) Secret Service
connection — the keyring `--replace` a few lines earlier swapped the keyring daemon,
but grd itself doesn't know to reconnect until the restart, which happens *after*
the write. The credential write during that window lands nowhere grd can read
consistently, so after the restart the daemon may expose a leftover value from a
previous successful cycle instead of the one just set.

**Corrected fix:** move the `systemctl --user restart gnome-remote-desktop.service`
call to immediately after the keyring unlock/`sleep 2`, **before** any `grdctl`
calls (cert, enable, credentials, view-only). Every subsequent `grdctl` call in the
script then talks to a daemon already bound to the fresh keyring — eliminating the
stale-connection window entirely, for both the TLS/enable calls and credentials. A
short `sleep` is added after the restart to let the user service re-register on the
session D-Bus before the first `grdctl` call hits it.

## Addendum 2 (2026-07-19): locked-screen session logoff

After the restart-ordering fix, live testing against `vexos-office` showed
authentication now succeeds (confirmed via `xfreerdp` probe: full negotiation,
`CONNECTION_STATE_CAPABILITIES_EXCHANGE_DEMAND_ACTIVE`, `gdi_init_ex` framebuffer
setup) but the server immediately terminates the session with
`ERRINFO_LOGOFF_BY_USER`. Root cause: GNOME Remote Desktop refuses to serve a
**locked** screen by design (confirmed via GNOME's own GitLab issue #16, "Remote
desktop with locked local screen"). `modules/gnome.nix` sets
`org/gnome/desktop/screensaver.idle-delay = 300` with `lock-delay = 0`, so any
machine idle for 5+ minutes is locked, and grd then rejects/logs-off any incoming
RDP connection outright. This is not a bug in our module — it's intentional GNOME
behavior — but it defeats the user's explicit goal of unattended, walk-away-and-
reconnect-later access.

**Fix:** add the `allow-locked-remote-desktop` GNOME Shell extension
(`pkgs.gnomeExtensions.allow-locked-remote-desktop`, nixpkgs version 17, binary
cached, confirmed via its bundled `metadata.json` to declare
`"shell-version": ["45","46","47","48","49","50"]` — i.e. explicitly GNOME-50
compatible) to `modules/gnome.nix`'s `commonExtensions` list, the same mechanism
already used for `tailscale-status` and `caffeine`. This is a well-known, actively
maintained (upstream GitHub: jikamens/allow-locked-remote-desktop) extension built
specifically to patch this GNOME restriction.

**Security tradeoff (explicitly accepted by the user):** the extension's own
documentation states that if a remote RDP client connects to a locked screen and
unlocks it, the **physical local console is also unlocked** — not just the remote
view. Anyone with RDP credentials and network access can therefore unlock the
physical machine. Given the user's stated threat model (Tailscale-only access,
explicit preference for simplicity over security for this feature), this is an
accepted tradeoff, not an oversight.

**Placement decision:** added to `modules/gnome.nix` `commonExtensions` (universal,
all GNOME roles) rather than via `vexos.gnome.extraExtensions` from
`remote-desktop.nix`, because `extraExtensions` is only actually consumed by
`modules/gnome-desktop.nix`'s `enabled-extensions` — `gnome-server.nix`,
`gnome-htpc.nix`, and `gnome-stateless.nix` do not include it. Using
`extraExtensions` would silently fail to activate the extension on server/htpc
roles despite installing the package. This wiring gap is flagged for the user but
left unfixed — it's a pre-existing, separate issue outside this change's scope.

## Validation

- `nix flake show --impure` (structure).
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`,
  `.#vexos-desktop-nvidia`, `.#vexos-desktop-vm` (module is display-role scoped).
- `bash scripts/preflight.sh`.
- Post-deploy runtime check on `vexos-vmc`: after `nixos-rebuild switch` + reboot,
  `xfreerdp +auth-only` responds in ms (not a 25 s hang) and Remmina connects.
