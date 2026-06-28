# Spec: Fix server RDP — system service running as root

## Problem

The server (`vexos-server-intel`) has auto-login enabled. Auto-login bypasses the
PAM password prompt, so the GNOME Keyring's "login" keyring is never unlocked.

`modules/remote-desktop.nix` defines a USER systemd service (`vexos-rdp-setup.service`)
that calls `grdctl rdp set-credentials`. This command stores credentials in the GNOME
Keyring via libsecret. With the keyring locked, the call fails:

```
Cannot create an item in a locked collection
```

Additionally, the password file `/etc/nixos/secrets/rdp-password` is root-owned and
lives in a `0700 root:root` directory. The user service (running as `nimda`) cannot
read it — `cat` silently fails, the `password` variable is empty, and the credential
call either fails or sets an empty password.

The `--system` grdctl calls added in the previous fix attempt also failed, because
`grdctl --system` from a user service context requires interactive polkit authentication
(`org.gnome.remotedesktop.configure-system-daemon`), which cannot be satisfied from a
non-interactive systemd unit.

Diagnostics from the live server confirmed all three failures:
1. `cat /etc/nixos/secrets/rdp-password: Permission denied` (user service can't read the file)
2. `Cannot create an item in a locked collection` (keyring locked under auto-login)
3. `grdctl --system status` → `AUTHENTICATION FAILED... Not authorized` (polkit blocks user service)

## Root Cause

The user-daemon approach is wrong for a server with auto-login:
- User daemon stores credentials in GNOME Keyring → blocked by locked keyring
- User service cannot read root-owned secret file
- `grdctl --system` from a user service requires polkit interactive auth → always fails

## Proposed Solution

### Architecture

Replace the user service approach (for server only) with a **system service** running as root:

- System services run as root by default → can read `/etc/nixos/secrets/rdp-password`
- Root bypasses polkit for all D-Bus calls → `grdctl --system` always succeeds
- System daemon (`gnome-remote-desktop-daemon --system`) stores credentials in
  `/var/lib/gnome-remote-desktop/` (root-owned files, no keyring)
- `gnome-remote-desktop-configuration.service` is D-Bus activated on the system bus →
  no separate WantedBy needed for the configuration helper

### Module Architecture (Option B)

Per the project's Option B pattern:
- `modules/remote-desktop.nix` — USER daemon for desktop/htpc (unchanged except removing
  the broken `--system` calls added in the previous fix, and fixing ordering)
- `modules/remote-desktop-server.nix` (NEW) — SYSTEM daemon for server roles only
- `configuration-server.nix` — swap import from `remote-desktop.nix` to
  `remote-desktop-server.nix`

No `lib.mkIf` guards. Presence in the import list is what makes content apply.

### System daemon start

`gnome-remote-desktop.service` (system) is currently "linked; preset: ignored" — the
unit file exists but it is not in `graphical.target.wants`. Our system setup service
starts it explicitly via `systemctl start gnome-remote-desktop.service` after configuring
credentials, so no WantedBy override is needed (which would risk overriding the
package-provided unit).

## Implementation Steps

### 1. Create `modules/remote-desktop-server.nix`

Defines `options.vexos.remoteDesktop.passwordFile` (same option, same default as
`remote-desktop.nix` — only one of the two is ever imported per role).

Defines `systemd.services.vexos-rdp-setup`:
- `wantedBy = ["graphical.target"]`
- `after = ["graphical.target" "dbus.service"]`
- `Type = "oneshot"`, `RemainAfterExit = true`
- No `User` override — system services run as root by default
- Script:
  ```bash
  if [ ! -f <passwordFile> ]; then exit 0; fi
  password=$(cat <passwordFile>)
  grdctl --system rdp enable
  grdctl --system rdp set-credentials <username> "$password"
  grdctl --system rdp disable-view-only
  systemctl start gnome-remote-desktop.service
  ```

### 2. Update `modules/remote-desktop.nix`

Remove the broken `--system` grdctl calls added in the previous fix attempt.
Add proper ordering (`wants`/`after`) for the user gnome-remote-desktop service
so the user daemon starts before credential setup on desktop/htpc.

### 3. Update `configuration-server.nix`

Replace:
```nix
./modules/remote-desktop.nix
```
With:
```nix
./modules/remote-desktop-server.nix
```

## Files Affected

- `modules/remote-desktop.nix` (update: remove --system calls, fix ordering)
- `modules/remote-desktop-server.nix` (new)
- `configuration-server.nix` (update: swap import)

## Dependencies

None. Internal NixOS/systemd configuration only. Context7 not required.

## Risks and Mitigations

- **Risk:** `grdctl --system rdp disable-view-only` might not exist in GNOME RD 50.1.
  **Mitigation:** The script has no `set -e`; if the command doesn't exist the script
  continues. Interactive access is still blocked only if the flag name is wrong — in that
  case a follow-up fix adds the correct flag name.
- **Risk:** `gnome-remote-desktop.service` (system) might fail to start (missing TLS cert).
  **Mitigation:** On first start the system daemon auto-generates a self-signed cert in
  `/var/lib/gnome-remote-desktop/`. The "BIO_new failed" error seen on the user daemon
  is because it had no cert; the system daemon starts fresh and generates one.
- **Risk:** `systemctl start gnome-remote-desktop.service` in the script runs at
  `graphical.target`; if the daemon is already running (e.g. after a re-run), this is a
  no-op. Safe.
- **Risk:** Polkit still required for non-root callers of `grdctl --system`.
  **Mitigation:** System service runs as root → polkit is never consulted.
