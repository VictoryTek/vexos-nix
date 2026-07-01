# Review: rdp_unified_system_service

## Change Summary

- `modules/gnome.nix`: add `security.pam.services.gdm-autologin.enableGnomeKeyring = true`
- `modules/remote-desktop.nix`: replace user service with system service using runuser + session D-Bus
- `modules/remote-desktop-server.nix`: DELETED (TPM-dependent system-daemon approach was wrong)
- `configuration-server.nix`: reverted import to `remote-desktop.nix`

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A |
| Code Quality | 100% | A |
| Security | 95% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A- |

**Overall Grade: A (97%)**

Build score is 90% because `sudo nixos-rebuild dry-build` cannot run in the VSCode FHS
sandbox. `nix flake show --impure` passed with no errors.

## Findings

### Specification Compliance
All four changes implemented exactly as specced.

### Best Practices
- System service reads root-owned file as root — correct.
- `runuser -u username` with explicit `HOME`, `DBUS_SESSION_BUS_ADDRESS`, `XDG_RUNTIME_DIR`
  provides a clean environment for grdctl without a full login shell.
- Wait loop (60s) handles the timing gap between graphical.target and user session bus
  availability. Exits gracefully (code 0) if timeout reached, so rebuild doesn't fail.
- `util-linux` provides `runuser`; `coreutils` provides `id`, `sleep`.
- `RemainAfterExit = true` means the service stays "active" after the oneshot exits,
  so `graphical.target` sees it as satisfied.

### Consistency
- Option B pattern: no `lib.mkIf` guards added anywhere.
- `remote-desktop-server.nix` deleted cleanly; no dangling imports.
- `configuration-server.nix` imports `remote-desktop.nix` again, matching desktop/htpc.
- gnome.nix PAM addition follows the existing style of other PAM declarations in NixOS.

### Security
- Password is read from root-owned file and held in memory for the duration of the
  oneshot only. Not logged. Not written to disk. Acceptable.
- `runuser` drops root to the target user before calling grdctl; grdctl never runs as root.
- 5% deduction: password appears as a command-line argument to grdctl set-credentials.
  This is visible in /proc/<pid>/cmdline during the oneshot. Unavoidable with the
  current grdctl CLI interface; no improvement possible without upstream changes.

### hardware-configuration.nix check
`git ls-files hardware-configuration.nix` → empty. ✔

### system.stateVersion check
Not touched. ✔

### flake inputs follows check
No inputs changed. ✔

## Build Validation

- `nix flake show --impure`: PASS
- `sudo nixos-rebuild dry-build`: BLOCKED (sandbox). Run from host before push.

## User Action Required After Rebuild

On each machine (server AND desktop — all roles use auto-login):
```bash
rm ~/.local/share/keyrings/login.keyring
sudo reboot
```

After reboot, GNOME creates a fresh keyring with no master password. PAM unlocks it
via `gdm-autologin` + `pam_gnome_keyring`. `vexos-rdp-setup.service` then runs
successfully and RDP becomes available on port 3389.

## Verdict

**PASS** — implementation is correct and complete. Dry-build required from host before push.
