# Spec: Fix disko / hardware-configuration.nix fileSystems Device Conflict

**Feature name:** `privacy_vm_disko_conflict`
**Date:** 2026-04-10
**File to modify:** `modules/privacy-disk.nix` (only)

---

## 1. Current State Analysis

`modules/privacy-disk.nix` is the disko-backed disk layout module for the
VexOS privacy role. Its `config` block (inside `lib.mkIf cfg.enable { }`)
currently sets:

```nix
fileSystems."/persistent".neededForBoot = lib.mkForce true;
fileSystems."/nix".neededForBoot        = lib.mkForce true;
```

It does **not** set `lib.mkForce` overrides for the `.device` attribute of
any mount point.

`privacyBase` in `flake.nix` (line ~270) imports both
`disko.nixosModules.disko` and `./modules/privacy-disk.nix`, and enables
`vexos.privacy.disk.enable = true`.

The disko partition layout in `privacy-disk.nix` defines:

| Partition name | Disk name | Generated partlabel     | Mount   |
|----------------|-----------|-------------------------|---------|
| `ESP`          | `main`    | `disk-main-ESP`         | `/boot` |
| `luks`         | `main`    | `disk-main-luks`        | (raw)   |
| `data`         | `main`    | `disk-main-data`        | `/nix`, `/persistent` (no-LUKS path) |
| LUKS mapper    | —         | `/dev/mapper/<luksName>` | `/nix`, `/persistent` (LUKS path) |

disko generates `fileSystems` entries using these partlabels/mapper paths at
the default module priority (100).

---

## 2. Problem Definition

When `hardware-configuration.nix` is generated **without** the
`--no-filesystems` flag (which is the common / default case), it emits its own
`fileSystems` entries derived from the UUID/PARTUUID values observed at
generation time:

```
fileSystems."/boot".device = "/dev/disk/by-uuid/B120-D905";   # from hw-config
fileSystems."/boot".device = "/dev/disk/by-partlabel/disk-main-ESP"; # from disko
```

Both definitions have priority 100 (the NixOS module default). The NixOS
module system treats `fileSystems."<mount>".device` as a scalar string option
and requires exactly one definition — two equal-priority definitions produce
a hard evaluation error:

```
error: The option `fileSystems."/boot".device' has conflicting definition values:
- In `hardware-configuration.nix': "/dev/disk/by-uuid/B120-D905"
- In `module.nix': "/dev/disk/by-partlabel/disk-main-ESP"
```

The same conflict will appear for `/nix` and `/persistent` if
`hardware-configuration.nix` was generated without `--no-filesystems`.

**Root cause:** `privacy-disk.nix` does not force its device declarations to
take precedence over whatever `hardware-configuration.nix` declares.

**Note on `fileSystems.options`:** This attribute is a `listOf` type and is
merged by union, so no conflict occurs there. Only `.device` (a scalar string)
is affected.

---

## 3. Proposed Solution

Add `lib.mkForce` overrides for `.device` on all three disko-managed mount
points directly in the `config = lib.mkIf cfg.enable { }` block, immediately
after the existing `neededForBoot` lines.

`lib.mkForce` sets priority 50, which is below all `mkOverride` / user-level
overrides but above the default priority-100 definitions from
`hardware-configuration.nix`. This causes the disko-declared device to win
the merge without changing any other behaviour.

### Exact code change

**File:** `modules/privacy-disk.nix`

**Find** (the last two lines of the `config` block, with their comment):

```nix
    # disko generates fileSystems entries for /nix and /persistent but does
    # not set neededForBoot.  impermanence requires neededForBoot = true on
    # /persistent so that bind mounts are available during early userspace.
    # /nix is also flagged so the Nix store is available before activation.
    # lib.mkForce overrides the disko default (false) without causing a conflict.
    fileSystems."/persistent".neededForBoot = lib.mkForce true;
    fileSystems."/nix".neededForBoot        = lib.mkForce true;

  };
}
```

**Replace with:**

```nix
    # disko generates fileSystems entries for /nix and /persistent but does
    # not set neededForBoot.  impermanence requires neededForBoot = true on
    # /persistent so that bind mounts are available during early userspace.
    # /nix is also flagged so the Nix store is available before activation.
    # lib.mkForce overrides the disko default (false) without causing a conflict.
    fileSystems."/persistent".neededForBoot = lib.mkForce true;
    fileSystems."/nix".neededForBoot        = lib.mkForce true;

    # Override filesystem device paths so disko's partlabel-/mapper-based
    # declarations take priority over any conflicting entries in
    # hardware-configuration.nix (generated without --no-filesystems).
    # lib.mkForce sets priority 50, which defeats the default priority-100
    # definitions emitted by nixos-generate-config without affecting any
    # user-level mkForce / mkOverride declarations.
    fileSystems."/boot".device = lib.mkForce "/dev/disk/by-partlabel/disk-main-ESP";
    fileSystems."/nix".device = lib.mkForce (
      if cfg.enableLuks
      then "/dev/mapper/${cfg.luksName}"
      else "/dev/disk/by-partlabel/disk-main-data"
    );
    fileSystems."/persistent".device = lib.mkForce (
      if cfg.enableLuks
      then "/dev/mapper/${cfg.luksName}"
      else "/dev/disk/by-partlabel/disk-main-data"
    );

  };
}
```

### Why these values are correct

| Mount        | LUKS path                           | non-LUKS path                                  |
|--------------|-------------------------------------|------------------------------------------------|
| `/boot`      | `/dev/disk/by-partlabel/disk-main-ESP` (always; ESP is never encrypted) | same |
| `/nix`       | `/dev/mapper/${cfg.luksName}`       | `/dev/disk/by-partlabel/disk-main-data`        |
| `/persistent`| `/dev/mapper/${cfg.luksName}`       | `/dev/disk/by-partlabel/disk-main-data`        |

- Partition `ESP` on disk `main` → disko-generated partlabel `disk-main-ESP` ✓  
- Partition `data` on disk `main` → disko-generated partlabel `disk-main-data` ✓  
- `cfg.luksName` is defined as a module option with default `"cryptroot"` and
  is in scope inside the `config = lib.mkIf cfg.enable { }` block ✓  
- `fsType` values (`vfat` for `/boot`, `btrfs` for `/nix`/`/persistent`) are
  identical in both disko and hw-config → no conflict there ✓  
- `fileSystems.options` is `listOf` → merged by union, no conflict ✓  

---

## 4. File to Modify

| File | Change type |
|------|-------------|
| `modules/privacy-disk.nix` | Add 13 lines (comment block + 3 `lib.mkForce` device overrides) inside existing `config` block |

No other files need modification.

---

## 5. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Partlabel name mismatch (e.g. disk not named `main`) | Low | The disko config in this file explicitly names the disk `disk.main`, so partlabels are deterministic. If `cfg.device` is changed, partlabels remain the same (disko uses the disk *key*, not the device path). |
| `lib.mkForce` (priority 50) defeated by a user `lib.mkForce` in hw-config | Very low | A second `lib.mkForce` at the same priority would re-introduce a conflict visible at evaluation time. The correct fix is always `--no-filesystems` at generation time. This fix only guards against the common default case. |
| Non-LUKS VM path: both `/nix` and `/persistent` on same btrfs partition via different subvolumes | Expected | disko correctly mounts two subvolumes from the same block device; the `.device` override simply reflects that shared device path. |
| `cfg.luksName` changing per-host | Handled | The mkForce expression uses `cfg.luksName` dynamically, so host-level overrides of `luksName` are automatically respected. |
| `fsType` conflict for `/nix`/`/persistent` between hw-config and disko | None | `fsType` is also a scalar option, but `hardware-configuration.nix` generated without `--no-filesystems` emits `fsType = "btrfs"` matching disko's declaration, so no conflict exists. If a conflict were introduced it would be resolved by adding a parallel `lib.mkForce` for `fsType`. |

---

## 6. Validation Steps

After implementation:

1. `nix flake check` — must pass with no evaluation errors
2. `sudo nixos-rebuild dry-build --flake .#vexos-privacy-vm` (or equivalent privacy host) — must complete without the `conflicting definition values` error
3. Confirm `fileSystems."/boot".device` resolves to `disk-main-ESP` in the evaluated config:
   ```
   nix eval .#nixosConfigurations.vexos-privacy-vm.config.fileSystems."/boot".device
   # expected: "/dev/disk/by-partlabel/disk-main-ESP"
   ```
