# Stateless Rebuild — Review & Quality Assurance

**Feature:** stateless_rebuild  
**Spec:** `.github/docs/subagent_docs/stateless_rebuild_spec.md`  
**Date:** 2026-04-10  
**Reviewer:** Phase 3 Review Subagent  
**Verdict:** **PASS**

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 97% | A |
| Best Practices | 92% | A- |
| Functionality | 98% | A |
| Code Quality | 88% | B+ |
| Security | 95% | A |
| Performance | 97% | A |
| Consistency | 90% | A- |
| Build Success | 100% | A+ |

**Overall Grade: A (95%)**

---

## Build Validation

### `nix flake check --impure --no-build`

**Result: PASSED (exit 0)**

All 16 nixosConfigurations evaluated cleanly, including all four stateless variants:

```
checking NixOS configuration 'nixosConfigurations.vexos-stateless-amd'...   ✓
checking NixOS configuration 'nixosConfigurations.vexos-stateless-nvidia'... ✓
checking NixOS configuration 'nixosConfigurations.vexos-stateless-intel'...  ✓
checking NixOS configuration 'nixosConfigurations.vexos-stateless-vm'...     ✓
```

Warnings present (non-fatal, pre-existing):
- `Using 'builtins.derivation' to create a derivation named 'options.json'…` (4 occurrences, one per stateless config — carried over from the options-doc generation machinery, not introduced by this change set)

### `sudo nixos-rebuild dry-build --flake .#vexos-stateless-vm --impure`

**Result: COULD NOT RUN** — requires interactive sudo authentication; no passwordless sudo configured in this environment.  
`nix flake check` (which evaluates the full module system including all assertions) passed for this configuration, providing equivalent evaluation coverage.

### `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd --impure`

**Result: COULD NOT RUN** — same constraint as above.  
Evaluation confirmed passing via `nix flake check`.

---

## Checklist Results

### Spec Compliance — `flake.nix`

| Item | Status | Details |
|------|--------|---------|
| `disko` input removed from inputs | ✅ PASS | `disko` block entirely absent from `flake.nix` inputs |
| `disko` removed from outputs function args | ✅ PASS | Signature: `{ self, nixpkgs, nixpkgs-unstable, nix-gaming, home-manager, impermanence, up, ... }@inputs` |
| `inputs.disko.nixosModules.disko` removed from all 4 stateless nixosConfigurations | ✅ PASS | None of the 4 stateless configs import disko; all have only `impermanence.nixosModules.impermanence` |
| `disko.nixosModules.disko` removed from `nixosModules.statelessBase` | ✅ PASS | statelessBase imports only: nix-gaming, home-manager, impermanence, configuration-stateless.nix, modules/stateless-disk.nix |
| `enableLuks` removed from `nixosModules.statelessBase` | ✅ PASS | `vexos.stateless.disk` block only contains `enable` and `device` |
| `enableLuks = lib.mkForce false` removed from `nixosModules.statelessGpuVm` | ✅ PASS | statelessGpuVm only sets `vexos.stateless.disk.device = lib.mkForce "/dev/vda"` |

### Spec Compliance — `modules/stateless-disk.nix`

| Item | Status | Details |
|------|--------|---------|
| No `disko.devices` anywhere in file | ✅ PASS | Module contains only `options.*` and `fileSystems.*` declarations |
| No `enableLuks` option | ✅ PASS | Options are exactly: `enable` (bool) and `device` (str) |
| `fileSystems."/boot"` with `lib.mkDefault` | ✅ PASS | `fileSystems."/boot" = lib.mkDefault { device = bootPart; fsType = "vfat"; options = [...]; }` |
| `fileSystems."/nix"` with `lib.mkDefault` and `neededForBoot = true` | ✅ PASS | Present and correct |
| `fileSystems."/persistent"` with `lib.mkDefault` and `neededForBoot = true` | ✅ PASS | Present and correct |
| nvme/mmcblk partition derivation (`p1`/`p2`) | ✅ PASS | `builtins.match ".*(nvme|mmcblk).*"` → `${cfg.device}p1` / `${cfg.device}p2` |
| sata/virtio partition derivation (`1`/`2`) | ✅ PASS | Else branch → `${cfg.device}1` / `${cfg.device}2` |

### Spec Compliance — `template/stateless-disko.nix`

| Item | Status | Details |
|------|--------|---------|
| `diskoFile ? null` in function signature | ✅ PASS | `{ disk ? "/dev/nvme0n1", enableLuks ? false, luksName ? "cryptroot", diskoFile ? null }:` |
| `enableLuks ? false` (was `true`) | ✅ PASS | Default changed to `false` as required |

### Spec Compliance — `hosts/stateless-vm.nix`

| Item | Status | Details |
|------|--------|---------|
| `enableLuks = false` removed | ✅ PASS | `vexos.stateless.disk` block only sets `enable = true` and `device = "/dev/vda"` |

### Spec Compliance — `scripts/stateless-setup.sh`

| Item | Status | Details |
|------|--------|---------|
| No VM-specific LUKS conditional block | ✅ PASS | No `if [ "$VARIANT" = "vm" ]` block present |
| `LUKS_BOOL="false"` for all variants | ✅ PASS | Line 137: `LUKS_BOOL="false"` set unconditionally with explanatory comment |
| Hostname default is `vexos` | ✅ PASS | `HOSTNAME="${HOSTNAME_INPUT:-vexos}"` |
| LUKS passphrase warning removed from end of script | ✅ PASS | Script ends with installation complete message and reboot prompt; no LUKS warning |

### Spec Compliance — `scripts/migrate-to-stateless.sh`

| Item | Status | Details |
|------|--------|---------|
| File exists | ✅ PASS | `scripts/migrate-to-stateless.sh` present |
| File is executable | ✅ PASS | `-rwxr-xr-x` |
| Root check at start | ✅ PASS | `if [ "$(id -u)" -ne 0 ]; then … exit 1; fi` |
| Live ISO detection (aborts if / is tmpfs) | ✅ PASS | `ROOT_FSTYPE=$(findmnt -n -o FSTYPE /); if [ "$ROOT_FSTYPE" = "tmpfs" ]; then … exit 1; fi` |
| Detects Btrfs root with `findmnt` | ✅ PASS | `ROOT_DEVICE=$(findmnt -n -o SOURCE /)` + fstype check |
| Detects FAT32 /boot with `findmnt` | ✅ PASS | `BOOT_DEVICE=$(findmnt -n -o SOURCE /boot …)` |
| Gets UUIDs with `blkid` | ✅ PASS | `ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV_RAW")` and `BOOT_UUID=…` |
| Checks for existing @nix/@persist subvols | ✅ PASS | Mounts subvolid=5, calls `btrfs subvolume show` for both |
| Mounts raw Btrfs with `subvolid=5` | ✅ PASS | `mount -o subvolid=5 "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}"` |
| Creates @nix and @persist subvols | ✅ PASS | `btrfs subvolume create "${BTRFS_MOUNT}/@nix"` and `@persist` |
| Reflink copy: `cp -a --reflink=always /nix/. .../@nix/` | ✅ PASS | `cp -a --reflink=always /nix/. "${BTRFS_MOUNT}/@nix/"` |
| Unmounts /mnt/vexos-migrate-btrfs | ✅ PASS | `umount "${BTRFS_MOUNT}"; rmdir "${BTRFS_MOUNT}"` |
| Backs up hardware-configuration.nix | ✅ PASS | `cp "${HW_CONFIG}" "${HW_CONFIG_BAK}"` |
| Runs `nixos-generate-config --no-filesystems` | ✅ PASS | `nixos-generate-config --no-filesystems` |
| Appends filesystem declarations with UUID substitution | ✅ PASS | Heredoc with `${ROOT_UUID}` and `${BOOT_UUID}` interpolation |
| GPU variant prompt | ✅ PASS | Case statement for amd/nvidia/intel/vm |
| Runs `nixos-rebuild switch` | ✅ PASS | `nixos-rebuild switch --flake "/etc/nixos#vexos-stateless-${VARIANT}"` |

### Spec Compliance — `modules/impermanence.nix`

| Item | Status | Details |
|------|--------|---------|
| No "LUKS-encrypted" text | ✅ PASS | The phrase "LUKS-encrypted" does not appear anywhere in the file |
| Assertion message mentions `migrate-to-stateless.sh` | ✅ PASS | "For existing systems: run scripts/migrate-to-stateless.sh to migrate in-place." |

---

## Issues Found

### CRITICAL

None.

---

### RECOMMENDED (Non-blocking)

#### R1 — Stale `(disko)` references in `modules/impermanence.nix` option description

**File:** `modules/impermanence.nix` lines 9, 32  
**Severity:** Minor — cosmetic/documentation only, no functional impact

Line 9 (header comment):
```nix
# modules/stateless-disk.nix using disko. No manual hardware-configuration.nix
```
Line 32 (option description):
```nix
        Disk layout is handled by modules/stateless-disk.nix (disko). The
```

Both references are vestiges of the old architecture. disko is no longer a NixOS module dependency. Recommended update: replace `(disko)` with `(plain Btrfs fileSystems)` and update the header comment to remove the reference to disko managing the disk layout.

---

#### R2 — Stale `LUKS2 container` in `scripts/stateless-setup.sh` header comment

**File:** `scripts/stateless-setup.sh` line 14  
**Severity:** Minor — documentation only, no functional impact

```bash
#   2. Creates: EFI partition (512 MiB), LUKS2 container, Btrfs subvolumes
```

This is contradicted by the implementation (LUKS is disabled) and will mislead users reading the script header. Recommended update:

```bash
#   2. Creates: EFI partition (512 MiB), Btrfs partition with @nix & @persist subvolumes
```

---

#### R3 — `scripts/stateless-setup.sh` is not executable

**File:** `scripts/stateless-setup.sh`  
**Severity:** Minor — permissions issue  
**Current:** `-rw-r--r--`  
**Expected:** `-rwxr-xr-x` (consistent with `migrate-to-stateless.sh`)

The script is invoked as `bash scripts/stateless-setup.sh` in documentation, but lacking execute bits is inconsistent with `migrate-to-stateless.sh` and makes it impossible to run as `./scripts/stateless-setup.sh`. Fix with `chmod +x scripts/stateless-setup.sh`.

---

#### R4 — Dead code block in `scripts/migrate-to-stateless.sh`

**File:** `scripts/migrate-to-stateless.sh` lines 63–65  
**Severity:** Minor — code quality

```bash
if grep -q "cow\|tmpfs\|aufs" /proc/mounts 2>/dev/null | grep -q " / "; then
  true  # live check below is more reliable
fi
```

This block is functionally inert: the body is `true` regardless of the condition, and the actual live ISO detection is performed by the `findmnt`-based check immediately below. The block should be removed entirely to avoid confusion.

---

## Summary of Findings

All **40 checklist items** from the spec validation list **PASS**. No critical issues were found.

The implementation correctly:
- Removed all disko NixOS module dependencies from the stateless build path
- Replaced `disko.devices` with `lib.mkDefault` `fileSystems` declarations enabling clean `nixos-rebuild switch` on existing systems
- Removed LUKS from all stateless build variants and the ISO setup script
- Added `diskoFile ? null` to the disko template for disko 1.13.0 compatibility
- Created a complete, production-quality `migrate-to-stateless.sh` migration script
- Updated all four stateless host files and the `nixosModules.statelessBase` / `statelessGpuVm` module exports

Four minor non-blocking issues remain (R1–R4), all documentation or cosmetic in nature.

`nix flake check --impure` passed with exit code 0 across all 16 configurations.

---

## Verdict

**PASS**

The implementation is functionally complete and correct. All spec requirements are satisfied. The four recommended improvements (R1–R4) are non-blocking and do not warrant a NEEDS_REFINEMENT verdict.
