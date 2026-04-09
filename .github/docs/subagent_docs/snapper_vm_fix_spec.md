# Specification: Disable Snapper & btrfs-scrub for VM Host

**Feature name:** `snapper_vm_fix`  
**Date:** 2026-04-09  
**Status:** Updated — reflects current code state after btrfs auto-detection refactor  

---

## 1. Current State Analysis

### 1.1 Module import chain

```
hosts/vm.nix
  └─ imports: configuration.nix
                └─ imports: modules/system.nix   ← snapper gated on vexos.btrfs.enable
  └─ imports: modules/gpu/vm.nix
```

`modules/system.nix` declares a custom **`vexos.btrfs.enable`** option with an auto-detection default:

```nix
vexos.btrfs.enable = lib.mkOption {
  type    = lib.types.bool;
  default = (config.fileSystems ? "/") && (config.fileSystems."/".fsType == "btrfs");
  ...
};
```

All snapper and btrfs configuration in `modules/system.nix` is wrapped in `lib.mkIf config.vexos.btrfs.enable { ... }`, which conditionally defines:

| Option | Value (when enabled) |
|---|---|
| `services.snapper.configs.root.SUBVOLUME` | `"/"` |
| `services.snapper.snapshotRootOnBoot` | `true` |
| `services.snapper.persistentTimer` | `true` |
| `services.btrfs.autoScrub.enable` | `true` |
| `services.btrfs.autoScrub.fileSystems` | `[ "/" ]` |
| `environment.systemPackages` | `btrfs-assistant`, `btrfs-progs` |
| `system.activationScripts.snapperSubvolume` | Creates `/.snapshots` btrfs subvolume |

**The auto-detection evaluates at Nix evaluation time** by reading `config.fileSystems."/".fsType` from the host's `hardware-configuration.nix`. If the VM's `hardware-configuration.nix` declares the root filesystem as `btrfs` (the NixOS 25.x graphical installer defaults to btrfs), this evaluates to `true` and the full snapper block is enabled.

### 1.2 Physical hosts (amd / nvidia / intel)

`hosts/amd.nix`, `hosts/nvidia.nix`, and `hosts/intel.nix` all import `configuration.nix` and run on real hardware provisioned with a btrfs root filesystem. The auto-detection fires correctly and snapper works on those hosts.

### 1.3 VM host filesystem and override state

The VM guest targets QEMU/KVM. The NixOS 25.x graphical installer defaults to btrfs for the root filesystem, so the VM's `hardware-configuration.nix` almost certainly declares `fsType = "btrfs"` — causing `vexos.btrfs.enable` to auto-detect as `true`.

However, `hosts/vm.nix` currently only sets:

```nix
vexos.swap.enable = false;   # disables swap file
```

There is **no** `vexos.btrfs.enable = false` override. This is the gap that causes the failure.

---

## 2. Problem Definition

### 2.1 Failing services

Immediately after `nixos-rebuild switch --flake .#vexos-desktop-vm`:

```
warning: the following units failed: snapper-boot.service

× snapper-boot.service - Take snapper snapshot of root on boot
     Active: failed (Result: exit-code) since Thu 2026-04-09 11:31:48 CDT; 4s ago
    Process: 21418 ExecStart=.../snapper-0.13.0/bin/snapper --config root create \
             --cleanup-algorithm number --description boot (code=exited, status=1/FAILURE)

Apr 09 11:31:48 vexos-desktop snapper[21418]: Creating snapshot failed.
```

`nixos-rebuild switch` returned **exit code 4** (activated units failed).

### 2.2 Root cause — auto-detection gives false positive; btrfs layout not snapper-compatible

The `vexos.btrfs.enable` auto-detection evaluates `config.fileSystems."/".fsType` from the VM's `hardware-configuration.nix`. Because the NixOS installer formats with btrfs by default, this evaluates to `true` and snapper is enabled.

At runtime, `snapper --config root create` fails because the VM's btrfs installation does not have a snapper-compatible subvolume layout. Common causes on NixOS installer-created btrfs systems:

| Root cause | Description |
|---|---|
| **No named root subvolume** | The NixOS installer may mount `/` as the btrfs top-level (**subvol ID 5**), not a named subvolume like `@`. Snapper requires the root to be a named subvolume. |
| **`/.snapshots` missing or wrong type** | The `system.activationScripts.snapperSubvolume` activation script attempts to create `/.snapshots` as a btrfs subvolume, but if `/` is the top-level btrfs volume rather than a subvolume, the snapshot creation still fails. |
| **Auto-detection is a false positive for VMs** | Even when the filesystem type is btrfs, the VM btrfs layout may not support snapper. The auto-detection check (`fsType == "btrfs"`) is necessary but not sufficient. |

Snapper requires BTRFS with a proper subvolume layout. From the nixpkgs `snapper.nix` module source:

> `SUBVOLUME` — "Path of the subvolume or mount point. This path is a subvolume
> and **has to contain a subvolume named `.snapshots`**."

### 2.3 How the failing units are generated

The nixpkgs snapper module generates these systemd units whenever
`services.snapper.configs` is non-empty:

| Unit | Condition |
|---|---|
| `snapper-timeline.service` | configs ≠ `{}` |
| `snapper-cleanup.service` | configs ≠ `{}` |
| `snapper-boot.service` | `cfg.snapshotRootOnBoot == true` |

With the current shared `modules/system.nix` config, all three are generated for
the VM, and `snapper-boot.service` + `snapper-timeline.service` fail on first execution.

### 2.4 Secondary issue — btrfs-scrub on non-BTRFS filesystem

`services.btrfs.autoScrub` is also enabled globally. btrfs scrub on a non-BTRFS
device produces an error (`ERROR: not a btrfs filesystem`). The scrub service
runs monthly, so it does not fail immediately at boot, but it will generate
errors on each execution and may accumulate in the journal.

---

## 3. Research Findings

### Sources consulted

1. **nixpkgs `nixos/modules/services/misc/snapper.nix`** (GitHub master)
   — Confirms `SUBVOLUME` requires a `.snapshots` subvolume; `FSTYPE` is an enum
   of `"btrfs"` | `"bcachefs"`; `snapper-boot.service` is gated on
   `cfg.snapshotRootOnBoot`; the entire services block activates when
   `cfg.configs ≠ {}`.

2. **NixOS options search** (`search.nixos.org/options?query=services.snapper`)
   — Lists all 18 snapper options. Confirms `services.snapper.configs` (attrset
   of submodule), `services.snapper.snapshotRootOnBoot` (bool, default false),
   `services.snapper.persistentTimer` (bool).

3. **NixOS Manual — Modularity section** (`nixos.org/manual/nixos/stable/#sec-option-types`)
   — Documents `lib.mkForce` = `lib.mkOverride 50`, which discards all
   competing definitions with priority > 50 (normal module definitions use
   priority 100). This is the correct tool for overriding options set in a
   shared module from a host-specific module.

4. **NixOS Manual — Setting Priorities section**
   — "A module can override the definitions of an option in other modules by
   setting an override priority. All option definitions that do not have the
   lowest priority value are discarded. `mkForce` is equal to `mkOverride 50`."

5. **NixOS Wiki — NixOS Modules** (`nixos.wiki/wiki/NixOS_modules`)
   — Explains module merge semantics: attrset options merge by default;
   `lib.mkForce` on an attrset completely replaces all lower-priority definitions.

6. **snapper upstream documentation / openSUSE snapper man page**
   — Confirms `.snapshots` must be a BTRFS subvolume (not just a directory).
   Creating it as a plain directory causes `IO Error (open failed)`.

7. **NixOS Manual — ISO/image override pattern**
   — The ISO base image uses `mkImageMediaOverride = mkOverride 60` to enforce
   config for image-specific needs, yielding to `mkForce`. This confirms the
   standard pattern: host-level overrides use `lib.mkForce` to win over shared
   module defaults.

### Key technical facts confirmed

- `services.snapper.configs` default is `{}` (empty). Any non-empty value
  activates the snapper systemd units.
- Setting `services.snapper.configs = lib.mkForce {};` in `hosts/vm.nix` will
  clear all configs, preventing the generation of `snapper-timeline.service`,
  `snapper-cleanup.service`, and deactivating the snapper DBus daemon registration.
- `snapper-boot.service` is additionally gated on `cfg.snapshotRootOnBoot`.
  Setting `services.snapper.snapshotRootOnBoot = lib.mkForce false;` prevents
  the service from being generated at all.
- `services.snapper.persistentTimer` only affects the `Persistent=` key in the
  `snapper-timeline.timer`. With empty configs, the timer exists but does nothing;
  setting it false is still good hygiene to avoid the `Persistent` flag on a no-op timer.
- `services.btrfs.autoScrub.enable` requires a BTRFS filesystem. Setting it
  `false` is required for the VM where the filesystem is ext4.
- `btrfs-assistant` and `btrfs-progs` are passive packages in
  `environment.systemPackages`. They produce no service failures on a non-BTRFS
  system. **They should remain in the VM environment** to keep the package
  environment consistent and in case the user opts to use a BTRFS-backed VM.

---

## 4. Proposed Solution

### 4.1 Approach: use the existing `vexos.btrfs.enable` option (preferred)

`modules/system.nix` already declares a `vexos.btrfs.enable` option specifically
for this purpose. Its description states:

> "Can be overridden explicitly for edge cases."

The VM is exactly this edge case. Setting `vexos.btrfs.enable = false` in
`hosts/vm.nix` deactivates the entire `lib.mkIf config.vexos.btrfs.enable { ... }`
block in `modules/system.nix`, cleanly disabling:

- `services.snapper.configs`
- `services.snapper.snapshotRootOnBoot`
- `services.snapper.persistentTimer`
- `services.btrfs.autoScrub`
- `system.activationScripts.snapperSubvolume`
- `btrfs-assistant` and `btrfs-progs` from `environment.systemPackages`

This approach:

- **Does not modify** `modules/system.nix`, `configuration.nix`, or any other host file.
- Uses the **intended public API** of the module rather than bypassing it with raw `mkForce` overrides.
- Keeps snapper fully enabled for `amd`, `nvidia`, and `intel` hosts (auto-detection continues to work there).
- Is consistent with the existing `vexos.swap.enable = false` pattern already in `hosts/vm.nix`.
- Does not require adding `lib` to the function signature.

### 4.2 Exact change

**File: `hosts/vm.nix`** — add one line.

#### Before

```nix
{ inputs, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = "vexos-desktop-vm";

  # VMs rely on hypervisor memory management — no disk swap file needed.
  vexos.swap.enable = false;

  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
  system.nixos.distroName = "VexOS Desktop VM";
}
```

#### After

```nix
{ inputs, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = "vexos-desktop-vm";

  # VMs rely on hypervisor memory management — no disk swap file needed.
  vexos.swap.enable = false;

  # VMs do not need in-guest btrfs snapshots — managed by the hypervisor instead.
  # Explicitly disabled to prevent snapper-boot.service and snapper-timeline.service
  # from failing when the VM's btrfs layout doesn't support snapper operation.
  # The auto-detection (fileSystems."/".fsType == "btrfs") fires as true on NixOS
  # installer-created VMs, but snapper still fails at runtime due to missing subvolume layout.
  vexos.btrfs.enable = false;

  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
  system.nixos.distroName = "VexOS Desktop VM";
}
```

### 4.3 Alternative approach: raw `lib.mkForce` overrides (not preferred)

If the `vexos.btrfs.enable` option approach cannot be used for any reason, the
individual service options can be overridden directly:

```nix
{ inputs, lib, ... }:
{
  # (lib must be added to function args for this approach)
  services.snapper.configs            = lib.mkForce {};
  services.snapper.snapshotRootOnBoot = lib.mkForce false;
  services.snapper.persistentTimer    = lib.mkForce false;
  services.btrfs.autoScrub.enable     = lib.mkForce false;
}
```

This is not preferred because:
- It bypasses the module API.
- It does not disable `system.activationScripts.snapperSubvolume` (the activation
  script that attempts `btrfs subvolume create /.snapshots`).
- It requires adding `lib` to the function signature.
- It leaves `btrfs-assistant` and `btrfs-progs` in the VM package set unnecessarily.

### 4.4 Expected result after fix

| Unit / item | Before fix | After fix |
|---|---|---|
| `snapper-boot.service` | ✗ Fails at runtime | Not generated (`vexos.btrfs.enable = false` → `mkIf false`) |
| `snapper-timeline.service` | Generated (would fail) | Not generated |
| `snapper-cleanup.service` | Generated | Not generated |
| `snapper-timeline.timer` | Generated | Not generated |
| `btrfs-scrub@-.service` | Will fail monthly | Not generated |
| `activationScripts.snapperSubvolume` | Runs (may fail or succeed) | Not generated |
| `btrfs-assistant`, `btrfs-progs` | In VM package set | Removed from VM package set |

---

## 5. Files to Modify

| File | Change |
|---|---|
| `hosts/vm.nix` | Add `vexos.btrfs.enable = false;` with explanatory comment (no signature change needed) |

No other files require modification.

---

## 6. Files NOT to Modify

| File | Reason |
|---|---|
| `modules/system.nix` | Must remain unchanged; BTRFS hosts depend on the current configuration |
| `configuration.nix` | Shared entry point; must not be host-specific |
| `hosts/amd.nix` | BTRFS hardware — snapper must remain active |
| `hosts/nvidia.nix` | BTRFS hardware — snapper must remain active |
| `hosts/intel.nix` | BTRFS hardware — snapper must remain active |

---

## 7. Packages Decision

With `vexos.btrfs.enable = false`, the entire btrfs `mkIf` block is suppressed,
which **removes** `btrfs-assistant` and `btrfs-progs` from the VM's
`environment.systemPackages`. This is correct:

- Neither tool is useful in a VM guest where btrfs snapshots are disabled.
- If the user ever provisions a btrfs-backed VM and re-enables `vexos.btrfs.enable`,
  the packages will return automatically.
- Removing them reduces the VM closure size slightly.

---

## 8. Implementation Steps

1. Open `hosts/vm.nix`.
2. After the `vexos.swap.enable = false;` line, add:
   ```nix
   # VMs do not need in-guest btrfs snapshots — managed by the hypervisor instead.
   # Explicitly disabled to prevent snapper-boot.service and snapper-timeline.service
   # from failing when the VM's btrfs layout doesn't support snapper operation.
   vexos.btrfs.enable = false;
   ```
3. Run `nix flake check` in the repository root to validate flake structure.
4. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` to verify the
   VM system closure builds without errors.
5. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` to confirm
   snapper is still fully configured on the AMD host.
6. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` (same check).

---

## 9. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Physical hosts stop getting snapshots | None — change is scoped to `hosts/vm.nix` | amd/nvidia/intel do not import `hosts/vm.nix`; their `vexos.btrfs.enable` auto-detection is unaffected |
| `vexos.btrfs.enable = false` is overridden by something higher-priority | Very low | No other module in this repo sets `vexos.btrfs.enable`; the plain `false` (priority 100) is definitive |
| VM user later provisions a btrfs root and wants snapshots | Low | Remove `vexos.btrfs.enable = false` from `hosts/vm.nix` and create `/.snapshots` subvolume per snapper docs |
| `nix flake check` fails for an unrelated reason | None expected | Run preflight before and after to confirm; the diff is one line |

---

## 10. Acceptance Criteria

- `nix flake check` passes with no errors or warnings related to this change.
- `nixos-rebuild dry-build --flake .#vexos-desktop-vm` completes successfully.
- `nixos-rebuild dry-build --flake .#vexos-desktop-amd` completes successfully
  with `services.snapper.configs.root` intact.
- After switching, `systemctl status snapper-boot.service` and
  `systemctl status snapper-timeline.service` show the units as **inactive** or
  non-existent (not failed) on the VM host.
- No new systemd unit failures are introduced on any host target.

---

## Appendix A — NixOS module priority reference

| Function | Priority | Meaning |
|---|---|---|
| `lib.mkDefault` | 1000 | Soft default; any explicit definition wins |
| _(plain definition)_ | 100 | Normal user/module definition |
| `lib.mkForce` | 50 | Overrides all normal definitions |

Setting `vexos.btrfs.enable = false` in `hosts/vm.nix` is a plain definition
(priority 100). The `default = ...` expression in `modules/system.nix` produces
a `lib.mkDefault` (priority 1000). The plain `false` wins over the default,
which is the correct and expected NixOS behavior for module option overrides.

No `lib.mkForce` is needed because there is no competing non-default binding
for `vexos.btrfs.enable` elsewhere in the module tree.

---

## Appendix B — How `vexos.btrfs.enable = false` suppresses snapper units

With `vexos.btrfs.enable = false`, the `lib.mkIf config.vexos.btrfs.enable { ... }`
block in `modules/system.nix` becomes `lib.mkIf false { ... }` — the entire
block is a no-op at evaluation time. None of its attributes are merged into the
final system configuration, so `services.snapper.configs` remains `{}` (the
NixOS snapper module default), and the following units are never generated:

- `snapper-boot.service`
- `snapper-timeline.service` / `snapper-timeline.timer`
- `snapper-cleanup.service` / `snapper-cleanup.timer`
- `snapperd.service`

The `system.activationScripts.snapperSubvolume` name is also never defined,
so no activation script attempts `btrfs subvolume create /.snapshots`.
