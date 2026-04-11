# VexOS Stateless VM Boot — Phase 2 Issue Diagnosis & Fix Spec

**Date**: 2026-04-11  
**Scope**: `vexos-stateless-vm` (and all stateless variants)  
**Symptoms**: auto-reboot during `nixos-rebuild switch`, followed by black screen with blinking cursor  
**Status**: AWAITING IMPLEMENTATION

---

## 1. Executive Summary

The previous fix to the stateless boot loop introduced two new regressions by adding
`boot.initrd.systemd.enable = true` to `modules/impermanence.nix`. This single line is
the common root cause of **both** problems:

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Auto-reboot during switch | `boot.initrd.systemd.enable = true` causes `switch-to-configuration-ng` to detect initrd divergence and trigger a kexec/reboot | Remove `boot.initrd.systemd.enable = true` from impermanence.nix |
| Black screen with blinking cursor | Plymouth running inside failed/incomplete systemd-initrd provides no visual output in a VM context; impermanence bind-mounts may fail silently | Same fix — revert to busybox initrd mode |

The actual fix for the original boot loop (which was applied correctly alongside the
wrong `systemd.enable` line) was:
- `fileSystems."/nix".neededForBoot = lib.mkForce true`
- `boot.initrd.availableKernelModules = lib.mkDefault ["btrfs"]`

Those two changes are correct and must be **kept**. Only `boot.initrd.systemd.enable = true`
must be reverted. Additionally, `availableKernelModules` should be upgraded to
`kernelModules` for the btrfs entry to guarantee force-loading order.

---

## 2. System Architecture Reference

```
flake.nix
  └── vexos-stateless-vm
        ├── /etc/nixos/hardware-configuration.nix  (host, not in repo)
        ├── hosts/stateless-vm.nix
        │     ├── configuration-stateless.nix
        │     │     └── modules/impermanence.nix   ← PROBLEM FILE
        │     ├── modules/gpu/vm.nix
        │     └── modules/stateless-disk.nix       ← SECONDARY CHANGE NEEDED
        └── impermanence.nixosModules.impermanence  (nix-community/impermanence)
```

**Boot sequence (desired):**
1. systemd-boot loads kernel + initrd
2. initrd: loads kernel modules → mounts `/nix` (Btrfs @nix) → mounts `/persistent`
   (Btrfs @persist) → runs impermanence bind mounts → switch-root to tmpfs `/`
3. userland systemd starts from `/nix/store/…`
4. NixOS activation creates `/etc`, users, symlinks
5. GDM auto-login → GNOME Wayland session

---

## 3. Issue 1 — Auto-Reboot During `nixos-rebuild switch`

### 3.1 Root Cause

`modules/impermanence.nix` line 88 sets:

```nix
boot.initrd.systemd.enable = true;
```

This is an **initrd-time-only** setting. It changes whether the initrd is built as a
busybox shell environment or a minimal systemd environment. The keystone fact is:

**This setting changes the stored derivation path of the initrd.**

In NixOS 25.11, `system.switch.enableNg = true` is the default. The Rust-based
`switch-to-configuration-ng` binary (installed at
`/nix/store/…-switch-to-configuration-ng-…/bin/switch-to-configuration`) compares:

```
/run/booted-system/initrd  ← path to the initrd used at current boot
vs.
<new-closure>/initrd        ← path to the initrd in the new configuration
```

When `boot.initrd.systemd.enable` transitions from `false` (previous default) to `true`
(now set by impermanence.nix), these two paths diverge completely — they point to
entirely different derivations. In NixOS 25.11, this divergence causes
`switch-to-configuration-ng` to signal that a full system restart is required to load
the new initrd. Depending on whether kexec is available in the running environment,
this manifests as either:

- `systemctl kexec` (instantaneous kexec into new kernel+initrd), or  
- `systemctl reboot` (BIOS/EFI reboot cycle)

Either way: **the system reboots mid-switch**, which the user observes as
"starts restarting services, then immediately reboots."

### 3.2 Why `boot.initrd.systemd.enable = true` Is Wrong Here

This setting only affects what happens *inside* the initrd — before `switch_root`. Once
userland systemd starts, it is irrelevant to the running system. Therefore:

1. Setting it via `nixos-rebuild switch` provides **no benefit to the currently running
   system** — it only takes effect after a manual reboot.
2. Because `switch-to-configuration-ng` compares initrd paths, adding this setting via
   `switch` unconditionally causes a reboot every first time it appears — defeating the
   purpose of `nixos-rebuild switch` vs `nixos-rebuild boot`.
3. More critically: on a system running the stateless configuration long-term, every
   `nixos-rebuild switch` that coincides with a nixpkgs input update (which changes the
   initrd derivation path) would trigger another kexec. This compounds into a
   reliability problem.

### 3.3 Specific Config Attribute Path

```
modules/impermanence.nix → config.boot.initrd.systemd.enable = true
```

### 3.4 Does `boot.initrd.systemd.enable = true` Need to Be Reverted?

**YES — remove it from `modules/impermanence.nix` entirely.**

The `nix-community/impermanence` NixOS module supports **both** initrd modes:

| Mode | Mechanism | Status |
|------|-----------|--------|
| Busybox initrd (`systemd.enable = false`) | `boot.initrd.postMountCommands` shell hook | Stable, widely used, correct |
| Systemd initrd (`systemd.enable = true`) | `boot.initrd.systemd.services.impermanence` unit | Supported but less battle-tested |

With `boot.initrd.systemd.enable = false` and the correct `neededForBoot` + btrfs
module settings already applied, impermanence bind-mounts run correctly via
`boot.initrd.postMountCommands` in the busybox initrd. The previous boot loop was **not
caused by the wrong initrd mode** — it was caused by missing `neededForBoot` and
missing btrfs kernel module, both of which are now fixed.

If `systemd.enable = true` is desired in the future, it must be set **before first
installation** (present in the config when `nixos-install` is called), not introduced
via `nixos-rebuild switch`. Setting it at install time means the initrd at first boot
already matches the config, and subsequent switches don't see a divergence.

---

## 4. Issue 2 — Black Screen with Blinking Cursor After Reboot

### 4.1 Root Cause (Primary)

After the auto-reboot, the system boots into the new configuration with
`boot.initrd.systemd.enable = true`. This triggers a cascade of visual and mount-ordering
problems specific to the VM environment:

**Plymouth in systemd-initrd on a VM guest fails to render:**

`modules/system.nix` sets `boot.plymouth.enable = true` unconditionally. With
`boot.initrd.systemd.enable = true`, Plymouth runs as `plymouth.service` *inside* the
systemd initrd, using the kernel's KMS/DRM framebuffer. In a QEMU/VirtualBox VM:

- VirtualBox VGA (`vboxvideo`) does **not** provide a DRM KMS device compatible with
  Plymouth's DRM backend in the initrd
- `virtio_gpu` is in `boot.initrd.kernelModules` (from `modules/gpu/vm.nix`), but
  virtio-gpu KMS initialisation in systemd-initrd may not complete before Plymouth
  tries to attach, leaving Plymouth with no display device
- Plymouth runs successfully (no crash), but renders nothing → **black Plymouth frame**
- The kernel params `quiet splash loglevel=3` suppress all text fallback output
- The VT1 cursor blinks underneath the black Plymouth frame

The user sees a black screen with a blinking cursor = Plymouth black frame + VT cursor
visible through it.

### 4.2 Root Cause (Secondary — reinforces black screen even if Plymouth worked)

With `boot.initrd.systemd.enable = true`, the `nix-community/impermanence` module
generates `boot.initrd.systemd.services.impermanence` which runs bind-mounts. This
service must declare `After = "sysroot-persistent.mount"`.

If the `sysroot-persistent.mount` unit name derivation in the current version of
`nix-community/impermanence` does not exactly match the escaped unit name NixOS
generates for `fileSystems."/persistent"`, the `After` ordering is broken and the
impermanence service runs before `/sysroot/persistent` is mounted. This results in:

- Bind-mount source `/sysroot/persistent/var/lib/nixos` does not exist
- `mount --bind` fails with ENOENT
- `/var/lib/nixos` on the tmpfs root remains **empty** after switch-root
- NixOS activation's `nixos-ensure-no-uid-conflicts` cannot write `uid-map` 
- User account setup fails silently → GDM auto-login fails → system reaches
  `multi-user.target` with no graphical session

Combined with Plymouth holding TTY1 black: the user sees only a blinking cursor.

### 4.3 Why This Differs from the Previous Boot Loop

The previous boot loop was caused by the busybox initrd failing to find `/nix` (the Nix
store) because:
1. Btrfs kernel module was not in the initrd
2. `/nix` did not have `neededForBoot = true`

Both of those are now fixed. The new black screen is specifically a **graphical/display
and systemd-initrd ordering problem** layered on top of a working boot. The system IS
booting; the graphical environment is what fails.

---

## 5. Required Code Changes

### 5.1 `modules/impermanence.nix` — Remove systemd-initrd directive

Remove the entire `boot.initrd.systemd.enable = true` block (lines 80–92 of the
current file, including its comment block).

**Before:**
```nix
    # ── Systemd initrd ─────────────────────────────────────────────────────
    # Required for a tmpfs-root system.  systemd-initrd provides:
    #   • Reliable mount ordering via unit dependencies (Before=/After=)
    #   • Correct integration with impermanence.nixosModules.impermanence
    #     (which generates systemd mount units in the initrd when this is true)
    #   • Correct Plymouth integration (plymouth.service in initrd namespace)
    #   • Emergency mode from initrd store (not /nix) on mount failure
    boot.initrd.systemd.enable = true;
```

**After:** *(entire block deleted)*

### 5.2 `modules/stateless-disk.nix` — Promote btrfs from `availableKernelModules` to `kernelModules`

`availableKernelModules` includes a module in the initrd image but relies on udev
hotplug events to actually load it. For a stateless root built on Btrfs, there is no
udev event for an already-present block device during very early initrd — the module
must be force-loaded. `kernelModules` guarantees unconditional early load.

**Before:**
```nix
      boot.initrd.availableKernelModules = lib.mkDefault [ "btrfs" ];
```

**After:**
```nix
      boot.initrd.kernelModules = lib.mkDefault [ "btrfs" ];
```

**Note:** `hardware-configuration.nix` may already put `btrfs` in
`availableKernelModules`; the `lib.mkDefault` in our override means it won't conflict
— it simply ensures `btrfs` also appears in `kernelModules` if not overridden
elsewhere.

---

## 6. Files That Need to Change

| File | Change |
|------|--------|
| `modules/impermanence.nix` | Remove `boot.initrd.systemd.enable = true` and its comment block |
| `modules/stateless-disk.nix` | Change `availableKernelModules` → `kernelModules` for the `btrfs` entry |

---

## 7. Files That Must NOT Change

| File | Reason |
|------|--------|
| `modules/stateless-disk.nix` — `neededForBoot = lib.mkForce true` | Correct; must remain |
| `modules/impermanence.nix` — `fileSystems."/".options = lib.mkForce [...]` | Correct; must remain |
| `modules/impermanence.nix` — `/nix` neededForBoot assertion | Correct; must remain |
| `modules/impermanence.nix` — `/` tmpfs assertion | Correct; must remain |
| `configuration.nix` / `configuration-stateless.nix` | No changes needed |
| `hosts/stateless-vm.nix` | No changes needed |
| `flake.nix` | No changes needed |

---

## 8. Post-Fix Expected Boot Sequence

After applying the two changes:

1. `nixos-rebuild switch` applies the new config **without auto-rebooting** because
   the initrd derivation path no longer changes between switches (busybox initrd stays
   busybox initrd unless the kernel or initrd modules change).

2. On the next manual reboot (or after the first kernel-changed kexec), the busybox
   initrd:
   - Loads `btrfs` (forced via `kernelModules`)
   - Mounts `/nix` (Btrfs @nix, `neededForBoot = true`)
   - Mounts `/persistent` (Btrfs @persist, `neededForBoot = true`)
   - Runs impermanence's `boot.initrd.postMountCommands` to bind-mount
     `/persistent/var/lib/nixos` → `/var/lib/nixos` on the tmpfs root
   - switch-root to tmpfs `/`

3. Userland systemd starts, NixOS activation runs, GDM auto-login proceeds. Plymouth
   works correctly in busybox-initrd mode (it ran correctly before this regression).

4. No black screen: Plymouth in busybox-initrd hands off to GNOME Wayland.

---

## 9. Note on Future Use of `boot.initrd.systemd.enable = true`

If systemd-initrd is desired for this project in the future:

1. The setting must be present **at nixos-install time** — it cannot be applied via
   `nixos-rebuild switch` on a system booted with busybox initrd without triggering the
   kexec/reboot.
2. When first setting it, use `nixos-rebuild boot` (writes new boot entry but does not
   switch) then manually reboot. This avoids the mid-switch reboot.
3. Add it to the host config (e.g., `hosts/stateless-vm.nix`) rather than the shared
   module, so it can be rolled out gradually and is explicit in the host spec.
4. Verify impermanence's `boot.initrd.systemd.services` ordering against your specific
   NixOS version before deploying.

---

## 10. Build Validation Required

After implementation, verify:

```bash
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-stateless-vm
sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd
sudo nixos-rebuild dry-build --flake .#vexos-stateless-nvidia
```

All three stateless variants must evaluate cleanly. The assertions in
`modules/impermanence.nix` will confirm that `neededForBoot = true` is still set for
both `/nix` and `/persistent`.

---

## 11. Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Removing `systemd.enable` breaks impermanence | Very Low | busybox initrd mode is the primary supported path |
| `kernelModules` change conflicts with hardware-configuration.nix | Low | `lib.mkDefault` allows hardware-configuration.nix to override |
| Boot loop returns | Low | `neededForBoot` and `btrfs` in `kernelModules` address the original cause |
| Plymouth still black in VM | Low | Plymouth has always worked in busybox-initrd mode for this project |
