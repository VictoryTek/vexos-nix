# Stateless Disk Automation — Implementation Specification

**Feature:** `stateless_disk`
**Date:** 2026-04-10
**Status:** DRAFT — awaiting implementation

---

## 1. Current State Analysis

### `modules/impermanence.nix`

The module manages tmpfs-rooted impermanence for the stateless role. It currently contains
a large `# PREREQUISITES` comment block at the top requiring users to **manually** add
four blocks to `/etc/nixos/hardware-configuration.nix`:

| Prerequisite | Hardware-specific? | Mechanism |
|---|---|---|
| `fileSystems."/" = { device = "none"; fsType = "tmpfs"; ... }` | **No** — zero hardware info needed | tmpfs, no UUID |
| `boot.initrd.luks.devices."cryptroot"` | **Yes** — needs LUKS partition UUID | `blkid` on target |
| `fileSystems."/nix"` (Btrfs `@nix` subvolume) | **Yes** — needs Btrfs filesystem UUID | `blkid` on target |
| `fileSystems."/persistent"` (Btrfs `@persist` subvolume) | **Yes** — needs Btrfs filesystem UUID | `blkid` on target |

Two assertions exist in the module to verify prerequisites were added:
1. `fileSystems."${cfg.persistentPath}"` has `neededForBoot = true`
2. `fileSystems."/"` has `fsType = "tmpfs"`

### Stateless host files (`hosts/stateless-{amd,nvidia,intel,vm}.nix`)

Minimal — import `configuration-stateless.nix` and a GPU module only. No disk configuration.

### `configuration-stateless.nix`

Enables `vexos.impermanence.enable = true` but contains no disk layout.

### `flake.nix`

Does **not** include disko as an input. Includes `impermanence` (no nixpkgs dependency).
All stateless configs use `commonModules` which imports `/etc/nixos/hardware-configuration.nix`.

### `scripts/install.sh`

A post-install rebuild helper. Runs `nixos-rebuild switch` on an already-running NixOS system.
Does **not** handle fresh disk partitioning or first-time installation.

---

## 2. Problem Definition

The stateless role requires non-standard disk layout (LUKS2 + Btrfs subvolumes + tmpfs root)
that `nixos-generate-config` does not produce. Users must manually:

1. Partition and format the disk (no guidance, no automation)
2. Look up hardware UUIDs via `blkid`
3. Correctly transcribe four configuration blocks into `hardware-configuration.nix`
4. Debug any mistakes silently (impermanence bind mounts fail quietly)

This is error-prone, undocumented in the host files, and particularly hostile to the
stateless role's target audience (Tails/stateless users who may not be NixOS experts).

---

## 3. Selected Approach: D — Disko Module + Setup Script

**Recommended approach: Hybrid D**

- `modules/stateless-disk.nix` — a new NixOS module using **disko** to declare the
  full GPT + EFI + LUKS2 + Btrfs subvolume layout declaratively
- `scripts/stateless-setup.sh` — a new interactive bash script for initial disk setup
  from the NixOS installer ISO (formats disk, installs system)
- `modules/impermanence.nix` — move `fileSystems."/"` (tmpfs) into the module config,
  eliminating the only UUID-free prerequisite from the comment block
- `flake.nix` — add `disko` as a flake input

---

## 4. Justification

### Why not Approach A (module + disko, no script)?
Approach A declares the disk module but leaves the user to manually run disko and
nixos-install. This is still too many manual steps for the target audience.

### Why not Approach B (module + bash-produces-UUID-snippet)?
Approach B still requires the user to copy UUIDs and edit hardware-configuration.nix.
It also creates a parallel source of truth (script output vs. module configuration) that
drifts over time.

### Why not Approach C (module + UUID options)?
Approach C eliminates hardware-configuration.nix edits but the user still must manually
partition, format, run `blkid`, and set two UUIDs in the host config. It saves one step
but solves nothing about disk setup.

### Why Approach D?
Disko is the current NixOS standard for declarative disk partitioning (2024–2026 consensus).
Key properties:

1. **disko generates `fileSystems.*` and `boot.initrd.luks.devices.*` automatically** from
   the disk layout declaration — eliminating all three hardware-UUID prerequisites.
2. **`disko-install` (or disko + nixos-install) performs the entire first-boot setup** in
   one script invocation — no UUID copy-paste, no hardware-configuration.nix editing.
3. **disko modules are idempotent for rebuilds** — on subsequent `nixos-rebuild switch`,
   disko generates the `fileSystems` options but does NOT reformat the disk.
4. **The VM variant** simply sets `enableLuks = false` to skip LUKS — same module, no
   separate code path.
5. **Aligns with NixOS 25.05/25.11 best practices** and the direction of the NixOS ecosystem.

The NixOS wiki explicitly states:
> "Ensure that there are no automatically generated entries of `fileSystems` options in
> `/etc/nixos/hardware-configuration.nix`. Disko will automatically generate them for you."

---

## 5. Architecture Overview

```
User runs scripts/stateless-setup.sh from NixOS live ISO
    │
    ├─ prompts: disk device (e.g. /dev/nvme0n1), GPU variant, hostname
    │
    ├─ runs disko --mode destroy,format,mount (from GitHub, inline config)
    │    └─ creates: EFI partition    → /mnt/boot (vfat)
    │    └─ creates: LUKS2 container  → /dev/mapper/cryptroot
    │    └─ creates: Btrfs @nix       → /mnt/nix
    │    └─ creates: Btrfs @persist   → /mnt/persistent
    │
    ├─ nixos-generate-config --no-filesystems --root /mnt
    │    └─ creates /mnt/etc/nixos/hardware-configuration.nix (no fileSystems)
    │
    ├─ downloads template/etc-nixos-flake.nix → /mnt/etc/nixos/flake.nix
    │
    └─ nixos-install --flake /mnt/etc/nixos#vexos-stateless-<variant>
         └─ NixOS evaluates flake:
              ├─ /etc/nixos/hardware-configuration.nix (hw details, no fileSystems)
              ├─ modules/stateless-disk.nix (disko → generates fileSystems + LUKS config)
              └─ modules/impermanence.nix (declares fileSystems."/" as tmpfs)
```

After reboot, normal `nixos-rebuild switch` / `just update` workflows apply.
`scripts/install.sh` is used for subsequent rebuilds (not initial install).

---

## 6. Context7-Verified Disko API Patterns

Library ID: `/nix-community/disko`
Source reputation: High

### 6.1 Flake Input Declaration (verified)

```nix
disko = {
  url = "github:nix-community/disko/latest";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 6.2 NixOS Module Import (verified)

```nix
imports = [ inputs.disko.nixosModules.disko ];
```

### 6.3 GPT + LUKS2 + Btrfs Subvolume Layout (verified from disko example `luks-btrfs-subvolumes.nix`)

```nix
disko.devices = {
  disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";   # overridden via option
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512MiB";
          type = "EF00";
          priority = 1;
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          priority = 2;
          content = {
            type = "luks";
            name = "cryptroot";
            settings = {
              allowDiscards    = true;
              bypassWorkqueues = true;
            };
            content = {
              type      = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@nix" = {
                  mountpoint   = "/nix";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "@persist" = {
                  mountpoint   = "/persistent";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
              };
            };
          };
        };
      };
    };
  };
};
```

### 6.4 `nixos-generate-config` Without Filesystems (verified from disko quickstart)

```console
nixos-generate-config --no-filesystems --root /mnt
```

This prevents `hardware-configuration.nix` from declaring `fileSystems` entries
that would conflict with disko's generated ones.

### 6.5 Disko Standalone CLI (verified)

```console
sudo nix run 'github:nix-community/disko/latest' -- \
  --mode destroy,format,mount \
  /tmp/stateless-disk.nix
```

---

## 7. Files to Create

| Path | Purpose |
|---|---|
| `modules/stateless-disk.nix` | Disko-based disk layout module with Nix options |
| `scripts/stateless-setup.sh` | Interactive initial-install script for stateless role |
| `template/stateless-disko.nix` | Standalone parameterized disko config (used by setup script) |

---

## 8. Files to Modify

| Path | Change summary |
|---|---|
| `flake.nix` | Add disko input; add to `outputs` destructuring |
| `modules/impermanence.nix` | Move tmpfs mount into `config`; remove PREREQUISITES block |
| `hosts/stateless-amd.nix` | Import `modules/stateless-disk.nix`; set `vexos.stateless.disk.device` |
| `hosts/stateless-nvidia.nix` | Import `modules/stateless-disk.nix`; set `vexos.stateless.disk.device` |
| `hosts/stateless-intel.nix` | Import `modules/stateless-disk.nix`; set `vexos.stateless.disk.device` |
| `hosts/stateless-vm.nix` | Import `modules/stateless-disk.nix`; set device + `enableLuks = false` |
| `scripts/install.sh` | Add notice for stateless role directing users to `stateless-setup.sh` |

---

## 9. New Nix Options

Module: `modules/stateless-disk.nix`
Option namespace: `vexos.stateless.disk`

| Option | Type | Default | Description |
|---|---|---|---|
| `vexos.stateless.disk.device` | `str` | `"/dev/nvme0n1"` | Block device for the stateless disk layout. Passed to disko as `disko.devices.disk.main.device`. |
| `vexos.stateless.disk.enableLuks` | `bool` | `true` | Wrap the data partition in LUKS2. Set `false` for VMs. |
| `vexos.stateless.disk.luksName` | `str` | `"cryptroot"` | Name of the LUKS device-mapper entry (`/dev/mapper/<luksName>`). |

---

## 10. Disko Module Design: `modules/stateless-disk.nix`

```nix
# modules/stateless-disk.nix
# Declarative disk layout for the VexOS stateless role.
#
# Uses disko (github:nix-community/disko) to declare the full GPT partition
# table, LUKS2 container, and Btrfs subvolumes required by the stateless role.
#
# disko generates fileSystems."/nix", fileSystems."/persistent",
# fileSystems."/boot", and boot.initrd.luks.devices."cryptroot" automatically.
# This module replaces all hardware-UUID prerequisites previously documented
# in modules/impermanence.nix.
#
# IMPORTANT: hardware-configuration.nix MUST be generated with:
#   nixos-generate-config --no-filesystems --root /mnt
# to avoid fileSystems conflicts with disko's generated entries.
{ config, lib, inputs, ... }:

let
  cfg = config.vexos.stateless.disk;
in
{
  imports = [ inputs.disko.nixosModules.disko ];

  options.vexos.stateless.disk = {

    device = lib.mkOption {
      type        = lib.types.str;
      default     = "/dev/nvme0n1";
      description = ''
        Block device to use for the stateless disk layout.
        This becomes disko.devices.disk.main.device.
        Examples: "/dev/nvme0n1"  "/dev/sda"  "/dev/vda"
        Override in your host file: vexos.stateless.disk.device = "/dev/sda";
      '';
    };

    enableLuks = lib.mkOption {
      type        = lib.types.bool;
      default     = true;
      description = ''
        Wrap the data partition in LUKS2 full-disk encryption.
        Set to false for VM guests that do not require disk encryption.
        When false, the Btrfs filesystem is created directly on the partition.
      '';
    };

    luksName = lib.mkOption {
      type        = lib.types.str;
      default     = "cryptroot";
      description = ''
        Name for the LUKS device-mapper entry.
        The decrypted device will appear at /dev/mapper/<luksName>.
      '';
    };

  };

  config = {

    disko.devices = {
      disk.main = {
        type   = "disk";
        device = cfg.device;
        content = {
          type = "gpt";
          partitions =
            # EFI System Partition — always present
            {
              ESP = {
                size     = "512MiB";
                type     = "EF00";
                priority = 1;
                content = {
                  type         = "filesystem";
                  format       = "vfat";
                  mountpoint   = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
            }
            # LUKS2-encrypted Btrfs (hardware installs)
            // lib.optionalAttrs cfg.enableLuks {
              luks = {
                size     = "100%";
                priority = 2;
                content = {
                  type  = "luks";
                  name  = cfg.luksName;
                  settings = {
                    allowDiscards    = true;
                    bypassWorkqueues = true;
                  };
                  content = {
                    type      = "btrfs";
                    extraArgs = [ "-f" ];
                    subvolumes = {
                      "@nix" = {
                        mountpoint   = "/nix";
                        mountOptions = [ "compress=zstd" "noatime" ];
                      };
                      "@persist" = {
                        mountpoint   = "/persistent";
                        mountOptions = [ "compress=zstd" "noatime" ];
                      };
                    };
                  };
                };
              };
            }
            # Plain Btrfs (VM installs — no LUKS overhead)
            // lib.optionalAttrs (!cfg.enableLuks) {
              data = {
                size     = "100%";
                priority = 2;
                content = {
                  type      = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "@nix" = {
                      mountpoint   = "/nix";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "@persist" = {
                      mountpoint   = "/persistent";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                  };
                };
              };
            };
        };
      };
    };

    # disko generates fileSystems entries for /nix and /persistent but does
    # not set neededForBoot. impermanence requires neededForBoot = true on
    # /persistent so that bind mounts are available during early userspace.
    # /nix is also flagged so the Nix store is available before activation.
    # lib.mkForce overrides the disko default (false) without causing a conflict.
    fileSystems."/persistent".neededForBoot = lib.mkForce true;
    fileSystems."/nix".neededForBoot        = lib.mkForce true;

  };
}
```

---

## 11. `modules/impermanence.nix` Changes

### 11.1 Remove the PREREQUISITES comment block (lines 8–44)

Delete the entire `# PREREQUISITES — add the following to the host's hardware-configuration.nix:` block through the `# See .github/docs/subagent_docs/impermanence_spec.md` line.

Replace with a short reference comment:

```nix
# modules/impermanence.nix
# Filesystem impermanence for the VexOS stateless role.
#
# This module implements a tmpfs-rooted NixOS system where everything
# outside of /nix and /persistent is wiped on every reboot, providing
# Tails-like ephemeral behaviour (similar to Tails Linux / Deep Freeze).
#
# Disk layout (LUKS2 + Btrfs subvolumes) is handled declaratively by
# modules/stateless-disk.nix using disko. No manual hardware-configuration.nix
# edits are required. See .github/docs/subagent_docs/stateless_disk_spec.md.
```

### 11.2 Move `fileSystems."/"` into `config = lib.mkIf cfg.enable { ... }`

Add the following at the beginning of the `config` block (after the opening brace,
before the assertions):

```nix
    # ── Ephemeral root (tmpfs) ──────────────────────────────────────────────
    # Declare / as a tmpfs mount. This is hardware-independent (no UUID).
    # Wiped on every reboot by design — this is the core of the stateless model.
    fileSystems."/" = {
      device  = "none";
      fsType  = "tmpfs";
      options = [ "defaults" "size=25%" "mode=755" ];
    };
```

### 11.3 Update assertions

The assertions remain but their messages should be updated to reflect the new flow:

**Assertion 1** (persistent path neededForBoot):
```nix
message = ''
  vexos.impermanence.enable = true requires
  fileSystems."${cfg.persistentPath}" to be declared with neededForBoot = true.
  This is normally satisfied automatically by modules/stateless-disk.nix.
  Check that stateless-disk.nix is imported in your stateless host file.
'';
```

**Assertion 2** (/ is tmpfs):
```nix
message = ''
  vexos.impermanence.enable = true requires fileSystems."/" to have
  fsType = "tmpfs". This is declared automatically by this module.
  If this assertion fails, another module is overriding fileSystems."/".
'';
```

### 11.4 Update the `enable` option description

Remove the sentence:
> "Requires hardware-configuration.nix to mount / as tmpfs and the persistent volume
> as a neededForBoot mount."

Replace with:
> "Disk layout is handled by modules/stateless-disk.nix (disko). The tmpfs root
> is declared by this module automatically when enabled."

---

## 12. Stateless Host File Changes

### `hosts/stateless-amd.nix`

```nix
# hosts/stateless-amd.nix
# vexos — Stateless AMD GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-amd
{ lib, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/amd.nix
    ../modules/stateless-disk.nix
  ];

  # Override with the actual disk device on the target machine.
  # Default "/dev/nvme0n1" is suitable for most modern AMD laptops/desktops.
  # Check with: lsblk -d -o NAME,SIZE,MODEL
  vexos.stateless.disk.device = "/dev/nvme0n1";

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Stateless AMD";
}
```

### `hosts/stateless-nvidia.nix`

```nix
# hosts/stateless-nvidia.nix
# vexos — Stateless NVIDIA GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/nvidia.nix
    ../modules/stateless-disk.nix
  ];

  # Override with the actual disk device on the target machine.
  # Check with: lsblk -d -o NAME,SIZE,MODEL
  vexos.stateless.disk.device = "/dev/nvme0n1";

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Stateless NVIDIA";
}
```

### `hosts/stateless-intel.nix`

Same pattern as AMD — add `modules/stateless-disk.nix` import and `vexos.stateless.disk.device`.

```nix
# hosts/stateless-intel.nix
{ lib, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/intel.nix
    ../modules/stateless-disk.nix
  ];

  vexos.stateless.disk.device = "/dev/nvme0n1";

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Stateless Intel";
}
```

### `hosts/stateless-vm.nix`

```nix
# hosts/stateless-vm.nix
# vexos — Stateless VM guest build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-vm
{ inputs, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/vm.nix
    ../modules/stateless-disk.nix
  ];

  # VM guests use plain Btrfs (no LUKS — encryption handled by the hypervisor).
  vexos.stateless.disk.device     = "/dev/vda";
  vexos.stateless.disk.enableLuks = false;

  networking.hostName = "vexos-stateless-vm";

  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
  system.nixos.distroName = "VexOS Stateless VM";
}
```

**Note:** The existing bootloader comment block in stateless-vm.nix can be removed —
bootloader is managed by the template's `bootloaderModule`.

---

## 13. `flake.nix` Changes

### 13.1 Add disko input

In the `inputs` attrset, after the `impermanence` input:

```nix
    # nix-community/disko: declarative disk partitioning for the stateless role.
    # Used by modules/stateless-disk.nix to generate fileSystems and LUKS config.
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

### 13.2 Add disko to outputs destructuring

Change:
```nix
  outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, home-manager, impermanence, ... }@inputs:
```
To:
```nix
  outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, home-manager, impermanence, disko, ... }@inputs:
```

*(The `disko` is already available via `inputs` in `specialArgs = { inherit inputs; }`, so
`modules/stateless-disk.nix` can access `inputs.disko.nixosModules.disko` directly. The explicit
destructuring is for documentation clarity and consistency with other inputs.)*

---

## 14. Setup Script Design: `scripts/stateless-setup.sh`

This script is run from the **NixOS live ISO** to perform an initial stateless role installation.
It is separate from `scripts/install.sh` (which handles rebuilds on running systems).

### Usage

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/stateless-setup.sh)
```

### Script Flow

```
1. Print header and security notice

2. Detect nix-command + flakes (enable if needed for the ISO session)

3. Show disk list (lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -v loop)

4. Prompt: "Enter the disk device to install to (e.g. /dev/nvme0n1):"
   - Require explicit /dev/ prefix (no number selection — avoids mistakes)
   - Confirm: "This will ERASE ALL DATA on <device>. Type the device path again to confirm:"
   - Abort if confirmation does not match

5. Prompt: "Select GPU variant: 1) AMD  2) NVIDIA  3) Intel  4) VM"
   → VARIANT = amd | nvidia | intel | vm

6. Prompt: "Enter hostname [vexos-stateless]:"
   → HOSTNAME = user input or default

7. If VARIANT != vm:
   - Print LUKS passphrase instructions
   - Run disko to format disk (interactive LUKS passphrase prompt from disko)
   else:
   - Run disko to format disk (no LUKS)
   
   disko command:
     sudo nix \
       --extra-experimental-features 'nix-command flakes' \
       run 'github:nix-community/disko/latest' -- \
       --mode destroy,format,mount \
       /tmp/vexos-stateless-disk.nix \
       --arg disk '"${DISK}"' \
       --arg enableLuks '${LUKS_BOOL}'

8. Generate hardware config (NO filesystems — disko handles those):
   sudo nixos-generate-config --no-filesystems --root /mnt

9. Download template flake to /mnt/etc/nixos/:
   sudo curl -fsSL \
     https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/template/etc-nixos-flake.nix \
     -o /mnt/etc/nixos/flake.nix

10. Run nixos-install:
    sudo nixos-install \
      --no-root-passwd \
      --flake /mnt/etc/nixos#vexos-stateless-${VARIANT}

11. Print success message and reboot prompt
```

### Key Safety Rules for the Script

- `set -uo pipefail` throughout
- Explicit device confirmation by re-typing (not just "yes/no") — protects against wrong disk selection
- Show `lsblk` output before asking for the device
- Label disko step as "DESTRUCTIVE — point of no return" before running
- No `--arg` passed for LUKS passphrase — disko will interactively prompt for it, which is
  the correct way to handle passphrases (never passed as arguments or env vars)

---

## 15. Standalone Disko Template: `template/stateless-disko.nix`

A standalone parameterized disko config used by `scripts/stateless-setup.sh`.
This is **separate** from `modules/stateless-disk.nix` (which is a NixOS module).
The standalone version is needed so disko CLI can run it before NixOS is installed.

```nix
# template/stateless-disko.nix
# Standalone disko disk layout for the VexOS stateless role.
# Used by scripts/stateless-setup.sh during initial installation.
# Parameters:
#   disk      — block device (string, e.g. "/dev/nvme0n1")
#   enableLuks — whether to use LUKS2 encryption (bool, default true)
#   luksName  — name of the LUKS device-mapper entry (string, default "cryptroot")
{ disk ? "/dev/nvme0n1", enableLuks ? true, luksName ? "cryptroot" }:
{
  disko.devices = {
    disk.main = {
      type   = "disk";
      device = disk;
      content = {
        type = "gpt";
        partitions =
          {
            ESP = {
              size     = "512MiB";
              type     = "EF00";
              priority = 1;
              content = {
                type         = "filesystem";
                format       = "vfat";
                mountpoint   = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
          }
          // (if enableLuks then {
            luks = {
              size     = "100%";
              priority = 2;
              content = {
                type  = "luks";
                name  = luksName;
                settings = {
                  allowDiscards    = true;
                  bypassWorkqueues = true;
                };
                content = {
                  type      = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "@nix" = {
                      mountpoint   = "/nix";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "@persist" = {
                      mountpoint   = "/persistent";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                  };
                };
              };
            };
          } else {
            data = {
              size     = "100%";
              priority = 2;
              content = {
                type      = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@nix" = {
                    mountpoint   = "/nix";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@persist" = {
                    mountpoint   = "/persistent";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                };
              };
            };
          });
      };
    };
  };
}
```

---

## 16. `scripts/install.sh` Changes

When `ROLE = "stateless"`, print a notice before the `nixos-rebuild switch` step:

```bash
# After selecting role = "stateless", before GPU variant selection:
echo ""
echo -e "${YELLOW}${BOLD}NOTE: Stateless role — fresh install?${RESET}"
echo "  If this is a FIRST-TIME installation from the NixOS ISO:"
echo "    bash <(curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/stateless-setup.sh)"
echo ""
echo "  install.sh handles REBUILDS on an already-running vexos-stateless system."
echo "  Press Enter to continue with rebuild, or Ctrl+C to abort."
read -r _
```

---

## 17. VM-Specific Considerations

| Concern | Hardware (AMD/NVIDIA/Intel) | VM (stateless-vm) |
|---|---|---|
| `enableLuks` | `true` (default) | `false` |
| Disk device | `/dev/nvme0n1` (default) | `/dev/vda` |
| LUKS passphrase setup | Required — prompted by disko | Not required |
| EFI partition | 512 MiB vfat | 512 MiB vfat |
| Btrfs subvolumes | Inside LUKS container | Directly on partition |
| `stateless-setup.sh` support | Yes | Yes (skips LUKS steps) |

For the VM, the setup script detects `VARIANT = "vm"` and passes `--arg enableLuks false` to disko.

The VM's `stateless-vm.nix` removes the existing bootloader comment block — bootloader is
handled by the template's `bootloaderModule` (systemd-boot by default, GRUB override documented
in the template header).

---

## 18. `hardware-configuration.nix` Guidance

After this implementation, stateless role hardware-configuration.nix should contain:
- CPU microcode (`hardware.cpu.{amd,intel}.updateMicrocode`)
- Kernel modules for storage/network hardware
- `boot.initrd.availableKernelModules`
- **No** `fileSystems.*` entries (disko provides these)
- **No** `boot.initrd.luks.devices.*` entries (disko provides these)
- **No** `swapDevices` (swap is disabled by impermanence module)

The `--no-filesystems` flag achieves this:
```console
nixos-generate-config --no-filesystems --root /mnt
```

For users migrating existing stateless installs (where hw-config was manually edited),
they must **remove** the four manual blocks from their `hardware-configuration.nix` to
avoid disko conflicts. A migration note should be added to the README.

---

## 19. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| User selects wrong disk → data loss | CRITICAL | Double-confirmation: must re-type the /dev/ path exactly. Show lsblk first. |
| `hardware-configuration.nix` has fileSystems entries → disko conflict | HIGH | `--no-filesystems` flag in setup script. Document migration for existing users. |
| disko doesn't set `neededForBoot = true` → impermanence bind mounts fail silently | HIGH | Explicitly set `fileSystems."/persistent".neededForBoot = lib.mkForce true` in stateless-disk.nix |
| disko input adds nixpkgs duplication | MEDIUM | `inputs.nixpkgs.follows = "nixpkgs"` declared in flake input |
| Desktop/HTPC/server hosts accidentally import stateless-disk.nix | LOW | stateless-disk.nix only imported in stateless host files — not in commonModules |
| Impermanence assertion fires after / is declared in module (self-fulfilling) | LOW | Assertion still guards against accidental module overrides; update message |
| LUKS passphrase lost | HIGH (user) | Document in setup script: passphrase cannot be recovered. Recommend using password manager in persistent storage. |
| disko reformats disk on nixos-rebuild switch | N/A | disko is idempotent for config — it generates fileSystems but only formats during initial `--mode destroy,format,mount` invocation |

---

## 20. Assertions Behavior After Implementation

| Assertion | Before | After |
|---|---|---|
| `/` is tmpfs | Fails if user forgot to add tmpfs mount to hw-config | Always passes — module declares it |
| `/persistent` has `neededForBoot` | Fails if user missed this flag | Always passes — stateless-disk.nix sets it via `lib.mkForce true` |

Both assertions are kept as safety guards against accidental overrides by other modules.

---

## 21. Files Summary

### Create (3 new files)
- `modules/stateless-disk.nix`
- `scripts/stateless-setup.sh`
- `template/stateless-disko.nix`

### Modify (7 existing files)
- `flake.nix`
- `modules/impermanence.nix`
- `hosts/stateless-amd.nix`
- `hosts/stateless-nvidia.nix`
- `hosts/stateless-intel.nix`
- `hosts/stateless-vm.nix`
- `scripts/install.sh`

---

*End of specification.*
