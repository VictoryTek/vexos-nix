# Phase 1 Spec — stateless_vm_boot_locked_root

## Problem Definition

After a completed fresh install via `scripts/stateless-setup.sh`, the stateless VM role fails
to boot. The systemd-based initrd (Stage 1) enters emergency mode immediately after
`systemd-udevd` starts, and then reports:

```
Cannot open access to console, the root account is locked.
See sulogin(8) man page for more details.
```

This leaves the system completely unbootable and undebuggable.

## Current State Analysis

### Root Cause 1 — `virtio_blk` missing from initrd (boot failure trigger)

`modules/gpu/vm.nix` adds `virtio_gpu` to `boot.initrd.kernelModules` for display, but does NOT
add `virtio_blk` — the VirtIO block device driver required for `/dev/vda` to appear in the initrd.

```nix
# modules/gpu/vm.nix (current)
boot.initrd.kernelModules = [ "virtio_gpu" ];
```

QEMU/KVM guests use VirtIO Block (`/dev/vda`) as the disk device. For this device to appear in
the initrd:
1. `virtio_pci` must be in `availableKernelModules` (typically auto-detected by nixos-generate-config)
2. `virtio_blk` must be in `kernelModules` OR `availableKernelModules` **and** present in the initrd's module directory

The NixOS live ISO (used to run `stateless-setup.sh`) compiles `virtio_blk` directly into the
kernel (built-in, not modular). Therefore `nixos-generate-config` does NOT add it to
`boot.initrd.availableKernelModules`. The installed NixOS kernel has `virtio_blk` as a module,
but since it's absent from both `kernelModules` and `availableKernelModules` in the evaluated
config, it is not bundled into the initrd.

**Consequence:** During the first real boot, the systemd initrd starts udev, `virtio_pci` is
loaded (from `availableKernelModules` in hardware-configuration.nix), but `virtio_blk` is not
available in the initrd module directory. `/dev/vda` never appears. The btrfs mounts for
`/nix` and `/persistent` (both `neededForBoot = lib.mkForce true` from `stateless-disk.nix`)
are waiting for a device that never shows up. systemd drops to emergency mode.

The screenshot confirms this: the explicit `kernelModules` list shows `btrfs`, `dm_mod`,
`virtio_balloon`, `virtio_console`, `virtio_gpu`, `virtio_rng` — but NOT `virtio_blk`.

### Root Cause 2 — Root account locked in systemd initrd (blocking recovery)

`modules/impermanence.nix` sets:
```nix
users.mutableUsers = false;
```

With `mutableUsers = false`, NixOS generates `/etc/shadow` entirely from the Nix config. No
`users.users.root.hashedPassword` is set anywhere in the stateless configuration, so NixOS
assigns root the default locked password (`!!` in `/etc/shadow`).

The systemd-based initrd on NixOS includes the system's `/etc/shadow`. When it drops to
emergency mode, `sulogin` checks root's shadow entry and refuses to open the emergency shell
because root is locked.

**Consequence:** The user cannot type any commands, cannot run `journalctl -xb`, and cannot
determine what failed. The machine is both unbootable and undebuggable.

## Affected Files

- `modules/gpu/vm.nix` — missing `virtio_blk` in initrd kernel modules
- `configuration-stateless.nix` — no root password set; root locked under mutableUsers = false

## Proposed Solution

### Fix 1 — Add `virtio_blk` to `boot.initrd.kernelModules` in `modules/gpu/vm.nix`

```nix
boot.initrd.kernelModules = [ "virtio_gpu" "virtio_blk" ];
```

`virtio_blk` is forced into the initrd and loaded early, before udev attempts to mount
filesystems. `/dev/vda` appears reliably, the btrfs mounts succeed, emergency mode is avoided.

This is placed in `modules/gpu/vm.nix` (not in the stateless-specific files) because ALL VM
roles that use `/dev/vda` as the disk require `virtio_blk` in the initrd. Fixing it once at
the VM GPU module level is correct per the Option B architecture pattern.

### Fix 2 — Set `users.users.root.hashedPassword = ""` in `configuration-stateless.nix`

```nix
users.users.root.hashedPassword = "";
```

An empty hash in `/etc/shadow` means "no password required" — root can log in without a
password. This is the standard NixOS mechanism for emergency shell access on systems with
`mutableUsers = false`.

This is placed in `configuration-stateless.nix` because:
- Only the stateless role sets `mutableUsers = false` (done in `impermanence.nix`)
- Other roles leave `mutableUsers = true`, so root's password is managed mutably and
  emergency access works via the install-time root password
- The stateless machine is ephemeral by design; persistent sensitive data that root-only could
  access doesn't exist on a tmpfs-rooted system

## Implementation Steps

1. Edit `modules/gpu/vm.nix`: change `boot.initrd.kernelModules = [ "virtio_gpu" ]` to
   `boot.initrd.kernelModules = [ "virtio_gpu" "virtio_blk" ]`

2. Edit `configuration-stateless.nix`: add `users.users.root.hashedPassword = "";` under the
   `# ---------- Users ----------` section with a comment explaining the rationale

## Dependencies

No new external dependencies. Internal-only NixOS option changes.

## Context7

Not required — no external libraries involved.

## Risks and Mitigations

- **Risk:** Setting root `hashedPassword = ""` could allow unauthorized root access on a
  multi-user shared system.
  **Mitigation:** The stateless role is a personal ephemeral workstation (not a server). The
  machine already resets all user state on every reboot. Root access without password is
  acceptable in this context. The option is placed in `configuration-stateless.nix` (not in a
  shared module), so it cannot accidentally apply to the server role.

- **Risk:** Other VM roles (desktop-vm, server-vm) might also be missing `virtio_blk`.
  **Mitigation:** The fix is in `modules/gpu/vm.nix` which ALL VM roles import. This fixes
  all VM roles simultaneously with a single change, which is the correct scope.
