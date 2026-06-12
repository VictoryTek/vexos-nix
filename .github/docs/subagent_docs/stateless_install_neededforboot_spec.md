# Spec: Fix stateless install — neededForBoot assertion failure

## Current State Analysis

`stateless-setup.sh` (the fresh ISO install path for the stateless role) calls:
```bash
sudo nixos-generate-config --root /mnt
```
WITHOUT the `--no-filesystems` flag. This generates `/mnt/etc/nixos/hardware-configuration.nix`
with filesystem entries for `/boot`, `/nix`, and `/persistent` — but without `neededForBoot = true`.

`modules/stateless-disk.nix` tries to add `neededForBoot = true` via:
```nix
fileSystems."/nix" = lib.mkDefault {
  ...
  neededForBoot = lib.mkForce true;
};
```
However, the NixOS module system uses priority to resolve `attrsOf submodule` attribute sets.
`hardware-configuration.nix` defines `fileSystems."/nix"` at priority 100 (default), which
**supersedes** the `lib.mkDefault` (priority 1000) block from `stateless-disk.nix` entirely —
including the `neededForBoot` attribute within it.

`modules/impermanence.nix` asserts that `fileSystems."/nix".neededForBoot` and
`fileSystems."/persistent".neededForBoot` are both `true`. Since hardware-configuration.nix
doesn't set `neededForBoot`, these assertions fail and `nixos-install` aborts.

**Contrast with `migrate-to-stateless.sh`:** the migration path uses `--no-filesystems` and
manually appends filesystem entries with `neededForBoot = true`. The fresh install path never
adopted this pattern.

## Problem Definition

`nixos-install` fails with assertion errors during a fresh stateless install from the live ISO
because `hardware-configuration.nix` is generated with complete filesystem entries (overriding
`stateless-disk.nix`'s `lib.mkDefault` definitions) but without `neededForBoot = true` on the
`/nix` and `/persistent` entries that impermanence requires.

## Proposed Solution Architecture

### Fix 1 — `scripts/stateless-setup.sh` (primary fix)

Mirror the approach used by `migrate-to-stateless.sh`:

1. Change `nixos-generate-config --root /mnt` → `nixos-generate-config --no-filesystems --root /mnt`
2. After generation, capture partition UUIDs from disko's by-partlabel paths:
   - `/dev/disk/by-partlabel/disk-main-ESP` → boot UUID
   - `/dev/disk/by-partlabel/disk-main-data` → root UUID
3. Strip the trailing `}` from the generated file (same perl/head pattern as migrate script)
4. Append stateless filesystem declarations with `neededForBoot = true` — identical format to
   what `migrate-to-stateless.sh` appends

### Fix 2 — `modules/stateless-disk.nix` (defensive fix)

Add **separate** top-level `lib.mkForce` definitions for `neededForBoot` that are NOT wrapped
in `lib.mkDefault`. These sit alongside the full-entry `lib.mkDefault` blocks and apply at
priority 0 regardless of what hardware-configuration.nix defines:

```nix
# Force neededForBoot regardless of what hardware-configuration.nix provides.
# The lib.mkDefault full-entry blocks above are overridden when hardware-configuration.nix
# defines the same filesystem key at priority 100. These separate definitions are at
# priority 0 (lib.mkForce) and therefore always win.
fileSystems."/nix".neededForBoot = lib.mkForce true;
fileSystems."/persistent".neededForBoot = lib.mkForce true;
```

Also simplify the now-redundant `neededForBoot = lib.mkForce true` inside the `/nix`
`lib.mkDefault` block to plain `neededForBoot = true` (the outer `lib.mkDefault` is at
priority 1000, so the inner `lib.mkForce` has no effect when overridden by hardware-configuration.nix).

## Implementation Steps

1. Edit `scripts/stateless-setup.sh`:
   - Change `nixos-generate-config --root /mnt` to `nixos-generate-config --no-filesystems --root /mnt`
   - Update the progress message from "with UUID-based filesystem entries" to just "hardware configuration"
   - Capture `BOOT_UUID` and `ROOT_UUID` after nixos-generate-config
   - Append the stateless filesystem block (matching migrate-to-stateless.sh format exactly)

2. Edit `modules/stateless-disk.nix`:
   - Add `fileSystems."/nix".neededForBoot = lib.mkForce true;`
   - Add `fileSystems."/persistent".neededForBoot = lib.mkForce true;`
   - Simplify `neededForBoot = lib.mkForce true` inside the `/nix` `lib.mkDefault` to `neededForBoot = true`
   - Update module comment to reflect that fresh installs now also generate proper hardware-configuration.nix entries

## Dependencies

No new external dependencies. Pure Nix/bash changes.

## Configuration Changes

None — the generated hardware-configuration.nix content changes (correct UUID entries with `neededForBoot = true`) but the user-visible behaviour is identical.

## Risks and Mitigations

- **Risk:** `blkid` returning empty string if partlabels haven't settled after disko.
  **Mitigation:** Both `disk-main-ESP` and `disk-main-data` are set by disko `sgdisk` commands
  and confirmed present in the live installer output. `udevadm settle` is called by disko before
  returning, so partlabels are stable.

- **Risk:** `perl` not available on live ISO.
  **Mitigation:** Same fallback pattern as `migrate-to-stateless.sh` (`|| head -n -1`).

- **Risk:** The stateless-disk.nix `lib.mkForce` on `neededForBoot` could conflict with
  hardware-configuration.nix that explicitly sets `neededForBoot = false` (pathological case).
  **Mitigation:** This is intentional — impermanence REQUIRES `neededForBoot = true`.
  Anyone setting it to `false` explicitly is breaking their own stateless install.
