# L-08 — zfs-server.nix installs pkgs.zfs alongside the module-managed build

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-08 (BUGS L8) · `modules/zfs-server.nix:50-55`
(current file: the `environment.systemPackages` block is lines 50-55,
matching the cited range)

## Current State

`modules/zfs-server.nix:50-55`:
```nix
environment.systemPackages = with pkgs; [
  zfs           # zpool, zfs (also pulled in by boot.supportedFilesystems but listed for clarity)
  gptfdisk      # sgdisk
  util-linux    # wipefs, lsblk
  pciutils      # lspci (optional, for disk topology hints)
];
```

Verified directly against the upstream ZFS NixOS module
(`nixos/modules/tasks/filesystems/zfs.nix`, fetched at this repo's
pinned nixpkgs rev `e4bae1bd10c9c57b2cf517953ab70060a828ee6f` from
`flake.lock`):

```nix
package = lib.mkOption {
  type = lib.types.package;
  default = pkgs.zfs;
  defaultText = lib.literalExpression "pkgs.zfs";
  description = "Configured ZFS userland tools package.";
};
...
environment.systemPackages = [ cfgZfs.package ] ++ lib.optional cfgSnapshots.enable autosnapPkg;
```

So the upstream module already unconditionally installs
`config.boot.zfs.package` (default `pkgs.zfs`) whenever
`boot.supportedFilesystems` includes `"zfs"` — the comment in this
repo's file ("also pulled in by boot.supportedFilesystems") is
accurate. `boot.zfs.package` is the officially supported override point
for choosing a specific ZFS userland build (e.g. pinning a compat
version, or `zfs_unstable`); it is **not** itself derived from
`boot.kernelPackages` — only the *kernel module* half
(`modulePackage = selectModulePackage cfgZfs.package`) is
version-matched off of it.

Confirmed via repo-wide grep that nothing here currently sets
`boot.zfs.package` — so today, `pkgs.zfs` (this file's literal
reference) and `config.boot.zfs.package` (the module's default)
evaluate to the exact same derivation, and there is no *live* version
skew right now.

## Problem Definition

The two references (`pkgs.zfs` here vs. `config.boot.zfs.package`
inside the upstream module) are only accidentally identical because
neither is currently overridden. If `boot.zfs.package` is ever set
explicitly in this repo (a legitimate, supported use of that option —
e.g. to pin a specific ZFS release, matching the same instinct already
exercised for `boot.kernelPackages` two blocks above in this same
file), this file's hardcoded `pkgs.zfs` would silently continue
installing the *old* default build alongside the newly-configured one,
producing two different `zfs`/`zpool` userland derivations in the same
system closure with undefined PATH/symlink precedence between them —
exactly the failure mode the file's own comment ("also pulled in... but
listed for clarity") assumes cannot happen.

## Proposed Solution

Reference `config.boot.zfs.package` instead of the plain `pkgs.zfs`
attribute, so this line always tracks whatever the module is actually
configured to install — including in the current, unconfigured case,
where it evaluates to the exact same thing it does today.

## Implementation Steps

1. `modules/zfs-server.nix:51` — change
   `zfs           # zpool, zfs (also pulled in by boot.supportedFilesystems but listed for clarity)`
   to
   `config.boot.zfs.package  # zpool, zfs (already pulled in by boot.supportedFilesystems; referenced explicitly so this stays correct if boot.zfs.package is ever pinned)`
   — moving it out of the `with pkgs; [ ... ]` list (since
   `config.boot.zfs.package` is not a `pkgs.*` attribute) while keeping
   the other three entries (`gptfdisk`, `util-linux`, `pciutils`) under
   `with pkgs;`.

## Configuration Changes

None — no new NixOS options; this only changes which existing option's
value a pre-existing line references.

## Risks and Mitigations

- **Risk:** listing `config.boot.zfs.package` explicitly duplicates an
  entry the upstream module already adds unconditionally
  (`environment.systemPackages = [ cfgZfs.package ] ++ ...`).
  **Mitigation:** confirmed this is harmless — `environment.systemPackages`
  is a plain list, and NixOS's profile-building tooling dedupes by
  store path; two identical entries for the same derivation produce no
  conflict (unlike today's risk, which is two *different* derivations
  for the same tool).
- **Risk:** moving `config.boot.zfs.package` out of the `with pkgs; [...]`
  block could be a syntax trap if done carelessly (e.g. leaving it
  inside the `with pkgs;` scope, where `config` still resolves fine
  since `with pkgs;` doesn't shadow the module's own `config` argument
  — but keeping it visually separated avoids reader confusion about
  which package set it comes from).
  **Mitigation:** verify in Phase 3 that the file still evaluates
  syntactically (`config` is already in scope from this module's
  `{ config, lib, pkgs, ... }:` argument list, used elsewhere in the
  same file, e.g. the `assertions` block's
  `config.networking.hostId`).
