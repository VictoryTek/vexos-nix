# Spec: Fix RDP credential setup — unified system service + PAM keyring unlock

## Problem

`grdctl rdp set-credentials` (user daemon) stores credentials in the GNOME Keyring
via libsecret. The GNOME Keyring's "login" collection must be UNLOCKED for this to
succeed. On every vexos GNOME role, `services.displayManager.autoLogin.enable = true`
is set (modules/gnome.nix line 139). Auto-login bypasses PAM password authentication,
so pam_gnome_keyring never receives the user's password and never unlocks the keyring.

Result: `Cannot create an item in a locked collection` on every machine, every rebuild.
RDP has never worked on any vexos device. TLS certificate (also keyring-stored) is also
never generated — explaining the FreeRDP `BIO_new failed for certificate` error.

Second problem: the user systemd service (`systemd.user.services.vexos-rdp-setup`)
cannot read `/etc/nixos/secrets/rdp-password` because the parent directory is enforced
as `0700 root:root` by modules/secrets.nix. The cat call silently fails, leaving
`$password` empty.

The system-daemon approach (grdctl --system) attempted in the previous fix fails on VMs
and physical servers because:
- VMs (Proxmox vTPM not configured): GNOME RD 50.1 system daemon requires TPM for
  credential storage → `Init TPM credentials failed`
- Physical server-intel: same TPM requirement applies

## Solution

### Part A — PAM: unlock keyring on auto-login (modules/gnome.nix)

`security.pam.services.gdm-autologin.enableGnomeKeyring = true`

When this is set AND the user's "login" keyring has an empty master password,
`pam_gnome_keyring.so` unlocks the collection with an empty string during auto-login.
NixOS already sets this for `gdm` (normal login) but NOT for `gdm-autologin`.

**Required one-time user action on each machine (after rebuild):**
Delete `~/.local/share/keyrings/login.keyring` and reboot. GNOME creates a fresh
keyring with no master password. pam_gnome_keyring then unlocks it automatically.

### Part B — System service with runuser (modules/remote-desktop.nix)

Replace the `systemd.user.services.vexos-rdp-setup` user service with a
`systemd.services.vexos-rdp-setup` SYSTEM service that:

1. Runs as root → can read `/etc/nixos/secrets/rdp-password`
2. Waits for the user's session D-Bus socket (`/run/user/<uid>/bus`) to appear
3. Uses `runuser -u <username>` with `DBUS_SESSION_BUS_ADDRESS` and `XDG_RUNTIME_DIR`
   set to the user's session values, so grdctl connects to the user daemon on the
   correct session bus
4. Calls `grdctl rdp enable`, `grdctl rdp set-credentials`, `grdctl rdp disable-view-only`
   as the user → daemon stores credentials in the (now unlocked) keyring

The system service triggers at `graphical.target`. With auto-login, the user session
bus appears within seconds of graphical.target. The wait loop handles the small
timing gap.

This approach is identical for all roles (desktop, server, htpc) because all use
auto-login. No role-specific module is needed.

### Part C — Remove remote-desktop-server.nix (modules/remote-desktop-server.nix)

This file was created to configure the system daemon via grdctl --system. The system
daemon is blocked by TPM requirements on VMs and physical servers. It is now dead code.
Delete it and revert configuration-server.nix to import remote-desktop.nix.

## Files Affected

- `modules/gnome.nix` — add PAM gdm-autologin gnome-keyring line
- `modules/remote-desktop.nix` — replace user service with system service + runuser
- `modules/remote-desktop-server.nix` — DELETE
- `configuration-server.nix` — revert import to remote-desktop.nix

## Dependencies

- `pkgs.util-linux` provides `runuser`
- `pkgs.coreutils` provides `id`, `sleep`, `timeout`
- No new flake inputs

## Risks and Mitigations

- **Risk:** User has not deleted their login.keyring — credentials call still fails.
  **Mitigation:** Script exits 0 (no set -e); grdctl prints an error but doesn't crash.
  User is informed of the one-time action required.
- **Risk:** Session bus not available within wait window.
  **Mitigation:** Script exits 0 gracefully with a log message; user can re-run
  `systemctl restart vexos-rdp-setup.service` after session is up, or reboot.
- **Risk:** grdctl rdp disable-view-only not present in GRD 50.1.
  **Mitigation:** No set -e; failure is non-fatal. Worst case: view-only mode stays on.
  User can run `grdctl rdp disable-view-only` manually to confirm the command name.
- **Risk:** runuser on NixOS — PATH mismatch or missing HOME.
  **Mitigation:** HOME, DBUS_SESSION_BUS_ADDRESS, XDG_RUNTIME_DIR all explicitly set.
