# Specification: Fix `sudo` ownership error in `install.sh` (v2)

## Problem Definition
When running `scripts/install.sh`, users encounter the following error during the `nixos-rebuild switch` phase:
`sudo: /run/current-system/sw/bin/sudo must be owned by uid 0 and have the setuid bit set`

Despite the script capturing the absolute path to `sudo` via `_SUDO="$(command -v sudo)"` and using it for calls within the script, the error persists. This indicates that a process spawned by the script—specifically one running in a context where `PATH` has been modified—is attempting to execute a bare `sudo` command.

## Root Cause Analysis

### The "Poisoned" PATH
In `scripts/install.sh`, the following lines are executed:
```bash
export PATH="/run/current-system/sw/bin:...:$PATH"
"$_SUDO" systemctl set-environment PATH="$PATH"
```

1. **Global Environment Pollution**: `systemctl set-environment` sets environment variables for the systemd manager. Any subsequent transient units or services started by systemd inherit this environment.
2. **`nixos-rebuild switch` Workflow**: When `nixos-rebuild switch` is called, it eventually triggers the NixOS activation script. This script is often executed via `systemd-run` as a transient unit.
3. **Execution Context**: The transient unit inherits the `PATH` set by `set-environment`. Because `/run/current-system/sw/bin` is now at the front of the `PATH`, any call to `sudo` inside the activation script (or any script it calls) resolves to `/run/current-system/sw/bin/sudo`.
4. **The Setuid Failure**: The binary at `/run/current-system/sw/bin/sudo` is a symlink/copy within the Nix store profile. For `sudo` to function, it must have the setuid bit set and be owned by root on the actual filesystem. When called from a context that doesn't handle the Nix store's setuid wrappers correctly, or when a script expects the system `sudo` (usually at `/usr/bin/sudo`), this results in the "must be owned by uid 0" error.

### Why `_SUDO` didn't fix it
The `_SUDO` variable only ensures that the *installer script itself* uses the correct binary. It does not affect the environment of the processes spawned by `nixos-rebuild` or systemd.

## Proposed Solution

### 1. Remove `systemctl set-environment PATH`
The primary goal of adding the `PATH` manipulation was to ensure `sed` (and other tools) were available during the `extraInstallCommands` phase of the bootloader setup. 

However, we have already implemented a robust fix in `template/etc-nixos-flake.nix`:
```nix
boot.loader.systemd-boot.extraInstallCommands = ''
  for f in /boot/loader/entries/*.conf; do
    [ -f "$f" ] && ${pkgs.gnused}/bin/sed -i 's/, built on [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//' "$f"
  done
'';
```
By using `${pkgs.gnused}/bin/sed`, the activation script uses the absolute path to the binary provided by Nix, making it completely independent of the `PATH` environment variable.

Consequently, the `systemctl set-environment PATH="$PATH"` call in `install.sh` is no longer necessary for the bootloader fix and is actively harmful to system stability.

### implementation Steps

1. **Edit `scripts/install.sh`**:
   - Remove the line: `export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"`
   - Remove the line: `"$_SUDO" systemctl set-environment PATH="$PATH"`
   - Remove the line: `"$_SUDO" systemctl unset-environment PATH`

2. **Maintain `_SUDO` usage**: Keep the `_SUDO` variable for the script's own calls to ensure it uses the host's `sudo` instead of any potentially ambiguous paths.

## Verification Plan

1. **Functional Test**: Run `scripts/install.sh` and verify that `nixos-rebuild switch` completes without the `sudo` ownership error.
2. **Regression Test**: Verify that the bootloader entries are still correctly modified (the `sed` command in `template/etc-nixos-flake.nix` should still execute successfully).
3. **Environment Check**: Confirm that `systemctl show-environment` does not contain a modified `PATH` after the installer runs.
