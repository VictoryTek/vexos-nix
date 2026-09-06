# stateless_persistent_swap — Spec

## Problem

Testing the `stateless` role inside a Proxmox VM causes OOM even after raising the
balloon-max from 6 GB to 8 GB. Raising VM RAM further is not a durable fix — the
underlying config has **no real disk-backed swap overflow** for the stateless role,
on a VM or bare metal.

## Current state (verified by reading source)

- `modules/system.nix:22-34,168-183` — `vexos.swap.enable` (default `true`) creates
  an 8 GiB disk-backed swapfile at `/var/lib/swapfile`. This is the only mechanism in
  the repo that provides genuine disk overflow beyond RAM.
- `modules/impermanence.nix:139-142` — for the stateless role, `vexos.swap.enable` is
  forced to `false` because `/var/lib/swapfile` would resolve onto the ephemeral tmpfs
  root (`/`), which is backed by RAM, not disk — a "swapfile" there would just move RAM
  around, not add capacity. This reasoning is correct; the force-off itself is not the
  bug.
- `modules/gpu/vm.nix:51` — also forces `vexos.swap.enable = false` for all VM guests,
  independently, reasoning that "hypervisor memory management" (ballooning) covers it.
  In practice ballooning is reactive (grows only after memory pressure is already
  detected) and cannot substitute for a real overflow device during a sudden build-time
  spike.
- `modules/system.nix:126-132` — `zramSwap` (lz4, `memoryPercent = 50`) is unconditional
  and already active for stateless/VM. It is RAM-backed compressed swap, not disk
  overflow — once RAM + zram capacity is exhausted, the only remaining outcome is the
  OOM killer.
- `modules/stateless-disk.nix:109-117` — the stateless role always mounts a real,
  disk-backed Btrfs subvolume at `/persistent` (`@persist` subvolume, `neededForBoot =
  true`, mounted in initrd before stage 2 — same subvolume group as `/nix`). This path
  is available on every stateless install, VM or bare metal, and is exactly the kind of
  disk-backed location the existing swapfile reasoning says is required.
- Verified against current `nixpkgs/nixos/modules/config/swap.nix` (master, fetched
  2026-09-06): when a `swapDevices.*.device` with `size` set resolves onto a btrfs
  filesystem, the module detects this (`stat -f -c %T "$(dirname "$DEVICE")"` ==
  `btrfs`) and creates the file with `btrfs filesystem mkswapfile --size … --uuid
  clear`, which handles NOCOW and disabling compression automatically. A swapfile
  placed on `/persistent` (Btrfs, `compress=zstd` mount option) is therefore safe and
  requires no extra `chattr`/nodatacow handling on our part — NixOS already does it.

## Root cause

Stateless installs (VM or bare metal) have **no disk overflow valve at all**: the only
two swap-like mechanisms (zram, and the generic `/var/lib/swapfile`) are either
RAM-backed or force-disabled, and nothing was added in their place. Under memory
pressure (e.g. building with the unstable overlay inside the VM), the kernel has
nowhere to go once zram fills, and the OOM killer fires regardless of balloon size.

## Proposed fix

Add a real disk-backed swapfile on the `/persistent` Btrfs subvolume, inside
`modules/impermanence.nix`'s own `config = lib.mkIf cfg.enable { ... }` block (already
gated by an option this module declares — satisfies the Module Architecture Pattern
carve-out; no new role-gating `lib.mkIf` is introduced).

- Keep `vexos.swap.enable = lib.mkForce false;` as-is — the generic
  `/var/lib/swapfile` path is still wrong under tmpfs root; this is not being reverted.
- Add directly to the same config block:
  ```nix
  swapDevices = [
    {
      device = "${cfg.persistentPath}/swapfile";
      size   = 8192; # 8 GiB — matches the repo-wide swapfile size convention (modules/system.nix)
    }
  ];
  ```
- Update the existing comment above the `vexos.swap.enable = lib.mkForce false;` line
  to explain the two-part story: the generic path is disabled because it would land on
  tmpfs, but a real disk-backed swapfile is provided separately on `/persistent`.
- No new options are introduced (matches existing repo convention: swap size is
  hardcoded elsewhere too, not user-configurable).
- `modules/gpu/vm.nix:51` is untouched — its force-off only affects the (already
  disabled for stateless) generic swapfile path; it has no bearing on this new
  Btrfs-backed swapfile, since that's a distinct `swapDevices` list entry.

## Why this is the minimal correct fix

- Uses an already-mounted, `neededForBoot = true` disk-backed filesystem — no new
  mount, no new disk layout changes, no changes to `scripts/stateless-setup.sh` or
  `scripts/migrate-to-stateless.sh`.
- Applies uniformly to every stateless install (VM and bare metal) since `/persistent`
  always exists for this role — no role/display/gaming `lib.mkIf` branching needed.
- Verified safe against actual upstream NixOS swap-module behavior for Btrfs, not
  assumed.
- Does not touch zram or tmpfs sizing (`modules/system.nix`), since those are
  memory-pressure-driven caps, not the actual gap — the gap is the total absence of a
  disk overflow device.

## Risks / mitigations

- **Disk space**: the swapfile competes for space on the same Btrfs volume as `/nix`
  and `/persistent` data. Mitigated by keeping the same 8 GiB size already used
  elsewhere in the repo (no larger); if a host's disk is too small, `mkswapfile` will
  fail loudly at activation time rather than silently corrupting data.
- **Hibernate**: not claimed or wired up for this swapfile (no `resumeDevice`
  configured) — out of scope; this is overflow capacity only, matching the existing
  scope of this task.
- **Build validation**: must confirm `nix flake show --impure` and
  `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` (and `-vm` variant if one
  exists) still evaluate cleanly, and that the impermanence module's existing
  assertions are unaffected.

## Files to modify

- `modules/impermanence.nix` (only file touched)
