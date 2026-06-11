# Boot Auto-Discovery Specification

## Feature Name: `boot_autodiscovery`

---

## Current State Analysis

The previous `dualboot` feature (spec: `dualboot_spec.md`) added `boot.loader.systemd-boot.edk2-uefi-shell.enable = true` and documented a manual process:

1. Boot into EDK2 UEFI shell
2. Run `map -c` to discover device handles
3. Hardcode the handle into a host file (`boot.loader.systemd-boot.windows."11".efiDeviceHandle = "HD0c1"`)
4. Rebuild

**This requires manual per-host configuration every time the dual-boot combination changes.** The user wants zero-configuration automatic detection.

### How systemd-boot discovers entries

systemd-boot discovers boot menu entries from three sources:

- **Type 1** — BLS entries in `$ESP/loader/entries/*.conf` (NixOS generations live here)
- **Type 2** — Unified Kernel Images (UKIs) in `$ESP/EFI/Linux/*.efi`
- **Type 3 (firmware)** — UEFI NVRAM `Boot####` variables registered via `efibootmgr` or any OS installer

Type 3 entries appear automatically in systemd-boot's boot menu for any `Boot####` variable that is marked **active** and has a valid EFI device path. The firmware knows the exact disk/partition/file path for these entries — systemd-boot just reads and presents them.

### Why other drives are not showing

When an OS (Windows, Ubuntu, another NixOS) is installed on a separate drive, its installer registers a `Boot####` UEFI NVRAM entry. These entries CAN get lost when:

1. Another `nixos-rebuild switch` with `canTouchEfiVariables = true` runs `bootctl install`, which rewrites the `BootOrder` (doesn't delete others, but can leave them de-prioritized or inactive)
2. BIOS/UEFI "secure boot" changes or firmware updates clear non-native entries
3. The user initially installed the OS without proper EFI NVRAM registration (e.g., BIOS mode install on a UEFI machine)
4. The OS was installed after the UEFI registered a different drive as authoritative

**The fix**: A boot-time systemd service that scans all drives for ESP partitions, detects installed OSes, and ensures their UEFI NVRAM entries exist via `efibootmgr`. systemd-boot will then present them as Type 3 entries automatically on the next boot.

---

## Problem Definition

The user dual-boots across various combinations:
- Linux + Windows (separate drives)
- Two different Linux distros (separate drives)
- Two different VexOS roles (separate drives)

For every combination, systemd-boot does not show the other drive's OS without manual configuration. The user wants plug-and-play detection that works regardless of what is connected.

---

## Proposed Solution Architecture

### Design: `modules/boot-discovery.nix` (new addition file)

A new module that adds a `systemd.services.vexos-boot-discovery` oneshot service. This service:

1. Finds the primary ESP (mounted at `/boot`)
2. Scans all other EFI System Partitions on the system (by partition type GUID `c12a7328-f81f-11d2-ba4b-00a0c93ec93b` via `/dev/disk/by-parttype/`)
3. Mounts each other ESP read-only
4. Detects installed OSes by well-known EFI binary paths
5. For each detected OS, creates a UEFI NVRAM entry via `efibootmgr` if one with the same label does not already exist
6. Unmounts the ESP

Labels include a short PARTUUID prefix (8 chars) to make them unique and idempotent across reboots:
- `"Windows Boot Manager [ab12cd34]"`
- `"Ubuntu [ab12cd34]"`
- `"NixOS/systemd-boot [ab12cd34]"`

**Why NVRAM (not `.conf` entries)?**

systemd-boot `.conf` entries (`extraEntries`) can only reference EFI binaries on the **same ESP** that systemd-boot is installed on. Chainloading to a binary on a different physical drive is not natively supported by `.conf` entries — it requires the EDK2 shell as an intermediary with a device handle that is non-deterministic across reboots.

UEFI NVRAM entries store the full EFI device path (including GPT partition UUID), which is drive-independent and stable. systemd-boot reads and presents these directly without any chainloading. This is the correct, standards-compliant mechanism.

**Why a systemd service (not activation script)?**

- `efibootmgr` writes to EFI NVRAM via `/sys/firmware/efi/efivars`, which requires the kernel to have efivarfs mounted (available from very early boot, but more reliably from systemd's perspective after `local-fs.target`)
- A `system.activationScripts` entry would also work but would run on every `nixos-rebuild switch` activation, including dry builds — NVRAM writes during dry evaluation is undesirable
- A systemd oneshot service with `RemainAfterExit = true` runs once per boot, which is the correct cadence for ensuring NVRAM entries are present

### Detected OS paths (in order of priority per ESP)

| OS | EFI Path |
|----|---------|
| Windows | `EFI/Microsoft/Boot/bootmgfw.efi` |
| Ubuntu | `EFI/ubuntu/shimx64.efi` |
| Fedora | `EFI/fedora/shimx64.efi` |
| Arch Linux | `EFI/arch/grubx64.efi` |
| Debian | `EFI/debian/shimx64.efi` |
| Pop!_OS | `EFI/pop/shimx64.efi` |
| Manjaro | `EFI/manjaro/grubx64.efi` |
| NixOS/systemd-boot | `EFI/systemd/systemd-bootx64.efi` |

For Windows and other Linux: only the first matching path per ESP is registered (one entry per ESP).
For NixOS/systemd-boot: registered separately in addition to the above (can co-exist on the same ESP if another OS ALSO has systemd-boot — unlikely but handled).

### Module Architecture compliance

Per Option B (Common base + role additions):

- `modules/boot-discovery.nix` is a **role-addition file**: unconditional content, no `lib.mkIf` guards
- Imported by ALL `configuration-*.nix` files — applies to all roles
- Rationale: any role could be dual-boot; the service is a no-op when no other ESPs are present; overhead is negligible (oneshot service, ~20ms at boot)

---

## Implementation Steps

### Step 1: Create `modules/boot-discovery.nix`

New file. Contains:
- `systemd.services.vexos-boot-discovery` oneshot service
- Shell script written via `pkgs.writeShellScript`
- Service path includes `efibootmgr` and `util-linux` (for `lsblk`, `findmnt`, `mount`)

### Step 2: Import in all `configuration-*.nix` files

Add `./modules/boot-discovery.nix` to imports in:
- `configuration-desktop.nix`
- `configuration-server.nix`
- `configuration-stateless.nix`
- `configuration-htpc.nix`
- `configuration-headless-server.nix`
- `configuration-vanilla.nix`

---

## Dependencies

- `pkgs.efibootmgr` — already in nixpkgs; no new flake input needed
- `pkgs.util-linux` — already in nixpkgs (provides `lsblk`, `findmnt`, `mount`)
- No new flake inputs
- No `follows` declarations required

---

## Configuration changes

None. The module is fully automatic — no per-host options required. The service is self-contained.

---

## Behavior notes

- **One-boot delay**: The service runs after the OS boots. Newly registered NVRAM entries appear in systemd-boot on the **next** boot.
- **Idempotent**: Label-based deduplication (including PARTUUID prefix) ensures `efibootmgr --create` is only called once per unique ESP.
- **No-op on bare-metal NixOS-only**: If no other ESPs are found, the service completes immediately with no NVRAM writes.
- **VM hosts**: VMs (`.#vexos-desktop-vm`) will find no other ESPs (no `/dev/disk/by-parttype/c12a7328...` entries); service is a no-op.
- **Stateless hosts**: The ESP is typically the only special partition; service is likely a no-op or irrelevant.
- **RTC clock**: `time.hardwareClockInLocalTime = true` is NOT set here — it belongs in per-host configs when dual-booting Windows. This module only handles UEFI entry registration.

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `efibootmgr` creates entry on every boot | Impossible | — | Label deduplication prevents this |
| efivarfs not mounted | Very low | Service fails silently | `|| true` around efibootmgr; logs warning |
| Detected OS path is wrong (stale entry) | Low | User sees broken entry in menu | UEFI firmware or systemd-boot shows the error; user can remove via efibootmgr |
| PARTUUID prefix collision (two ESPs with same first 8 chars) | Extremely low | Two entries with same label | Cosmetic only; both entries work |
| NixOS dual-boot registers other drive's systemd-boot | Certain (intended) | Two-level menu | Expected; user navigates second menu |
| `canTouchEfiVariables = false` on some host | N/A | efibootmgr fails silently | Already `true` in all vexos-nix configs |

---

## Verification

After implementation:
- `nix flake show --impure` — must succeed
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — must succeed
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` — must succeed
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` — must succeed
- On physical hardware after switch: `systemctl status vexos-boot-discovery` — must be active
- On hardware with a second drive: `efibootmgr` must show new `[ab12cd34]`-labelled entries
- `hardware-configuration.nix` NOT committed
- `system.stateVersion` unchanged in all `configuration-*.nix`
