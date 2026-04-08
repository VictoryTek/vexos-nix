# Boot Label — Desktop Role & Date Removal Spec

**Feature:** `boot_label_desktop`
**Date:** 2026-04-08
**Status:** Specification

---

## 1. Current State

### 1.1 Current Boot Entry Format

```
VexOS AMD (Generation 1 25.11 (Linux 6.12.63), built on 2026-04-08)
VexOS NVIDIA (Generation 1 25.11 (Linux 6.12.63), built on 2026-04-08)
VexOS Intel (Generation 1 25.11 (Linux 6.12.63), built on 2026-04-08)
VexOS VM (Generation 1 25.11 (Linux 6.12.63), built on 2026-04-08)
```

### 1.2 Source of the Label Components

| Component | Source |
|---|---|
| `VexOS AMD` (distro name) | `system.nixos.distroName` in `hosts/amd.nix` |
| `VexOS` fallback default | `system.nixos.distroName = lib.mkDefault "VexOS"` in `modules/branding.nix` |
| `25.11` (label suffix) | `system.nixos.label = "25.11"` in `modules/branding.nix` |
| `, built on YYYY-MM-DD` | Hardcoded in NixOS's systemd-boot Python installer script; not exposed as a NixOS option |

### 1.3 Bootloader Configuration Location

The systemd-boot loader is configured in `template/etc-nixos-flake.nix` inside the `bootloaderModule` attribute set:

```nix
bootloaderModule = {
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;
};
```

This is the host-side template. The `boot.loader.systemd-boot.extraInstallCommands` option, when set here, runs as root after systemd-boot writes each generation's `.conf` entry to the ESP.

---

## 2. Problem Definition

### 2.1 Missing "Desktop" Role Identifier

The current `system.nixos.distroName` values (`VexOS AMD`, `VexOS NVIDIA`, etc.) do not include a role tier. The user wants all variants to carry a "Desktop" identifier to distinguish them from potential future roles (Server, Minimal, etc.).

### 2.2 "built on DATE" Suffix

The `, built on YYYY-MM-DD` suffix is appended by NixOS's internal systemd-boot installer (`nixos/modules/system/boot/loader/systemd-boot/systemd-boot-builder.py`). It is not controlled by any public NixOS module option. The only supported mechanism to remove it post-install is `boot.loader.systemd-boot.extraInstallCommands`, which executes a shell script as root after each `bootctl install`/`bootctl update` run.

---

## 3. Proposed Solution

### 3.1 Desired Boot Entry Format

```
VexOS Desktop AMD (Generation 1 25.11 (Linux 6.12.63))
VexOS Desktop NVIDIA (Generation 1 25.11 (Linux 6.12.63))
VexOS Desktop Intel (Generation 1 25.11 (Linux 6.12.63))
VexOS Desktop VM (Generation 1 25.11 (Linux 6.12.63))
```

### 3.2 Change 1 — Add "Desktop" Role to distroName

Update `system.nixos.distroName` in five locations:

| File | Old Value | New Value |
|---|---|---|
| `modules/branding.nix` | `lib.mkDefault "VexOS"` | `lib.mkDefault "VexOS Desktop"` |
| `hosts/amd.nix` | `"VexOS AMD"` | `"VexOS Desktop AMD"` |
| `hosts/nvidia.nix` | `"VexOS NVIDIA"` | `"VexOS Desktop NVIDIA"` |
| `hosts/intel.nix` | `"VexOS Intel"` | `"VexOS Desktop Intel"` |
| `hosts/vm.nix` | `"VexOS VM"` | `"VexOS Desktop VM"` |

### 3.3 Change 2 — Strip ", built on DATE" via extraInstallCommands

Add `boot.loader.systemd-boot.extraInstallCommands` to the `bootloaderModule` in `template/etc-nixos-flake.nix`:

```nix
bootloaderModule = {
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.extraInstallCommands = ''
    for f in /boot/loader/entries/*.conf; do
      [ -f "$f" ] && sed -i 's/, built on [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//' "$f"
    done
  '';
};
```

**Regex notes:**
- Uses POSIX BRE syntax (default for `sed -i` on Linux/GNU sed).
- `[0-9]\{4\}` matches exactly 4 digits (year); `[0-9]\{2\}` matches 2 digits.
- Anchored to the literal prefix `, built on ` — will not match partial or malformed strings.
- If no `.conf` files exist (e.g., degraded ESP), the `for` loop body is never reached — safe no-op.

---

## 4. Implementation Steps

### Step 1 — `modules/branding.nix`

Locate the line:
```nix
  system.nixos.distroName = lib.mkDefault "VexOS";
```
Change to:
```nix
  system.nixos.distroName = lib.mkDefault "VexOS Desktop";
```

### Step 2 — `hosts/amd.nix`

Locate:
```nix
  system.nixos.distroName = "VexOS AMD";
```
Change to:
```nix
  system.nixos.distroName = "VexOS Desktop AMD";
```

### Step 3 — `hosts/nvidia.nix`

Locate:
```nix
  system.nixos.distroName = "VexOS NVIDIA";
```
Change to:
```nix
  system.nixos.distroName = "VexOS Desktop NVIDIA";
```

### Step 4 — `hosts/intel.nix`

Locate:
```nix
  system.nixos.distroName = "VexOS Intel";
```
Change to:
```nix
  system.nixos.distroName = "VexOS Desktop Intel";
```

### Step 5 — `hosts/vm.nix`

Locate:
```nix
  system.nixos.distroName = "VexOS VM";
```
Change to:
```nix
  system.nixos.distroName = "VexOS Desktop VM";
```

### Step 6 — `template/etc-nixos-flake.nix`

Locate the `bootloaderModule` block:
```nix
    bootloaderModule = {
      boot.loader.systemd-boot.enable      = true;
      boot.loader.efi.canTouchEfiVariables = true;
    };
```
Replace with:
```nix
    bootloaderModule = {
      boot.loader.systemd-boot.enable      = true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.systemd-boot.extraInstallCommands = ''
        for f in /boot/loader/entries/*.conf; do
          [ -f "$f" ] && sed -i 's/, built on [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//' "$f"
        done
      '';
    };
```

---

## 5. Files Modified

- `modules/branding.nix`
- `hosts/amd.nix`
- `hosts/nvidia.nix`
- `hosts/intel.nix`
- `hosts/vm.nix`
- `template/etc-nixos-flake.nix`

---

## 6. Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `.conf` glob matches no files (empty ESP) | Low | `[ -f "$f" ]` guard makes the `sed` call a no-op |
| `sed` not available in PATH during `extraInstallCommands` | Very Low | GNU sed is always present in the NixOS stage-2 environment; `systemd-boot-builder.py` runs in a fully activated system |
| Regex matches unintended text | Very Low | Pattern is anchored to `, built on ` literal prefix plus strict digit-count BRE quantifiers |
| `extraInstallCommands` runs on BIOS/GRUB builds | N/A | Only evaluated when `boot.loader.systemd-boot.enable = true`; GRUB users override `bootloaderModule` entirely per the template header comment |
| PRETTY_NAME in `/etc/os-release` also changes | Expected & Desired | `system.nixos.distroName` sets both the boot label and `PRETTY_NAME=`; the new "Desktop" string is correct for both |
| `hostnamectl` shows new name | Expected & Desired | `hostnamectl` reads `PRETTY_NAME` from `/etc/os-release`; "VexOS Desktop AMD" etc. is correct |

---

## 7. Validation

After rebuild, verify:

```sh
# Boot menu entries (inspect ESP directly)
cat /boot/loader/entries/*.conf | grep title

# os-release
grep PRETTY_NAME /etc/os-release

# hostnamectl
hostnamectl | grep "Operating System"
```

Expected output examples:
```
title VexOS Desktop AMD (Generation N 25.11 (Linux X.X.X))
PRETTY_NAME="VexOS Desktop AMD"
Operating System: VexOS Desktop AMD
```
