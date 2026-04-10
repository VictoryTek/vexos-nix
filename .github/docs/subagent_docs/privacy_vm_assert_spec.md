# Spec: Fix `vexos-privacy-vm` impermanence assertion failure

**Feature name:** `privacy_vm_assert`  
**Date:** 2026-04-10  
**Files to modify:** `flake.nix`, `template/etc-nixos-flake.nix`

---

## 1. Current State Analysis

### 1.1 Two distinct execution paths for privacy builds

The repo exposes privacy roles in two ways:

| Path | Who uses it | How it works |
|------|-------------|--------------|
| **Direct `nixosConfigurations`** in `flake.nix` | Developers running `nixos-rebuild --flake .#vexos-privacy-vm` from the repo checkout | `commonModules ++ [ ./hosts/privacy-vm.nix impermanence.nixosModules.impermanence disko.nixosModules.disko ]` |
| **`nixosModules` wrapper** consumed by `/etc/nixos/flake.nix` | End-users following the thin-wrapper setup from `template/etc-nixos-flake.nix` | `privacyBase` module + `gpuVm` module |

### 1.2 What `hosts/privacy-vm.nix` does

```nix
imports = [
  ../configuration-privacy.nix   # sets vexos.impermanence.enable = true
  ../modules/gpu/vm.nix
  ../modules/privacy-disk.nix    # ← sets fileSystems."/persistent".neededForBoot = true
];

vexos.privacy.disk = {
  enable     = true;
  device     = "/dev/vda";
  enableLuks = false;
};
```

`modules/privacy-disk.nix` is imported here. When `vexos.privacy.disk.enable = true`, it generates disko disk config **and** sets:

```nix
fileSystems."/persistent".neededForBoot = lib.mkForce true;
fileSystems."/nix".neededForBoot        = lib.mkForce true;
```

### 1.3 What `nixosModules.privacyBase` does (current state)

```nix
privacyBase = { ... }: {
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    disko.nixosModules.disko
    ./configuration-privacy.nix    # sets vexos.impermanence.enable = true
    # ❌ ./modules/privacy-disk.nix is NOT imported here
  ];
  ...
};
```

`./modules/privacy-disk.nix` is **never imported** in this path.

### 1.4 What `nixosModules.gpuVm` does (current state)

```nix
gpuVm = { ... }: {
  imports = [ ./modules/gpu/vm.nix ];
  # ❌ No disk configuration here
};
```

No disk configuration at all.

### 1.5 What `template/etc-nixos-flake.nix` does

```nix
mkPrivacyVariant = _mkVariantWith vexos-nix.nixosModules.privacyBase;

vexos-privacy-vm = mkPrivacyVariant "vexos-privacy-vm" vexos-nix.nixosModules.gpuVm;
```

The wrapper system builds: `privacyBase + gpuVm + bootloaderModule + hardware-configuration.nix`.

Neither `privacyBase` nor `gpuVm` imports `privacy-disk.nix`, so `fileSystems."/persistent"` is never declared, and `neededForBoot` is never set to `true`.

---

## 2. Problem Definition

The assertion in `modules/impermanence.nix` fires:

```nix
assertions = [
  {
    assertion =
      (config.fileSystems ? "${cfg.persistentPath}") &&
      (config.fileSystems."${cfg.persistentPath}".neededForBoot or false);
    message = ''
      vexos.impermanence.enable = true requires
      fileSystems."${cfg.persistentPath}" to be declared with neededForBoot = true.
      This is normally satisfied automatically by modules/privacy-disk.nix.
      Check that privacy-disk.nix is imported in your privacy host file.
    '';
  }
  ...
];
```

**Trigger sequence when using the wrapper:**

1. `privacyBase` imports `configuration-privacy.nix`
2. `configuration-privacy.nix` sets `vexos.impermanence.enable = true`
3. `modules/impermanence.nix` (also imported by `privacyBase` via `impermanence.nixosModules.impermanence`) evaluates the assertion
4. `fileSystems."/persistent"` does not exist (no `privacy-disk.nix` in the module graph)
5. **Assertion fails → build aborts**

The same failure would occur for all four wrapper-path privacy variants (`vexos-privacy-amd`, `-nvidia`, `-intel`, `-vm`) because none of them have `privacy-disk.nix` in the module graph. The VM variant is what the user hit first.

---

## 3. Proposed Solution Architecture

Three coordinated changes ensure the wrapper path is fixed without breaking the direct `nixosConfigurations` path.

### Design principle

- `privacyBase` becomes fully self-contained: it imports `privacy-disk.nix` and sets safe bare-metal defaults.
- A new `privacyGpuVm` module bundles GPU/VM drivers + VM-specific disk overrides, replacing the generic `gpuVm` for privacy-VM builds.
- The direct `nixosConfigurations` (repo builds) are unaffected: they still use `hosts/privacy-*.nix` which imports `privacy-disk.nix` directly; the NixOS module system deduplicates double-imports cleanly.

### Why deduplication is safe

NixOS module imports are idempotent when the same file path is listed multiple times — the evaluator deduplicates them. `privacy-disk.nix` defines options declaratively; importing it twice does not cause option conflicts. The `vexos.privacy.disk.*` option values set by `hosts/privacy-*.nix` use plain assignment, while `privacyBase` will use `lib.mkDefault`, so host values always win.

---

## 4. Implementation Steps

### Change 1 — `flake.nix`: add `privacy-disk.nix` to `privacyBase`

**Location:** inside the `nixosModules.privacyBase` attrset, approximately line 276 onwards.

**Before:**
```nix
privacyBase = { ... }: {
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    disko.nixosModules.disko
    ./configuration-privacy.nix
  ];
```

**After:**
```nix
privacyBase = { lib, ... }: {
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    disko.nixosModules.disko
    ./configuration-privacy.nix
    ./modules/privacy-disk.nix
  ];
```

Then, in the body of `privacyBase` (after the `home-manager` config block and overlays), add the disk defaults:

```nix
  # Enable disk layout with bare-metal defaults; VM variants override these
  # via privacyGpuVm (device = "/dev/vda", enableLuks = false).
  vexos.privacy.disk.enable    = true;
  vexos.privacy.disk.device    = lib.mkDefault "/dev/nvme0n1";
  vexos.privacy.disk.enableLuks = lib.mkDefault true;
```

`lib.mkDefault` (priority 1000) is lower than a plain assignment (priority 1500), so any host-specific override in `hardware-configuration.nix` or a custom module will always win. The existing `hosts/privacy-*.nix` files set plain values that override `mkDefault` correctly.

### Change 2 — `flake.nix`: add `privacyGpuVm` to `nixosModules`

**Location:** inside the `nixosModules` attrset, after the existing `gpuVm` entry (approximately line 310).

Add the following new module:

```nix
# Privacy-role VM variant: VM GPU drivers + VM-appropriate disk settings.
# Overrides the bare-metal defaults set by privacyBase with mkForce to
# select the virtio disk (/dev/vda) and disable LUKS (no hw encryption needed).
privacyGpuVm = { lib, ... }: {
  imports = [ ./modules/gpu/vm.nix ];
  vexos.privacy.disk.device    = lib.mkForce "/dev/vda";
  vexos.privacy.disk.enableLuks = lib.mkForce false;
};
```

`lib.mkForce` (priority 1500+50 = override) ensures these values beat any `mkDefault` from `privacyBase`, even if future changes raise priorities.

### Change 3 — `template/etc-nixos-flake.nix`: use `privacyGpuVm`

**Location:** the `vexos-privacy-vm` line inside `nixosConfigurations`, approximately line 128.

**Before:**
```nix
vexos-privacy-vm = mkPrivacyVariant "vexos-privacy-vm" vexos-nix.nixosModules.gpuVm;
```

**After:**
```nix
vexos-privacy-vm = mkPrivacyVariant "vexos-privacy-vm" vexos-nix.nixosModules.privacyGpuVm;
```

This is the only line change required in the template.

---

## 5. Risks and Mitigations

### 5.1 Existing wrapper users with `/etc/nixos/flake.nix` already downloaded

**Risk:** Users who already downloaded `template/etc-nixos-flake.nix` before this fix will have the old version referencing `gpuVm`. Their `vexos-privacy-vm` build will continue failing until they update their local `/etc/nixos/flake.nix`.

**Mitigation:** The fix is backward-compatible in the sense that updating `/etc/nixos/flake.nix` requires only a one-line change (`gpuVm` → `privacyGpuVm`). Document this in the `README.md` upgrade notes. Users running `just switch` or `nixos-rebuild --flake /etc/nixos#vexos-privacy-vm` will receive an error that is now easier to resolve because `privacyGpuVm` simply won't exist in the old template — the error will be a missing attribute rather than the opaque assertion message.

### 5.2 Direct `nixosConfigurations` double-import of `privacy-disk.nix`

**Risk:** After Change 1, both `privacyBase` and `hosts/privacy-*.nix` import `privacy-disk.nix`. The NixOS module evaluator could theoretically produce duplicate option definitions.

**Mitigation:** The NixOS module system deduplicates imports by file path — identical paths are only evaluated once. This is standard, documented NixOS behaviour. No conflict will occur. Verified by examining `hosts/privacy-vm.nix`: it sets `vexos.privacy.disk.device = "/dev/vda"` as a plain expression (priority 1500), which overrides `privacyBase`'s `lib.mkDefault "/dev/nvme0n1"` (priority 1000) cleanly.

### 5.3 Non-VM bare-metal wrapper variants now have `privacy-disk.nix` active by default

**Risk:** `vexos-privacy-amd`, `-nvidia`, `-intel` in the wrapper now get `privacy-disk.nix` with `device = "/dev/nvme0n1"` and `enableLuks = true` by default. A user whose disk is `/dev/sda` would partition the wrong device on first install.

**Mitigation:** This is the same situation as before — the `privacy-setup.sh` script already prompts for device selection. The `lib.mkDefault` value is overridable, and the `README.md` already documents that users must verify their disk with `lsblk` before running the setup script. No regression.

### 5.4 `privacyBase` now requires `lib` in its module argument

**Risk:** `privacyBase` currently uses `{ ... }` (no named args). Changing to `{ lib, ... }` is required for `lib.mkDefault`.

**Mitigation:** This is a trivial change — `lib` is always available in NixOS modules. No downstream breakage.

---

## 6. Files to Modify

| File | Change |
|------|--------|
| `flake.nix` | Change 1 + Change 2 |
| `template/etc-nixos-flake.nix` | Change 3 |

No other files require modification. `modules/privacy-disk.nix`, `modules/impermanence.nix`, `configuration-privacy.nix`, and all `hosts/*.nix` files are unchanged.

---

## 7. Verification Checklist

After implementation, the following must pass:

- [ ] `nix flake check` — validates all `nixosConfigurations` and `nixosModules` outputs
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-privacy-vm` — must not produce the assertion failure
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-privacy-amd` — must still succeed (no regression)
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-privacy-nvidia` — must still succeed
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-privacy-intel` — must still succeed
- [ ] Manual inspection: `privacyGpuVm` module is listed in `nix flake show` output under `nixosModules`
- [ ] `hardware-configuration.nix` is NOT committed to the repository (existing constraint)
- [ ] `system.stateVersion` in `configuration-privacy.nix` is unchanged at `"25.11"`
