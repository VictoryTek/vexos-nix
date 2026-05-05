# Dual-Boot Support Specification

## Feature Name: `dualboot`

## Current State Analysis

### Boot Configuration (modules/system.nix)
The current boot configuration in `modules/system.nix` sets:
- `boot.loader.systemd-boot.enable = lib.mkDefault true`
- `boot.loader.systemd-boot.configurationLimit = 5`
- `boot.loader.efi.canTouchEfiVariables = lib.mkDefault true`

No dual-boot or UEFI shell support is configured. Hosts with other operating systems on separate drives cannot boot them from the systemd-boot menu.

### Flake Inputs
The project uses `nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"` which includes full support for:
- `boot.loader.systemd-boot.edk2-uefi-shell` (enable + sortKey)
- `boot.loader.systemd-boot.windows` (per-install entries with efiDeviceHandle, title, sortKey)
- `boot.loader.systemd-boot.extraEntries` (arbitrary boot entries)

### Host Files
Host files (e.g. `hosts/desktop-nvidia.nix`) are role+GPU-variant-specific and import a configuration module plus GPU module. They contain host-specific overrides like `system.nixos.distroName`.

---

## Problem Definition

The user has:
1. **Desktop PC**: NixOS + Ubuntu on separate drives
2. **Laptop**: NixOS + Windows on separate drives

systemd-boot only auto-discovers operating systems on the **same** EFI System Partition (ESP). When other OSes are on separate drives with their own ESPs, they are invisible to systemd-boot unless manually configured.

---

## Proposed Solution Architecture

### Design Decisions

Following the **Option B: Common base + role additions** module architecture:

1. **`modules/system.nix` (universal base)** — Add `boot.loader.systemd-boot.edk2-uefi-shell.enable = true`
   - The UEFI shell is universally useful: any machine *could* be dual-boot, and it's a diagnostic tool regardless
   - The EDK2 shell is also automatically installed when `windows != {}`, but enabling it explicitly makes it available on all hosts for discovery purposes
   - This is a ~1MB addition to the ESP — negligible cost

2. **Per-host dual-boot entries** — Documented for user to add in their specific `hosts/*.nix` file
   - Windows entries use `boot.loader.systemd-boot.windows.<name>.efiDeviceHandle`
   - Linux entries use `boot.loader.systemd-boot.extraEntries` with UEFI shell chainloading
   - `time.hardwareClockInLocalTime = true` only in hosts with Windows (Windows stores local time in RTC)

### Why NOT a separate module file?

A `modules/dualboot.nix` or `modules/dualboot-windows.nix` would be mostly empty — the entries are 100% host-specific (efiDeviceHandle varies per machine). The EDK2 shell enable is a single line that fits naturally in the existing boot section of `modules/system.nix`. Creating a separate module would be over-engineering for a one-liner.

---

## Implementation Steps

### Step 1: Modify `modules/system.nix`

Add `edk2-uefi-shell.enable` to the unconditional boot section (after `boot.loader.efi.canTouchEfiVariables`):

```nix
      # EFI / systemd-boot — standard bootloader for all vexos-nix hosts.
      # lib.mkDefault allows the host's /etc/nixos/flake.nix thin wrapper
      # to override for BIOS/GRUB systems without conflict.
      boot.loader.systemd-boot.enable           = lib.mkDefault true;
      boot.loader.systemd-boot.configurationLimit = 5;  # keep only the 5 latest boot entries
      boot.loader.efi.canTouchEfiVariables      = lib.mkDefault true;

      # EDK2 UEFI Shell — enables booting other OSes on separate drives and
      # provides a diagnostic shell for EFI troubleshooting. Required for
      # boot.loader.systemd-boot.windows entries to function.
      boot.loader.systemd-boot.edk2-uefi-shell.enable = true;
```

### Step 2: Provide per-host configuration examples in comments / documentation

The user must add OS-specific entries to their host file. Examples:

#### Windows (in `hosts/desktop-nvidia.nix` or similar):

```nix
{ lib, ... }:
{
  imports = [
    ../configuration-desktop.nix
    ../modules/gpu/nvidia.nix
    ../modules/asus.nix
  ];

  system.nixos.distroName = "VexOS Desktop NVIDIA";

  # ── Dual-boot: Windows on separate drive ──────────────────────────────
  # efiDeviceHandle discovered via EDK2 UEFI Shell (`map -c` then check
  # each handle for EFI\Microsoft\Boot\Bootmgfw.efi)
  boot.loader.systemd-boot.windows."11" = {
    title = "Windows 11";
    efiDeviceHandle = "HD0c1";  # REPLACE with actual handle
  };

  # Windows stores RTC in local time; this prevents clock drift between OSes.
  time.hardwareClockInLocalTime = true;
}
```

#### Linux / Ubuntu (in `hosts/desktop-amd.nix` or similar):

```nix
{ lib, ... }:
{
  imports = [
    ../configuration-desktop.nix
    ../modules/gpu/amd.nix
  ];

  system.nixos.distroName = "VexOS Desktop AMD";

  # ── Dual-boot: Ubuntu on separate drive ───────────────────────────────
  # Uses EDK2 UEFI Shell to chainload Ubuntu's GRUB from its own ESP.
  # efiDeviceHandle discovered via `map -c` in the UEFI shell.
  boot.loader.systemd-boot.extraEntries."ubuntu.conf" = ''
    title Ubuntu
    efi /efi/edk2-uefi-shell/shell.efi
    options -nointerrupt -nomap -noversion HD1c1:EFI\ubuntu\shimx64.efi
    sort-key o_ubuntu
  '';
}
```

**Note:** For the Linux chainload entry, the `efi` path points to the EDK2 shell (which acts as the chainloader), and `options` tells the shell to execute the target EFI binary on the specified device handle.

### Step 3: No changes to `modules/branding.nix`

The `extraInstallCommands` in branding.nix only processes NixOS generation entries (`*.conf` files with "Generation" in the title). The Windows/Ubuntu entries will not match those sed patterns, so no modification is needed.

---

## User Instructions: Discovering efiDeviceHandle

After the implementation is applied:

1. Run `sudo nixos-rebuild switch --flake .#vexos-<your-variant>`
2. Reboot and select **"EDK2 UEFI Shell"** from the systemd-boot menu
3. At the shell prompt, run:
   ```
   map -c
   ```
   This lists all consistent (non-removable) device handles.
4. For each handle (e.g., `HD0c1`, `HD1c1`, `FS0`, `FS1`):
   ```
   ls HD0c1:\EFI
   ```
5. **For Windows:** Look for `Microsoft\Boot\Bootmgfw.efi`
   - Test: `HD0c1:\EFI\Microsoft\Boot\Bootmgfw.efi` — if Windows boots, this is correct
6. **For Ubuntu/Linux:** Look for `ubuntu\shimx64.efi` or `ubuntu\grubx64.efi`
   - Test: `HD1c1:\EFI\ubuntu\shimx64.efi` — if Ubuntu boots, this is correct
7. Note the handle and add it to your host file as shown above
8. Rebuild again with `sudo nixos-rebuild switch`

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `modules/system.nix` | MODIFY | Add `boot.loader.systemd-boot.edk2-uefi-shell.enable = true` |
| Host files (user-managed) | DOCUMENT | Provide examples for Windows and Linux chainloading |

---

## Dependencies

- `pkgs.edk2-uefi-shell` — already in nixpkgs, pulled automatically when the option is enabled
- No new flake inputs required
- No `nixpkgs.follows` changes needed

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| EDK2 shell adds ~1MB to ESP | Certain | Negligible | ESP is typically 512MB-1GB; this is insignificant |
| Wrong efiDeviceHandle causes failed boot | Medium | Low | Entry simply fails to boot; user returns to menu. Documentation guides correct discovery |
| `time.hardwareClockInLocalTime` affects time sync | Medium | Low | Only set on hosts with Windows; `systemd-timesyncd` corrects any drift on Linux |
| UEFI shell as attack surface | Low | Low | Shell requires physical console access; same threat model as BIOS setup |
| `extraInstallCommands` in branding.nix interfering with new entries | Low | None | The sed patterns only match entries containing "Generation" — Windows/Ubuntu entries don't match |
| Handle changes after firmware update | Low | Medium | User re-runs discovery process; document this possibility |

---

## Verification Checklist

After implementation:
- [ ] `nix flake check` passes
- [ ] `nixos-rebuild dry-build --flake .#vexos-desktop-amd` succeeds
- [ ] `nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` succeeds
- [ ] `nixos-rebuild dry-build --flake .#vexos-desktop-vm` succeeds
- [ ] EDK2 shell entry appears in `/boot/loader/entries/edk2-uefi-shell.conf` after rebuild
- [ ] Shell binary present at `/boot/efi/edk2-uefi-shell/shell.efi` after rebuild
- [ ] `system.stateVersion` unchanged
- [ ] No `hardware-configuration.nix` added to repo

---

## NixOS Option Reference (Verified in nixpkgs nixos-25.11)

### `boot.loader.systemd-boot.edk2-uefi-shell.enable`
- Type: `bool`, Default: `false`
- Makes EDK2 UEFI Shell available in the boot menu
- Also automatically installed when `boot.loader.systemd-boot.windows != {}`

### `boot.loader.systemd-boot.edk2-uefi-shell.sortKey`
- Type: `str`, Default: `"o_edk2-uefi-shell"`
- Controls menu ordering

### `boot.loader.systemd-boot.windows.<name>.efiDeviceHandle`
- Type: `str` (required)
- Device handle for the ESP containing Windows Boot Manager
- Discovered via EDK2 UEFI Shell `map -c` command

### `boot.loader.systemd-boot.windows.<name>.title`
- Type: `str`, Default: `"Windows <name>"`
- Menu entry title

### `boot.loader.systemd-boot.windows.<name>.sortKey`
- Type: `str`, Default: `"o_windows_<name>"`
- Controls menu ordering

### `boot.loader.systemd-boot.extraEntries`
- Type: `attrsOf lines`
- Arbitrary boot entries (used for Linux chainloading)
- Files must have `.conf` extension and no directory separators

### Internal mechanism
The Windows entries generate a `.conf` file that uses the EDK2 shell as the EFI binary with options:
```
efi /efi/edk2-uefi-shell/shell.efi
options -nointerrupt -nomap -noversion <HANDLE>:EFI\Microsoft\Boot\Bootmgfw.efi
```
