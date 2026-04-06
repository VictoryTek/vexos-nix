# Specification: snapper + btrfs-assistant

**Feature**: Automatic btrfs snapshot management with snapper and a GUI via btrfs-assistant  
**Date**: 2026-04-05  
**Status**: Draft  

---

## 1. Current State Analysis

### Repository scan

A full search of every `.nix` file under `/home/nimda/Projects/vexos-nix/` reveals:
- **No existing `services.snapper` configuration** anywhere in the tree.
- **No existing `services.btrfs.*` configuration** anywhere in the tree.
- **No `btrfs-progs`, `btrfs-assistant`, or `snapper` packages** in `modules/packages.nix`.
- `modules/performance.nix` contains unrelated kernel/ZRAM/sysctl tuning; no filesystem settings.

### Flake targets

| Output | Host file | GPU module |
|---|---|---|
| `vexos-amd` | `hosts/amd.nix` | `modules/gpu/amd.nix`, `modules/asus.nix` |
| `vexos-nvidia` | `hosts/nvidia.nix` | `modules/gpu/nvidia.nix`, `modules/asus.nix` |
| `vexos-intel` | `hosts/intel.nix` | `modules/gpu/intel.nix` |
| `vexos-vm` | `hosts/vm.nix` | `modules/gpu/vm.nix` |

All four hosts import `configuration.nix` as their shared base. The VM host uses a virtual disk; btrfs is not guaranteed there.

### nixpkgs channel

The flake pins `nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"`. All package attribute paths and module options below are verified against that channel (commit `bcd464cc`).

---

## 2. Problem Definition

The user wants:

1. **Automatic btrfs snapshots** managed by `snapper` — hourly timeline with daily/weekly/monthly retention and a boot snapshot.
2. **btrfs-assistant** — a Qt6 GUI application (version 2.2 in nixpkgs 25.11) for browsing, restoring, and diffing snapper snapshots, and for general btrfs subvolume/balance operations.

The feature is only meaningful on physical hosts (`vexos-amd`, `vexos-nvidia`, `vexos-intel`) which are expected to run on btrfs-formatted SSDs. The `vexos-vm` guest typically uses a virtual ext4 disk and **must not** have snapper services enabled.

---

## 3. Proposed Solution Architecture

### 3.1 New file: `modules/snapper.nix`

Create a dedicated module consistent with the existing pattern (one concern → one file). This module will:

- Configure `services.snapper` with a named `root` config for the root subvolume `/`.
- Enable `services.btrfs.autoScrub` for monthly data integrity checks.
- Add `pkgs.btrfs-assistant` to `environment.systemPackages`.

### 3.2 Import in physical hosts only

Add `../modules/snapper.nix` to the `imports` list in **`hosts/amd.nix`**, **`hosts/nvidia.nix`**, and **`hosts/intel.nix`**. Do **not** add it to `hosts/vm.nix`.

**Rationale for per-host import (not `configuration.nix`):**

- `vexos-vm` almost certainly does not use btrfs. If snapper configs were active on a non-btrfs root, `snapper-timeline.service` would fail at runtime.
- The module would add btrfs-assistant to the VM closure unnecessarily.
- Consistent with the existing pattern: `modules/asus.nix` is also a per-host import (only in `amd.nix` and `nvidia.nix`), not in `configuration.nix`.

### 3.3 What the NixOS snapper module provides automatically

When `services.snapper.configs` is non-empty, the NixOS module (`nixos/modules/services/misc/snapper.nix`) activates the following without any extra configuration:

| Automatically provided | Description |
|---|---|
| `pkgs.snapper` in `environment.systemPackages` | CLI tool |
| `snapperd.service` | D-Bus daemon (`org.opensuse.Snapper`) |
| `services.dbus.packages = [ pkgs.snapper ]` | D-Bus policy registration |
| `snapper-timeline.service` + `snapper-timeline.timer` | Hourly snapshot creation |
| `snapper-cleanup.service` + `snapper-cleanup.timer` | Periodic snapshot pruning |
| `snapper-boot.service` (when `snapshotRootOnBoot = true`) | Boot-time snapshot (requires config name `root`) |

The `snapper-boot.service` uses `ConditionPathExists = "/etc/snapper/configs/root"` — so the config **must be named `root`** for boot snapshots to work.

### 3.4 btrfs-assistant and D-Bus/polkit

`btrfs-assistant` communicates with `snapperd` over D-Bus (`org.opensuse.Snapper`). The D-Bus service configuration and polkit rules are provided automatically by `services.snapper` (via `services.dbus.packages = [ pkgs.snapper ]`). No additional polkit or D-Bus configuration is needed beyond enabling `services.snapper`.

The nixpkgs `btrfs-assistant` package is built with `enableSnapper = true` (the default), which embeds the Nix store path to the `snapper` binary instead of `/usr/bin/snapper`.

---

## 4. Implementation Steps

### Step 1 — Pre-activation host prerequisite (manual, one-time)

**Before** running `nixos-rebuild switch`, the user must verify:

1. The root filesystem is btrfs (`df -T /`).
2. The `/.snapshots` btrfs subvolume exists on the underlying btrfs volume:

```bash
# List subvolumes on the root btrfs volume
sudo btrfs subvolume list /

# If /.snapshots does not appear, create it:
sudo btrfs subvolume create /.snapshots
sudo chmod 750 /.snapshots
```

> **Critical**: Snapper requires the `SUBVOLUME` path to already contain a subvolume named `.snapshots`. If this subvolume does not exist, `snapper-timeline.service` will fail with a permissions/path error.

### Step 2 — Create `modules/snapper.nix`

Create the file `/home/nimda/Projects/vexos-nix/modules/snapper.nix`:

```nix
# modules/snapper.nix
# Btrfs snapshot management: snapper automatic timeline + btrfs-assistant GUI.
# Import this module only in physical host configurations (amd, nvidia, intel).
#
# One-time prerequisite on the host before the first nixos-rebuild switch:
#   sudo btrfs subvolume create /.snapshots
#   sudo chmod 750 /.snapshots
{ pkgs, ... }:
{
  # ── Snapper: automatic btrfs snapshots ────────────────────────────────────
  # Root config — snapshots the root subvolume (/).
  # The config MUST be named "root" for snapshotRootOnBoot to function
  # (snapper-boot.service conditions on /etc/snapper/configs/root).
  services.snapper = {
    snapshotRootOnBoot = true;      # extra snapshot on each boot
    snapshotInterval   = "hourly";  # systemd calendar spec; default is "hourly"
    cleanupInterval    = "1d";      # systemd time spec; default is "1d"
    persistentTimer    = true;      # re-fire missed snapshots after suspend/poweroff

    configs.root = {
      SUBVOLUME        = "/";
      FSTYPE           = "btrfs";

      TIMELINE_CREATE  = true;        # enable hourly snapshot creation
      TIMELINE_CLEANUP = true;        # enable periodic cleanup of old snapshots

      # Allow the primary user to list/diff/restore snapshots without sudo
      ALLOW_USERS      = [ "nimda" ];

      # Retention policy — conservative defaults for a desktop SSD.
      # Adjust to taste; totals ~19 snapshots in steady state plus boot snapshots.
      TIMELINE_LIMIT_HOURLY  = 5;   # keep last 5 hourly snapshots
      TIMELINE_LIMIT_DAILY   = 7;   # keep last 7 daily snapshots
      TIMELINE_LIMIT_WEEKLY  = 4;   # keep last 4 weekly snapshots
      TIMELINE_LIMIT_MONTHLY = 3;   # keep last 3 monthly snapshots
      TIMELINE_LIMIT_YEARLY  = 0;   # no yearly snapshots (personal desktop)
    };
  };

  # ── btrfs auto-scrub: monthly data integrity verification ─────────────────
  # Scrub only "/" — all subvolumes sharing the same btrfs volume are covered.
  services.btrfs.autoScrub = {
    enable      = true;
    interval    = "monthly";
    fileSystems = [ "/" ];
  };

  # ── btrfs-assistant: Qt6 GUI for snapshot management ─────────────────────
  # Communicates with snapperd over D-Bus (registered automatically above).
  # Package: pkgs.btrfs-assistant, version 2.2, nixpkgs 25.11.
  environment.systemPackages = with pkgs; [
    btrfs-assistant   # GUI management tool for btrfs/snapper
    btrfs-progs       # userspace btrfs utilities (CLI: btrfs, mkfs.btrfs, etc.)
  ];
}
```

### Step 3 — Import the module in physical host files

Edit **`hosts/amd.nix`** — add `../modules/snapper.nix`:

```nix
# hosts/amd.nix
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/amd.nix
    ../modules/asus.nix
    ../modules/snapper.nix   # ← add this line
  ];
}
```

Edit **`hosts/nvidia.nix`** — add `../modules/snapper.nix`:

```nix
# hosts/nvidia.nix
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/nvidia.nix
    ../modules/asus.nix
    ../modules/snapper.nix   # ← add this line
  ];
}
```

Edit **`hosts/intel.nix`** — add `../modules/snapper.nix`:

```nix
# hosts/intel.nix
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/intel.nix
    ../modules/snapper.nix   # ← add this line
  ];
}
```

**`hosts/vm.nix` — no change.** Snapper must NOT be added to the VM build.

### Step 4 — Validate

```bash
# Nix flake structural check (all four outputs)
nix flake check

# Dry-build each physical output
sudo nixos-rebuild dry-build --flake .#vexos-amd
sudo nixos-rebuild dry-build --flake .#vexos-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-intel

# (Optional) VM output — must still build cleanly without snapper
sudo nixos-rebuild dry-build --flake .#vexos-vm
```

---

## 5. Dependencies

| Dependency | Attribute path | Version | Source |
|---|---|---|---|
| snapper | `pkgs.snapper` (pulled in by `services.snapper`) | — (managed by nixpkgs) | nixpkgs 25.11 |
| btrfs-assistant | `pkgs.btrfs-assistant` | 2.2 | nixpkgs 25.11, `pkgs/by-name/bt/btrfs-assistant/package.nix` |
| btrfs-progs | `pkgs.btrfs-progs` | — (managed by nixpkgs) | nixpkgs 25.11 |

No new flake inputs are required. All three packages are in `nixpkgs` 25.11, which the flake already pins.

---

## 6. NixOS Module Option Reference

Sourced from `nixos/modules/services/misc/snapper.nix` at nixpkgs commit `bcd464cc` (nixos-25.11):

| Option | Type | Default | Notes |
|---|---|---|---|
| `services.snapper.snapshotRootOnBoot` | bool | `false` | Creates snapshot at boot via `snapper-boot.service`; requires config named `root` |
| `services.snapper.snapshotInterval` | str | `"hourly"` | systemd.time(7) calendar spec |
| `services.snapper.cleanupInterval` | str | `"1d"` | systemd.time(7) duration |
| `services.snapper.persistentTimer` | bool | `false` | Set `Persistent=true` on the timeline timer |
| `services.snapper.configs.<name>.SUBVOLUME` | path | required | Must already contain a `.snapshots` btrfs subvolume |
| `services.snapper.configs.<name>.FSTYPE` | enum | `"btrfs"` | `"btrfs"` or `"bcachefs"` |
| `services.snapper.configs.<name>.ALLOW_USERS` | listOf str | `[]` | Users who may run `snapper` without sudo |
| `services.snapper.configs.<name>.ALLOW_GROUPS` | listOf str | `[]` | Groups who may run `snapper` without sudo |
| `services.snapper.configs.<name>.TIMELINE_CREATE` | bool | `false` | Must be `true` to enable hourly snapshots |
| `services.snapper.configs.<name>.TIMELINE_CLEANUP` | bool | `false` | Must be `true` to enable cleanup |
| `services.snapper.configs.<name>.TIMELINE_LIMIT_HOURLY` | int | `10` | |
| `services.snapper.configs.<name>.TIMELINE_LIMIT_DAILY` | int | `10` | |
| `services.snapper.configs.<name>.TIMELINE_LIMIT_WEEKLY` | int | `0` | Default is 0 (disabled) |
| `services.snapper.configs.<name>.TIMELINE_LIMIT_MONTHLY` | int | `10` | |
| `services.snapper.configs.<name>.TIMELINE_LIMIT_QUARTERLY` | int | `0` | |
| `services.snapper.configs.<name>.TIMELINE_LIMIT_YEARLY` | int | `10` | |

---

## 7. Risks and Mitigations

### Risk 1 — `.snapshots` subvolume does not exist

**Severity**: HIGH  
**Description**: The NixOS snapper module writes `/etc/snapper/configs/root` with `SUBVOLUME=/`, but snapper itself requires that `/.snapshots` already be a btrfs subvolume on the filesystem. If it is absent, the `snapper-timeline.service` unit will fail immediately at its first scheduled run.  
**Mitigation**: Documented as Step 1 (manual prerequisite). The README or a notice in the module comment should remind the user. The dry-build validation (`nixos-rebuild dry-build`) will succeed even without `.snapshots` because it is a runtime concern, not a Nix evaluation concern.

### Risk 2 — Root filesystem is not btrfs

**Severity**: HIGH for VM, LOW for physical hosts  
**Description**: If the root filesystem is ext4 (e.g., some older hardware-configuration.nix setups), snapper will fail at runtime with an unsupported filesystem error.  
**Mitigation**: The module is **not imported in `hosts/vm.nix`**. For physical builds, the project convention assumes btrfs. If a physical host uses ext4, the user must simply not import `modules/snapper.nix` in that host file.

### Risk 3 — Root subvolume uses an alias name (e.g. `@` instead of `/`)

**Severity**: MEDIUM  
**Description**: Some btrfs layouts use subvolume names like `@`, `@home`, `@snapshots`. The `SUBVOLUME = "/"` setting refers to the mount point, not the subvolume name — snapper resolves the mount point to the underlying subvolume. Setting `SUBVOLUME = "/"` is correct regardless of the underlying subvolume name.  
**Mitigation**: No code change needed. The mount-point-based approach in the spec is correct per snapper's documentation.

### Risk 4 — Disk space exhaustion from snapshots

**Severity**: LOW  
**Description**: On a nearly-full SSD, keeping 19 snapper snapshots could consume significant space if large files are frequently written and deleted.  
**Mitigation**: The chosen limits (5 hourly, 7 daily, 4 weekly, 3 monthly, 0 yearly) are conservative. The `services.btrfs.autoScrub` monthly scrub will surface errors early. The user can tune `TIMELINE_LIMIT_*` values down if disk space is a concern.

### Risk 5 — Snapper D-Bus not available when btrfs-assistant launches

**Severity**: LOW  
**Description**: btrfs-assistant communicates with snapperd via D-Bus. If the user launches btrfs-assistant before `snapperd.service` is running, the GUI will show an error.  
**Mitigation**: `snapperd` is a D-Bus-activated service registered via `services.dbus.packages`; it auto-starts on first D-Bus call from btrfs-assistant. No manual service management is needed.

---

## 8. Files to Create / Modify

| Action | Path | Description |
|---|---|---|
| CREATE | `modules/snapper.nix` | New module: snapper + btrfs-assistant + autoScrub |
| MODIFY | `hosts/amd.nix` | Add `../modules/snapper.nix` to imports |
| MODIFY | `hosts/nvidia.nix` | Add `../modules/snapper.nix` to imports |
| MODIFY | `hosts/intel.nix` | Add `../modules/snapper.nix` to imports |
| NO CHANGE | `hosts/vm.nix` | VM must not enable snapper |
| NO CHANGE | `configuration.nix` | Shared base; snapper is per-host |
| NO CHANGE | `flake.nix` | No new inputs required |

---

## 9. Sources Consulted

1. NixOS snapper module source — `nixos/modules/services/misc/snapper.nix` @ nixpkgs `bcd464cc` (nixos-25.11): confirms all option names, types, defaults, and the D-Bus/systemd auto-wiring.
2. nixpkgs `btrfs-assistant` package — `pkgs/by-name/bt/btrfs-assistant/package.nix` @ nixos-25.11: confirms `pkgs.btrfs-assistant` attribute, version 2.2, snapper integration enabled by default, Qt6 runtime dependencies.
3. NixOS package search (25.11) — `https://search.nixos.org/packages?channel=25.11&query=btrfs-assistant`: confirms single result, GPL-3.0, maintainer Austin Horstman.
4. NixOS option search (25.11) — `https://search.nixos.org/options?query=services.snapper&channel=25.11`: confirmed 18 options in services.snapper namespace.
5. NixOS Wiki — Btrfs page (`https://wiki.nixos.org/wiki/Btrfs`): confirmed `services.btrfs.autoScrub` option pattern, subvolume layout conventions, snapshot semantics.
6. nixpkgs snapper module raw source (`raw.githubusercontent.com`): verified default values: `snapshotInterval = "hourly"`, `cleanupInterval = "1d"`, `persistentTimer = false`, `TIMELINE_LIMIT_WEEKLY = 0`, `TIMELINE_LIMIT_YEARLY = 10`, `TIMELINE_CREATE = false`, `TIMELINE_CLEANUP = false`.
