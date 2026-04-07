# Specification: Disable Snapper & btrfs-scrub for VM Host

**Feature name:** `snapper_vm_fix`  
**Date:** 2026-04-06  
**Status:** Draft  

---

## 1. Current State Analysis

### 1.1 Module import chain

```
hosts/vm.nix
  └─ imports: configuration.nix
                └─ imports: modules/system.nix   ← snapper enabled here
  └─ imports: modules/gpu/vm.nix
```

`modules/system.nix` unconditionally defines:

| Option | Value |
|---|---|
| `services.snapper.configs.root.SUBVOLUME` | `"/"` |
| `services.snapper.snapshotRootOnBoot` | `true` |
| `services.snapper.persistentTimer` | `true` |
| `services.btrfs.autoScrub.enable` | `true` |
| `services.btrfs.autoScrub.fileSystems` | `[ "/" ]` |
| `environment.systemPackages` | `btrfs-assistant`, `btrfs-progs` |

Because `hosts/vm.nix` imports `configuration.nix`, which imports `modules/system.nix`, the VM host receives the full snapper and btrfs-scrub configuration with no override.

### 1.2 Physical hosts (amd / nvidia / intel)

`hosts/amd.nix`, `hosts/nvidia.nix`, and `hosts/intel.nix` all import `configuration.nix` and run on real hardware provisioned with a BTRFS root filesystem that has a `/.snapshots` subvolume. Snapper works correctly there.

### 1.3 VM host filesystem

The VM guest targets QEMU/KVM. Its root device is a virtio block device formatted as **ext4** (the default for NixOS VM images). Even if deliberately formatted as BTRFS, the `/.snapshots` subvolume would never be created automatically; it must be created manually before first use.

---

## 2. Problem Definition

### 2.1 Failing services

Immediately after `nixos-rebuild switch --flake /etc/nixos#vexos-desktop-vm`:

```
× snapper-boot.service
IO Error (open failed path://.snapshots errno:2 (No such file or directory))

× snapper-timeline.service
IO Error (open failed path://.snapshots errno:2 (No such file or directory))
```

### 2.2 Root cause — filesystem incompatibility

**Snapper requires BTRFS.** From the nixpkgs `snapper.nix` module source
(nixpkgs `nixos/modules/services/misc/snapper.nix`):

> `SUBVOLUME` — "Path of the subvolume or mount point. This path is a subvolume
> and **has to contain a subvolume named `.snapshots`**."

The `FSTYPE` option accepts only `"btrfs"` or `"bcachefs"` (enum type). On a
non-BTRFS filesystem, snapper cannot open `/.snapshots` (errno 2 = ENOENT) and
all snapper systemd units fail.

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

### 4.1 Approach: host-level overrides in `hosts/vm.nix`

The lightest-touch, minimally invasive fix is to add `lib.mkForce` overrides
directly in `hosts/vm.nix`. This approach:

- **Does not modify** `modules/system.nix`, `configuration.nix`, or any other
  host file.
- Keeps snapper fully enabled for `amd`, `nvidia`, and `intel` hosts.
- Follows the standard NixOS pattern for host-specific overrides of shared
  module settings.
- Is consistent with how the NixOS ISO image overrides conflicting options
  (`mkOverride 60` / `mkForce`).

An alternative — adding a `btrfsSupport` option to `modules/system.nix` — is
more architecturally clean but is out of scope for a targeted bug fix. That
refactor can be done in a follow-up.

### 4.2 Exact changes

**File: `hosts/vm.nix`** — add a snapper/btrfs override block.

The `lib` argument must be added to the module function signature.

#### Before

```nix
{ inputs, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = "vexos-desktop-vm";

  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
}
```

#### After

```nix
{ inputs, lib, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = "vexos-desktop-vm";

  # ---------- Disable snapper (requires BTRFS + /.snapshots subvolume) ----------
  # The VM guest uses an ext4 root; snapper-boot and snapper-timeline would fail
  # with "IO Error (open failed path://.snapshots errno:2)".
  services.snapper.configs = lib.mkForce {};
  services.snapper.snapshotRootOnBoot = lib.mkForce false;
  services.snapper.persistentTimer = lib.mkForce false;

  # ---------- Disable btrfs auto-scrub (requires BTRFS filesystem) ----------
  services.btrfs.autoScrub.enable = lib.mkForce false;

  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
}
```

### 4.3 Why each override uses `lib.mkForce`

| Option | Type | Why mkForce is required |
|---|---|---|
| `services.snapper.configs` | `attrsOf submodule` | Merges by default; `mkForce {}` discards the `root` config set in `system.nix` (priority 100) |
| `services.snapper.snapshotRootOnBoot` | `bool` | Same option set to `true` in `system.nix`; competing bool definitions conflict — `mkForce false` wins |
| `services.snapper.persistentTimer` | `bool` | Same as above |
| `services.btrfs.autoScrub.enable` | `bool` | Same as above |

### 4.4 Expected result after fix

| Unit | Before fix | After fix |
|---|---|---|
| `snapper-boot.service` | ✗ Fails (errno 2) | Not generated (configs empty + snapshotRootOnBoot false) |
| `snapper-timeline.service` | ✗ Fails (errno 2) | Not generated (configs empty) |
| `snapper-cleanup.service` | ✓ or silent | Not generated (configs empty) |
| `snapper-timeline.timer` | Generated | Not generated (configs empty) |
| `btrfs-scrub@-.service` | Will fail monthly | Not generated |

---

## 5. Files to Modify

| File | Change |
|---|---|
| `hosts/vm.nix` | Add `lib` to function args; add 4 `lib.mkForce` overrides |

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

`btrfs-assistant` and `btrfs-progs` remain in the VM environment.

**Rationale:**
- They are GUI/CLI tools with no associated services. Their presence does not
  cause any systemd unit failures.
- A user may choose to provision a BTRFS-backed VM in the future, at which point
  the tools are already available.
- Removing them would require a separate `lib.mkForce` on
  `environment.systemPackages` which produces an list override, discarding the
  `inputs.up` package added by vm.nix itself unless explicitly re-included.
  The complexity is not justified for tools with zero runtime impact.

---

## 8. Implementation Steps

1. Open `hosts/vm.nix`.
2. Change `{ inputs, ... }:` to `{ inputs, lib, ... }:`.
3. After the `networking.hostName` line, add the four `lib.mkForce` overrides
   as shown in Section 4.2.
4. Run `nix flake check` in the repository root to validate flake structure.
5. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` to verify the
   VM system closure builds without errors.
6. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` to confirm
   snapper is still fully configured on the AMD host.
7. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` (same check).

---

## 9. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `lib.mkForce {}` on `services.snapper.configs` breaks amd/nvidia/intel | None — `mkForce {}` only applies in `hosts/vm.nix` which only the VM target imports | No action needed; the override is scoped to the module evaluation of the VM host only |
| `lib.mkForce false` on a bool conflicts with future module adding `lib.mkForce true` | Low | The priority of `mkForce` (50) beats normal definitions (100) but can be beaten by another `mkForce` (also 50) if defined later in the same module evaluation; unlikely in this codebase |
| VM user later provisions a BTRFS root and wants snapshots | Low | Remove the overrides from `hosts/vm.nix` and create the `/.snapshots` subvolume manually per the snapper setup docs |
| `nix flake check` fails for a reason unrelated to this change | None | Run `nix flake check` before and confirm it passes; the diff is small and isolated |
| `services.btrfs.autoScrub.fileSystems` being defined while `enable = false` | None — the enable guard is respected by the NixOS btrfs module | No action needed |

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

Setting `lib.mkForce false` in `hosts/vm.nix` (priority 50) defeats the
`true` definition in `modules/system.nix` (priority 100). ✓

---

## Appendix B — snapper-boot systemd unit (from nixpkgs source)

```nix
systemd.services.snapper-boot = lib.mkIf cfg.snapshotRootOnBoot {
  description = "Take snapper snapshot of root on boot";
  serviceConfig.ExecStart = "${pkgs.snapper}/bin/snapper --config root
    create --cleanup-algorithm number --description boot";
  serviceConfig.Type = "oneshot";
  requires = [ "local-fs.target" ];
  wantedBy = [ "multi-user.target" ];
  unitConfig.ConditionPathExists = "/etc/snapper/configs/root";
};
```

With `services.snapper.configs = lib.mkForce {}`, `/etc/snapper/configs/root`
is never written, so even if `snapshotRootOnBoot` were not forced false, the
`ConditionPathExists` check would prevent execution. Setting both overrides
provides defense-in-depth.
