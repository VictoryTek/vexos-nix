# Spec — Fix VirtualBox Guest Additions build on VM variants

## Current state analysis

`modules/gpu/vm.nix` and `modules/gpu/vanilla-vm.nix` enable
`virtualisation.virtualbox.guest`. Commit `f05e4f2` removed their
`boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;` pin and added
`virtualisation.virtualbox.guest.use3rdPartyModules = false`, asserting that the
in-tree drivers would remove the out-of-tree build and that the pin's "only
purpose was working around this exact failure". Both assertions are false.

### Why `use3rdPartyModules = false` cannot work

In `nixpkgs/nixos/modules/virtualisation/virtualbox-guest.nix` the option gates
exactly one line:

```nix
boot.extraModulePackages = lib.mkIf cfg.use3rdPartyModules [ kernel.virtualboxGuestAdditions ];
```

The same package is referenced unconditionally by `environment.systemPackages`,
`systemd.services.virtualbox`, every `VBoxClient` user service, and — via
`cfg.vboxsf` (default `true`) — `boot.supportedFilesystems = [ "vboxsf" ]`, which
pulls `mount.vboxsf` out of that derivation. The option controls which modules are
*loaded*, never whether the package is *built*.

### Why the kernel pin cannot work either

`virtualboxGuestAdditions` 7.2.14 builds `vboxvideo`, whose `vbox_fb.c:336` calls
`drm_fb_helper_alloc_info()`. Verified by grepping each kernel's real
`include/drm/drm_fb_helper.h` (and the whole `include/` tree) in the repo's pinned
nixpkgs:

| Kernel | `drm_fb_helper_alloc_info` |
|---|---|
| 6.6.151 | absent |
| 6.12.103 (LTS pin) | absent |
| 6.18.44 (`pkgs.linuxPackages`) | absent |
| 7.1.8 (`linuxPackages_latest`) | absent |

Confirmed empirically: building `linuxPackages_6_12.virtualboxGuestAdditions`
fails with the identical `-Wint-conversion` error as 6.18.44. **No packaged kernel
can build this package as-is.** `meta.broken = false`, so nothing warns.

### Actual root cause

The vendored `src/vboxguest-7.2.14_NixOS/Makefile` already excludes `vboxvideo`
on new kernels:

```make
KERN_MAJ = $(shell uname -r | cut -d . -f1)
all:     vboxguest vboxsf         $(if $(shell [ "$(KERN_MAJ)" -lt 7 ] && echo y),vboxvideo,)
install: install-vboxguest install-vboxsf $(if $(shell [ "$(KERN_MAJ)" -lt 7 ] && echo y),install-vboxvideo,)
```

Two defects: it reads the **build host's running kernel** via `uname -r` rather
than the target kernel (meaningless in a Nix sandbox, which reports a pre-7
release, so the gate always opens), and the `< 7` threshold is wrong regardless
since 6.6/6.12/6.18 also lack the symbol.

### Why this only now broke the deploy

`pkgs.linuxPackages` moved from 6.12 to 6.18.44. `modules/zfs-server.nix` sets
`boot.kernelPackages = lib.mkOverride 75 pkgs.linuxPackages`, which outranks
`modules/system-lts-kernel.nix` (priority 100). With `f05e4f2` having deleted
`vm.nix`'s `lib.mkForce` (priority 50), VM variants inherited 6.18.44 and the
guest-additions build entered the closure unguarded.

## Problem definition

Every `gpu = vm` variant fails to build:
`VirtualBox-GuestAdditions-7.2.14-6.18.44.drv` → `mount.vboxsf.drv` →
`system-path.drv` → `nixos-system-vexos-26.05.drv`.

User decision (2026-08-17): VirtualBox guest support is to be **kept** — some
VexOS VM installs run under Oracle VirtualBox, not only Proxmox/QEMU-KVM.
Disabling `virtualisation.virtualbox.guest` was therefore rejected, so the package
must be made buildable rather than removed.

## Proposed solution

New shared module `modules/gpu/vm-guest-additions.nix`, imported by both
`modules/gpu/vm.nix` and `modules/gpu/vanilla-vm.nix`, that sets
`boot.kernelPackages` once to the LTS kernel extended with a fixed
`virtualboxGuestAdditions`:

```nix
boot.kernelPackages = lib.mkForce (pkgs.linuxPackages_6_12.extend (lfinal: lprev: {
  virtualboxGuestAdditions = lprev.virtualboxGuestAdditions.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      for mk in src/vboxguest-*/Makefile; do
        substituteInPlace "$mk" \
          --replace-fail 'KERN_MAJ = $(shell uname -r | cut -d . -f1)' 'KERN_MAJ = 99'
      done
    '';
  });
}));
```

Setting `KERN_MAJ = 99` forces upstream's own exclusion for the `all`, `install`
and `clean` targets — no patching of build logic we do not own, and it fails loudly
via `--replace-fail` if nixpkgs changes the Makefile.

Two things are restored/kept alongside it:

- The `lib.mkForce pkgs.linuxPackages_6_12` LTS pin, both because VM variants are
  expected to run LTS and because `modules/zfs-server.nix`'s comment documents a
  deliberate priority contract (its `mkOverride 75` "intentionally loses to
  `lib.mkForce` (priority 50) in `modules/gpu/vm.nix`"). `f05e4f2` broke that
  contract silently.
- `use3rdPartyModules = false`, whose comment is corrected: it does not remove the
  broken build (that is what the override does); it selects the mainline
  vboxguest/vboxsf/vboxvideo drivers for loading.

Prototype verified: builds successfully against 6.12.103 and produces
`bin/{mount.vboxsf,VBoxClient,VBoxControl,VBoxDRMClient,VBoxService}` plus
`vboxguest.ko.xz` and `vboxsf.ko.xz`. Only `vboxvideo.ko` is absent, supplied
instead by the in-tree DRM driver (mainline since kernel 4.13).

## Implementation steps

1. Create `modules/gpu/vm-guest-additions.nix` with the pinned + overridden
   `boot.kernelPackages`.
   → verify: file exists and is `git add`-ed (untracked files are invisible to nix)
2. Import it from `modules/gpu/vm.nix`; correct the `use3rdPartyModules` comment.
   → verify: `grep -n "vm-guest-additions" modules/gpu/vm.nix`
3. Import it from `modules/gpu/vanilla-vm.nix`; same comment correction.
   → verify: `grep -n "vm-guest-additions" modules/gpu/vanilla-vm.nix`
4. Prove the package builds through the NixOS module path.
   → verify: `nix build …nixosConfigurations.vexos-server-vm.config.boot.kernelPackages.virtualboxGuestAdditions`
5. Per-variant closure validation (Phase 3).
   → verify: `nixos-rebuild dry-build` for `vexos-server-vm` and `vexos-desktop-vm`;
     `nix eval` for `vexos-vanilla-vm`, `vexos-htpc-vm`, `vexos-stateless-vm`,
     `vexos-headless-server-vm`, plus `vexos-desktop-amd`/`-nvidia` for regressions
6. Preflight.
   → verify: `bash scripts/preflight.sh` exits 0

## Dependencies

None added. No new flake inputs. Context7 not applicable — no external library
integration; the change is an in-repo `overrideAttrs` on an existing nixpkgs
attribute.

## Configuration changes

VM-variant hosts return to kernel 6.12.103 LTS (maintained to Dec 2026) from
6.18.44. No user-facing options change.

## Risks and mitigations

- **Risk:** nixpkgs changes the vendored Makefile and the substitution stops matching.
  **Mitigation:** `--replace-fail` turns that into a hard build error, not a silent no-op.
- **Risk:** nixpkgs bumps the guest-additions version or fixes this upstream, making
  the override redundant.
  **Mitigation:** harmless if still applied; remove when `virtualboxGuestAdditions`
  builds unpatched. Documented in the module comment.
- **Risk:** losing out-of-tree `vboxvideo` degrades VirtualBox display handling.
  **Mitigation:** the in-tree `vboxvideo` DRM driver has been mainline since 4.13 and
  is already what `use3rdPartyModules = false` selects; `VBoxDRMClient` and
  `VBoxClient --vmsvga-session` (which drive auto-resize) are still installed.
- **Risk:** the LTS pin masks `zfs-server.nix`'s ZFS-compatibility kernel on
  `vexos-server-vm`.
  **Mitigation:** pre-existing and intentional — `vm.nix` sets
  `boot.supportedFilesystems.zfs = lib.mkForce false`, so no ZFS module is built.
- **Risk:** VM guests lose post-6.12 kernel features (e.g. `scx`).
  **Mitigation:** already handled — `vm.nix` sets `services.scx.enable = lib.mkForce false`.

## Out of scope (observed, not changed)

- `modules/zfs-server.nix` says `vm.nix` pins `linuxPackages_6_6`; it is and was
  `linuxPackages_6_12`. Stale comment, pre-existing.
- Because `pkgs.linuxPackages` moved to 6.18.44, **bare-metal** server roles now run
  6.18.44 despite importing `modules/system-lts-kernel.nix`, whose comment claims
  6.12 LTS. Pre-existing priority inversion, unrelated to this failure.
- `hosts/vanilla-vm.nix` enables `virtualisation.virtualbox.guest` with no kernel
  pin, but nothing imports it — `flake.nix:452` wires `vexos-vanilla-vm` to
  `modules/gpu/vanilla-vm.nix`. Appears to be dead code.
