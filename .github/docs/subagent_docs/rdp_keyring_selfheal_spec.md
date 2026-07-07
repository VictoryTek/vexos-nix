# Spec: RDP keyring self-heal — eliminate manual login.keyring reset

## Current State Analysis

`modules/remote-desktop.nix` runs `systemd.services.vexos-rdp-setup` (system service,
root, `wantedBy graphical.target`). It waits for the autologin user's session D-Bus
socket, then calls `grdctl rdp enable / set-credentials / disable-view-only` via
`runuser -u <user>` with `DBUS_SESSION_BUS_ADDRESS` pointed at that session.

`grdctl` stores the RDP password in the user's GNOME Keyring "login" collection via
libsecret. `modules/gnome.nix` sets
`security.pam.services.gdm-autologin.enableGnomeKeyring = true`, which unlocks that
collection **only if** PAM supplies password material during login. Auto-login never
calls `pam_authenticate`, so `pam_gnome_keyring` receives no password data at all
(not even an empty string) — it cannot unlock, and it cannot create the collection
if missing.

## Problem Definition

Observed on `vexos-vmc` (server-intel role) across two separate rebuilds:
- Before any manual keyring changes: `Cannot create an item in a locked collection`
  (login.keyring exists, locked, PAM never unlocked it).
- After the user deleted `~/.local/share/keyrings/login.keyring` without a full
  reboot/re-login cycle: `Object does not exist at path
  "/org/freedesktop/secrets/collection/login"` (no collection exists at all — nothing
  ever recreated it, because the live autologin session's `gnome-keyring-daemon`
  process was never restarted, and even a fresh login via autologin has no password
  material to create one).

The currently-documented fix (`rm ~/.local/share/keyrings/login.keyring && sudo
reboot`, once per machine) is a manual, host-specific, non-idempotent workaround.
It doesn't survive being retried without a real interactive reboot+re-login cycle,
and provides no protection against the collection becoming locked/missing again in
the future (e.g. after a keyring package upgrade resets local state).

`grdctl --system` (TPM-backed system daemon mode) was already evaluated and rejected
in a prior session — see `rdp_system_daemon_creds_spec.md` and
`rdp_unified_system_service_spec.md` — because GNOME Remote Desktop 50.1's system
daemon requires a TPM for credential storage, and neither this VM (no vTPM) nor the
physical server-intel host have one. That path is not available.

## Proposed Solution

Make `vexos-rdp-setup.service` self-heal the keyring on every run instead of relying
on PAM or a one-time manual step.

`gnome-keyring-daemon --unlock` reads a password from stdin over the target session's
D-Bus and:
- Creates the "login" collection with that password if it doesn't exist yet.
- Unlocks the existing "login" collection if the password matches.
- `--replace` takes over the already-running daemon instance for that session so the
  live GNOME session's keyring references get repointed to the freshly-unlocked state
  (needed because the autologin session's keyring daemon has usually been running
  since boot, before this service fires).

Adding a single step to the existing script, run in the same `runuser` session-bus
environment already established for the `grdctl` calls, immediately before them:

```bash
printf '' | runuser -u "$username" -- \
  env HOME="$home" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_RUNTIME_DIR="$runtime" \
  gnome-keyring-daemon --unlock --replace --components=secrets,pkcs11,ssh >/dev/null
```

This is idempotent and safe to run on every `graphical.target` start:
- Missing collection → created fresh with an empty password.
- Existing empty-password collection → unlocked (matches).
- Existing collection with a real user-set password → unlock fails harmlessly (wrong
  password); script continues without `set -e` exactly as it already does for the
  existing non-fatal `grdctl` calls, so it never breaks the rebuild.

No PAM changes needed. `security.pam.services.gdm-autologin.enableGnomeKeyring = true`
in `modules/gnome.nix` stays as-is — it's still useful as a no-op-safe unlock attempt
for any *interactive* re-login (e.g. after `loginctl terminate-session`), but is no
longer load-bearing for RDP; its comment will be updated to stop describing the manual
`rm login.keyring` step as a required prerequisite for RDP, since it no longer is.

## Implementation Steps (Module Architecture Pattern — Option B)

`modules/remote-desktop.nix` is a role-addition-style shared module already imported
only by the roles that need it (desktop, server, htpc) — no `lib.mkIf` role guards
needed or added.

1. `modules/remote-desktop.nix`: insert the `gnome-keyring-daemon --unlock --replace`
   step into the existing `script`, after the session-bus wait loop and before the
   three existing `grdctl` calls. Update the module's header comment (lines 12-24) to
   describe the self-heal mechanism instead of the manual one-time keyring-reset
   prerequisite.
2. `modules/gnome.nix`: update the comment above
   `security.pam.services.gdm-autologin.enableGnomeKeyring = true` (lines 135-141) to
   remove the now-inaccurate claim that deleting `login.keyring` is a required
   prerequisite for RDP credential setup.

## Dependencies

`gnome-keyring-daemon` binary ships in the `gnome-keyring` package, which is already
an implicit dependency of `services.desktopManager.gnome.enable` (pulled in via
`pkgs.gnome-remote-desktop`'s runtime closure and the GNOME session itself — it's
already on the live session's PATH). Add `pkgs.gnome-keyring` explicitly to the
service's `path` list for reliability rather than relying on transitive closure.
No new flake inputs. Context7 not applicable (not a versioned library API — this is a
CLI tool documented by its own manpage, verified via ArchWiki/manpages.debian.org).

## Configuration Changes

None beyond the two files above. No new options, no `system.stateVersion` change, no
new flake inputs.

## Risks and Mitigations

- **Risk:** `--replace` without `GNOME_KEYRING_CONTROL` set (older/legacy env var) may
  not perfectly hand off from the live session's daemon in all GNOME versions.
  **Mitigation:** modern `gnome-keyring-daemon` coordinates primarily over D-Bus, not
  the legacy control-socket env var; `DBUS_SESSION_BUS_ADDRESS` pointed at the real
  session bus is sufficient for the D-Bus-based replace/reconnect path used by current
  GNOME (46+). If replace ever silently fails, worst case is unchanged from today's
  behavior (grdctl fails, service logs a non-fatal error) — no regression.
- **Risk:** User has intentionally set a real (non-empty) keyring password.
  **Mitigation:** unlock attempt with an empty password fails harmlessly; existing
  keyring/collection and its contents are untouched (no delete, no overwrite).
- **Risk:** Order-of-operations — unlocking before the wait-loop confirms the session
  bus exists would target a socket that doesn't exist yet.
  **Mitigation:** the unlock step is inserted after the existing wait loop, using the
  same `bus`/`runtime`/`home` variables already validated by it.
