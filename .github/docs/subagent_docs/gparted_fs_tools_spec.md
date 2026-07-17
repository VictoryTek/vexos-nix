# gparted_fs_tools — Spec

## Current State Analysis

`gparted` is installed system-wide in [modules/packages-desktop.nix](../../modules/packages-desktop.nix),
shared by the `desktop`, `server`, `htpc`, and `stateless` roles (per the file's header
comment and its `environment.systemPackages` import chain in each role's
`configuration-*.nix`).

gparted delegates all format/resize operations to external `mkfs.*` CLI tools found on
`$PATH`. It greys out any filesystem whose tool is missing. The module currently installs
only `gparted` itself — no filesystem-specific helper packages. `btrfs-progs` exists
elsewhere ([modules/system.nix:171](../../modules/system.nix#L171)), which is why btrfs
already works. ext2/3/4 works without an explicit package because `e2fsprogs` is a core
NixOS system dependency pulled in transitively.

## Problem Definition

NTFS, FAT32, and exFAT format options are greyed out in gparted on `desktop-nvidia` (and,
by inheritance, on every role importing `packages-desktop.nix`) because `mkfs.ntfs`,
`mkfs.vfat`, and `mkfs.exfat` are not on `$PATH`.

## Proposed Solution

Add the three cross-platform filesystem utility packages to the existing
`environment.systemPackages` list in `modules/packages-desktop.nix`:

- `ntfs3g` — provides `mkfs.ntfs` (NTFS)
- `dosfstools` — provides `mkfs.vfat` / `mkfs.fat` (FAT16/FAT32)
- `exfatprogs` — provides `mkfs.exfat` (exFAT)

Verified present in the `stable` nixpkgs channel via the NixOS MCP package index:
`ntfs3g` 2022.10.3, `dosfstools` 4.2, `exfatprogs` 1.3.0.

This is a same-file, same-list addition — no new module, no `lib.mkIf`, no role-gating
logic. It follows Option B implicitly: since `packages-desktop.nix` is itself the shared
base file for the desktop-having roles, adding to its existing list applies uniformly to
all of them, matching how `gparted` itself is already declared there.

## Implementation Steps

1. Edit `modules/packages-desktop.nix`: add `ntfs3g`, `dosfstools`, `exfatprogs` to the
   `environment.systemPackages` list, each with a one-line comment naming the format it
   unlocks in gparted.

## Dependencies

No new flake inputs. All three packages come from the existing `nixpkgs` input already
used by this list (no Context7 lookup needed — these are plain nixpkgs packages, not a
versioned library/API integration).

## Configuration Changes

None beyond the package list edit.

## Risks and Mitigations

- **Risk:** None of these packages register systemd services, open ports, or run
  daemons — they are inert CLI tools invoked on-demand by gparted (via polkit).
  No security surface change.
- **Risk:** Minor closure size increase (~a few MB). Acceptable given `gparted` is
  already a desktop-only package.
- **Mitigation:** Restrict to `modules/packages-desktop.nix` only — do not touch
  `headless-server`, which does not import this file and has no GUI disk tool anyway.
