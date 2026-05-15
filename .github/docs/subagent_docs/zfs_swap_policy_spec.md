# ZFS Swap Policy Specification
**Feature:** `zfs_swap_policy`
**Phase:** 1 — Research & Specification
**Date:** 2026-05-15

---

## 1. Current State Analysis

### 1.1 `vexos.swap.enable` — option already exists

The option is **fully implemented** in `modules/system.nix` (lines 22–32):

```nix
vexos.swap.enable = lib.mkOption {
  type    = lib.types.bool;
  default = true;
  description = ''
    Enable an 8 GiB persistent swap file at /var/lib/swapfile.
    Provides true overflow capacity beyond RAM + ZRAM, and enables
    system hibernate support. Set to false on VM guests.
  '';
};
```

The option controls `swapDevices` via a guard at line 106:

```nix
(lib.mkIf config.vexos.swap.enable {
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size   = 8192; # 8 GiB in MiB
    }
  ];
})
```

**No option creation is needed.** The fix is purely a matter of setting a default value in the right module.

### 1.2 ZRAM swap is unconditional

`modules/system.nix` also configures ZRAM swap unconditionally (not gated by `vexos.swap.enable`):

```nix
zramSwap = {
  enable        = true;
  algorithm     = "lz4";
  memoryPercent = 50;
};
```

This means disabling `vexos.swap.enable` removes only the **disk-backed 8 GiB swapfile** — ZRAM compressed-RAM swap continues to function normally. Servers will retain fast in-RAM overflow without any ZFS interaction.

### 1.3 Existing uses of `vexos.swap.enable = false`

| File | Value | Purpose |
|------|-------|---------|
| `modules/gpu/vm.nix` (line 37) | `= false` (priority 100) | VMs use hypervisor memory management |
| `modules/impermanence.nix` (line 138) | `= lib.mkForce false` (priority 50) | Stateless: no persistent path for swapfile |

Both server and headless-server roles currently **inherit the default `true`** and therefore create an 8 GiB swapfile at `/var/lib/swapfile`. This file will be on whatever filesystem holds `/var/lib/` — typically the root filesystem. On a ZFS-rooted server, this is a ZFS dataset.

### 1.4 What imports `zfs-server.nix`

Exactly two configuration files import `modules/zfs-server.nix`:
- `configuration-server.nix`
- `configuration-headless-server.nix`

No other role (desktop, htpc, stateless, vanilla) imports it. The module is declared server-only by design (see its header comment).

### 1.5 `modules/system-server.nix` — does not exist

A search of the repository confirms no file named `modules/system-server.nix` exists.

---

## 2. Problem Definition

### 2.1 ZFS + swap deadlock risk

ZFS's Adaptive Replacement Cache (ARC) is an in-kernel memory consumer that can grow to fill available RAM. When the kernel tries to reclaim memory to satisfy a page fault, it may attempt to write to the swap file. If the swap file is on a ZFS dataset, the write goes to ZFS — which itself is trying to reclaim ARC memory to service the write. This produces a kernel-level deadlock:

```
kernel memory reclaim
  → write to swap (on ZFS)
    → ZFS needs to free ARC
      → ZFS blocks waiting for memory reclaim
        ← deadlock
```

This is well-documented in the OpenZFS project and the NixOS ZFS wiki. The canonical recommendation is:

> **Never put swap on a ZFS pool.** Use ZRAM or a swap partition/file on a non-ZFS filesystem.

*Sources:*
1. [OpenZFS documentation — "Swap"](https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Memory%20Management.html) — explicitly warns against swapping on ZFS datasets.
2. [NixOS Wiki — ZFS](https://nixos.wiki/wiki/ZFS) — recommends `swapDevices = []` or ZRAM-only for ZFS hosts.
3. [NixOS Discourse — ZFS + swap deadlock thread](https://discourse.nixos.org/t/zfs-swap-deadlock/8123) — community confirmations of the bug in practice.
4. [Ubuntu ZFS documentation](https://ubuntu.com/tutorials/setup-zfs-storage-pool#1-overview) — notes that swap should be on a separate, non-ZFS partition.
5. [Arch Linux Wiki — ZFS#Swap](https://wiki.archlinux.org/title/ZFS#Swap_partition) — "Never use a ZFS zvol as a swap device; this can cause a deadlock."
6. NixOS module system reference — `lib.mkDefault` / `lib.mkOverride` priority semantics confirm that `lib.mkDefault false` (priority 1000) is safely overridden by any plain assignment (priority 100) in a host file.

### 2.2 Current project gap

- `modules/zfs-server.nix` enables ZFS kernel support, scrub, and trim — but does not declare any swap policy.
- Both server roles default to `vexos.swap.enable = true`, silently creating a swapfile that is very likely on a ZFS dataset.
- There is no documentation, assertion, or opt-in to acknowledge this risk.

---

## 3. Architecture Decision

### Option A — Add to `modules/zfs-server.nix`

**Rationale:** The reason swap is being disabled is ZFS — the presence of ZFS on the system is what makes a swapfile dangerous. `zfs-server.nix` is the exact module that enables ZFS. The policy is causally tied to ZFS, not to a general server-role policy.

**Consistency with Option B pattern:** No `lib.mkIf` guard is needed. The assignment is unconditional within the file. The file itself is only imported by the two roles that need it.

**Override path:** A host operator can override with `vexos.swap.enable = true` in their `hosts/<role>-<gpu>.nix` if they genuinely have a separate non-ZFS swap partition.

### Option B — New `modules/system-server.nix`

**Rationale:** Servers generally don't need hibernate or disk overflow swap beyond ZRAM; this would be a role-wide policy rather than a ZFS-specific policy.

**Problem:** This creates a new file that partially overlaps with `zfs-server.nix` semantics, adds an unnecessary import to both `configuration-*.nix` files, and separates a ZFS-motivated rule from the ZFS module — weakening documentation locality.

### Decision: **Option A — add to `modules/zfs-server.nix`**

This is semantically precise, requires no new files, no new imports, and follows the Option B architecture pattern (unconditional content in a file that is itself conditionally imported).

---

## 4. Implementation Steps

### Step 1 — Modify `modules/zfs-server.nix`

Add `vexos.swap.enable = lib.mkDefault false;` to the file. The correct position is **after** the `networking.hostId` assignment and **before** the `assertions` block, in a clearly commented section.

**Priority semantics:**
- `lib.mkDefault` = `lib.mkOverride 1000` — lowest priority among module values
- Plain assignment in a host file = priority 100 — overrides `lib.mkDefault`
- `lib.mkForce` (used by impermanence) = priority 50 — overrides everything

This means:
- Server hosts that import `zfs-server.nix` will get swap disabled by default ✓
- A host can override with `vexos.swap.enable = true;` in its `hosts/<role>-<gpu>.nix` ✓
- ZRAM swap is unaffected (unconditional in `system.nix`) ✓

### Step 2 — Update option description in `modules/system.nix`

The current description says *"Set to false on VM guests."* This is now incomplete since ZFS servers also set it false. Update the description to reflect the broader policy.

---

## 5. Code Snippets

### 5.1 `modules/zfs-server.nix` — add swap policy section

Insert this block **between** the `networking.hostId` assignment and the `assertions = [` list:

```nix
  # ── Swap policy: disable disk-backed swap on ZFS hosts ───────────────────
  # Writing a swapfile to a ZFS dataset risks a kernel deadlock: the kernel's
  # memory-reclaim path writes to swap (on ZFS), ZFS needs to shrink its ARC
  # to service the write, but ARC shrink itself blocks on memory reclaim.
  # See: https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Memory%20Management.html
  #
  # lib.mkDefault (priority 1000) is weaker than a plain assignment (priority 100),
  # so a host operator can override this by setting:
  #   vexos.swap.enable = true;   # in hosts/<role>-<gpu>.nix
  # only if they have a confirmed non-ZFS swap partition or file.
  #
  # ZRAM swap (configured unconditionally in modules/system.nix) is unaffected
  # and continues to provide fast in-RAM compressed swap on all server roles.
  vexos.swap.enable = lib.mkDefault false;
```

### 5.2 `modules/system.nix` — update option description (line 24–30)

Replace the existing description string:

```nix
      description = ''
        Enable an 8 GiB persistent swap file at /var/lib/swapfile.
        Provides true overflow capacity beyond RAM + ZRAM, and enables
        system hibernate support. Set to false on VM guests.
      '';
```

With:

```nix
      description = ''
        Enable an 8 GiB persistent swap file at /var/lib/swapfile.
        Provides true overflow capacity beyond RAM + ZRAM, and enables
        system hibernate support.
        Defaults to false on ZFS server roles (modules/zfs-server.nix) to
        avoid the ZFS+swap kernel deadlock; false on VM guests (modules/gpu/vm.nix)
        and stateless hosts (modules/impermanence.nix). All other roles default
        to true.
      '';
```

---

## 6. Complete Modified File Preview

### `modules/zfs-server.nix` (complete, after patch)

```nix
# modules/zfs-server.nix
# ZFS support for server roles — required for proxmox-nixos VM storage.
#
# Why this is a server-only addition:
#   • Loads the ZFS kernel module on every boot (overhead on roles that don't
#     need it, plus ZFS+nvidia-headless DKMS interactions can lengthen rebuilds).
#   • networking.hostId must be globally unique per machine; setting it on
#     desktop/htpc/stateless variants without ZFS adds noise.
#
# Per the Option B module pattern (see .github/copilot-instructions.md):
#   imported ONLY by configuration-server.nix and configuration-headless-server.nix.
{ config, lib, pkgs, ... }:
{
  # ── Kernel + userland ────────────────────────────────────────────────────
  boot.supportedFilesystems        = [ "zfs" ];
  boot.zfs.forceImportRoot         = false;
  boot.zfs.forceImportAll          = false;

  # ── Kernel pinning for ZFS compatibility ─────────────────────────────────
  # (existing comment block unchanged)
  boot.kernelPackages = lib.mkOverride 75 pkgs.linuxPackages;

  boot.zfs.extraPools              = [ ];
  services.zfs.autoScrub.enable    = true;
  services.zfs.autoScrub.interval  = "monthly";
  services.zfs.trim.enable         = true;
  services.zfs.trim.interval       = "weekly";

  # ── Userland tools needed by scripts/create-zfs-pool.sh ──────────────────
  environment.systemPackages = with pkgs; [
    zfs
    gptfdisk
    util-linux
    pciutils
  ];

  # ── networking.hostId ────────────────────────────────────────────────────
  # (existing comment block unchanged)
  networking.hostId = lib.mkDefault "00000000";

  # ── Swap policy: disable disk-backed swap on ZFS hosts ───────────────────
  # Writing a swapfile to a ZFS dataset risks a kernel deadlock: the kernel's
  # memory-reclaim path writes to swap (on ZFS), ZFS needs to shrink its ARC
  # to service the write, but ARC shrink itself blocks on memory reclaim.
  # See: https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Memory%20Management.html
  #
  # lib.mkDefault (priority 1000) is weaker than a plain assignment (priority 100),
  # so a host operator can override this by setting:
  #   vexos.swap.enable = true;   # in hosts/<role>-<gpu>.nix
  # only if they have a confirmed non-ZFS swap partition or file.
  #
  # ZRAM swap (configured unconditionally in modules/system.nix) is unaffected
  # and continues to provide fast in-RAM compressed swap on all server roles.
  vexos.swap.enable = lib.mkDefault false;

  assertions = [
    {
      assertion = config.networking.hostId != "00000000";
      message = ''
        ZFS requires a unique networking.hostId per machine.
        Set it in hosts/<role>-<gpu>.nix or hardware-configuration.nix:
          networking.hostId = "deadbeef";   # replace with real value
        Generate with: head -c 8 /etc/machine-id
      '';
    }
  ];
}
```

---

## 7. Files Modified

| File | Change |
|------|--------|
| `modules/zfs-server.nix` | Add `vexos.swap.enable = lib.mkDefault false;` with comment block |
| `modules/system.nix` | Update `vexos.swap.enable` option description to mention ZFS servers |

No new files. No new imports. No changes to `configuration-server.nix` or `configuration-headless-server.nix`.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| A server host genuinely needs disk swap (e.g. non-ZFS root with separate swap partition) | Low | `lib.mkDefault` is priority 1000; a plain `vexos.swap.enable = true;` in the host file overrides it at priority 100. No `lib.mkForce` needed. |
| Operator doesn't realise swap is now disabled | Very low | The comment block in `zfs-server.nix` documents the policy, and the updated option description in `system.nix` lists all cases. |
| ZRAM swap is somehow removed in the future, leaving servers with zero swap | Very low — separate config | ZRAM is unconditional in `system.nix`. If someone removes it, they will notice independently; the ZFS swap policy doesn't affect that path. |
| Priority conflict with another module setting `vexos.swap.enable` | None | Only `impermanence.nix` (`mkForce false`, priority 50) and `gpu/vm.nix` (priority 100) set this option. Both override `lib.mkDefault` (priority 1000) correctly. |

---

## 9. Validation Steps

After implementation, the following must pass:

```bash
# 1. Flake structure check
nix flake check

# 2. Server role (with GUI) — verify no swapDevices in closure
sudo nixos-rebuild dry-build --flake .#vexos-server-amd

# 3. Headless server role — verify no swapDevices in closure
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd

# 4. Desktop role — verify swapDevices still present (unaffected)
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd

# 5. VM role — verify no conflict with existing vexos.swap.enable = false
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
```

---

## 10. Summary

- **`vexos.swap.enable` already exists** in `modules/system.nix` at line 22 as a `lib.types.bool` option defaulting to `true`. No new option creation is needed.
- **Swap is suppressed** by the `lib.mkIf config.vexos.swap.enable { swapDevices = [...]; }` guard at line 106. ZRAM remains unconditional and unaffected.
- **The fix belongs in `modules/zfs-server.nix`** — the ZFS module is the causal reason for disabling swap, it is already imported by both server roles, and placing the policy here preserves documentation locality and Option B architecture compliance.
- **Implementation is minimal**: one `lib.mkDefault false` assignment + comment in `zfs-server.nix`, plus a description update in `system.nix`. No new files, no new imports, no `lib.mkIf` guards.
