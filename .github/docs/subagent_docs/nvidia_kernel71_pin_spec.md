# NVIDIA desktop kernel pin (7.1) — Phase 1 Spec

## Current state analysis

`vexos-desktop-nvidia` fails to build. `configuration-desktop.nix:26` imports
`modules/system-latest-kernel.nix`, which sets
`boot.kernelPackages = pkgs.linuxPackages_latest`. In the currently locked
nixpkgs (`f4f698677b11`, 2026-08-25 — healthy, 68 commits behind
`nixos-26.05` HEAD) that alias resolves to **kernel 7.2**:

```
linux_latest = packages.linux_7_2;      # pkgs/top-level/linux-kernels.nix:749
```

`modules/gpu/nvidia.nix` selects `nvidiaPackages.stable` for the default
`vexos.gpu.nvidiaDriverVariant = "latest"`, which resolves to `production`
= **595.71.05**. That driver's open kernel modules do not compile against
kernel 7.2. Two independent, verified breakages:

1. `strncpy` was removed from kernel-space `include/linux/string.h`
   (only `strscpy` / `sized_strscpy` remain). 5 call sites across 4 files in
   `kernel-open/` fail with `-Werror=implicit-function-declaration`.
2. The DRM atomic-commit API was restructured (`struct drm_atomic_state` →
   `struct drm_atomic_commit`-shaped types, `drm_atomic_state_put` →
   `drm_atomic_commit_put`). `nvidia-drm/nvidia-drm-helper.c` no longer
   matches it.

Breakage (1) was fixed locally in an earlier session pass and verified by
build; breakage (2) is a genuine driver-API port and out of scope for a
carried patch. Those local changes have since been reverted — the working
tree is clean and matches `origin/main`.

## Problem definition

Every `vexos.gpu.nvidiaDriverVariant = "latest"` host on the latest-kernel
roles (`desktop`, `stateless`) cannot build. This blocks `just deploy` /
`just update` on the user's primary machine.

## Constraint (hard requirement)

The desktop role **must not** be moved to an LTS kernel track. vexos-nix
exists to run the newest versions that can be run stably; falling back to
`modules/system-lts-kernel.nix` (6.12) defeats its purpose. LTS is reserved
for `server`, `headless-server`, and `htpc`.

## Options evaluated

| Option | Verdict |
|---|---|
| Different NVIDIA branch (`beta` / `new_feature` / `latest` / `bleeding_edge`) | **Rejected — no gain.** Verified in the locked nixpkgs: `production` = 595.71.05, `new_feature` = 590.48.01, `beta` = 595.45.04. `latest` and `bleeding_edge` both `selectHighestVersion` back to 595.71.05. Production is already the newest driver nixpkgs has. |
| Carry local compat patches | **Rejected — insufficient.** The `strncpy` half was fixed and build-verified; the DRM atomic-commit half is a real driver port with display-corruption / use-after-free risk. Not appropriate to improvise. |
| LTS kernel (6.12) | **Rejected** — violates the hard constraint above. |
| chaotic-nyx / CachyOS kernels | **Deferred.** Adds a large third-party flake input plus its own binary cache and bleeding-edge risk. CachyOS's own forum reports 595.71.05 failing to build on kernel 7.x, so it is not a reliable fix for this specific break. Keep as a future option, not this change. |
| **Pin NVIDIA-on-latest-roles to `linuxPackages_7_1`** | **Selected — verified working.** |

## Proposed solution

Pin **only the NVIDIA variants of the latest-kernel roles** to
`pkgs.linuxPackages_7_1`. Kernel 7.1 is current mainline, one minor release
behind latest — it is **not** an LTS or maintenance kernel. In the locked
nixpkgs, 7.1 and 7.2 are the only mainline kernels still present alongside
`linux_6_18` (`linux_default`); 6.16, 6.17, 6.19 and 7.0 have all been
removed as EOL. So 7.1 is the newest kernel that the newest available NVIDIA
driver actually supports.

### Verification performed

```
nix build …linuxPackages_7_1.nvidiaPackages.production.open
  → /nix/store/…-nvidia-open-595.71.05-7.1.10   EXIT=0
  → "copying path … from 'https://cache.nixos.org'"
```

The module is not merely buildable — it is **prebuilt on cache.nixos.org**,
so NVIDIA hosts stop compiling the driver locally entirely (today the 7.2
path forces a local build that then fails).

Full-system dry-build of the real target config also passes:

```
nix build --dry-run  vexos-desktop-nvidia (boot.kernelPackages = linuxPackages_7_1)
  → 46 derivations to build (linux-7.1.10-modules, -shrunk, initrd only)
  → 38 paths fetched; nvidia-open NOT in the build list   EXIT=0
```

### Implementation steps (Module Architecture Pattern — Option B)

This adds a **role/feature-specific addition file** imported only where it
applies, with no conditional logic inside — the standard Option B shape. It
does not add a `lib.mkIf` guard to any shared module.

1. **New file `modules/gpu/nvidia-latest-kernel.nix`** — sets
   `boot.kernelPackages = lib.mkOverride 95 pkgs.linuxPackages_7_1;` with a
   comment stating this is a temporary NVIDIA-compat pin, why 7.1, and the
   exact condition for removing it.

2. **Import it from the two host files** already on the latest-kernel track
   with NVIDIA — `hosts/desktop-nvidia.nix` and `hosts/stateless-nvidia.nix`.
   Because `flake.nix`'s `mkHost` reuses `hosts/<role>-<gpu>.nix` for the
   `legacy535` variants too, these two imports cover all four affected
   outputs:
   - `vexos-desktop-nvidia`
   - `vexos-desktop-nvidia-legacy535`
   - `vexos-stateless-nvidia`
   - `vexos-stateless-nvidia-legacy535`

   Server / headless-server / htpc NVIDIA variants keep their LTS kernel;
   vanilla (nouveau) and the amd / intel / vm desktop variants keep
   `linuxPackages_latest` (7.2), which works fine for them.

3. **Update the priority-ladder comment** in
   `modules/system-custom-kernel.nix` to document the new rung.

### Priority placement

`modules/system-custom-kernel.nix` documents an existing `boot.kernelPackages`
ladder (lower number = higher priority). The new pin slots at **95**:

```
1000  mkDefault      modules/system.nix
 100  normal         system-latest-kernel.nix / system-lts-kernel.nix
  95  mkOverride     THIS PIN — beats the role's latest-kernel default
  90  mkOverride     system-custom-kernel.nix  (user opt-in still wins)
  75  mkOverride     modules/zfs-server.nix
  50  mkForce        modules/gpu/vm-guest-additions.nix
```

95 beats the role default (100) but deliberately **loses** to the custom-kernel
opt-in (90), so `just enable-feature kernel` continues to override it, and the
ZFS and VM pins are unaffected.

## Dependencies

None. No new flake inputs, no new packages, no overlay changes. Context7 not
applicable (no external library integration).

## Configuration changes

Three files: one new module, two one-line host imports, plus a doc-comment
update. No `flake.nix`, `configuration-*.nix`, or `system.stateVersion`
changes.

## Risks and mitigations

- **Risk:** kernel 7.1 eventually reaches EOL and is removed from nixpkgs
  (7.0 removed 2026-06-27, 6.19 removed 2026-04-23). The alias then becomes a
  `throw` and evaluation fails.
  **Mitigation:** this fails loudly at eval with an explicit "reached its end
  of life" message, not silently. The module comment names the revert
  condition so the pin is removed rather than bumped indefinitely.

- **Risk:** the pin outlives its usefulness and silently holds NVIDIA hosts a
  minor version behind after nixpkgs ships a 7.2-capable driver.
  **Mitigation:** documented revert trigger — when
  `nvidiaPackages.production.version` exceeds 595.71.05 **or** a kernel-7.x
  entry appears in `patchesOpen` for production, delete the module and its two
  imports. Verifiable with a single `nix eval`.

- **Known pre-existing issue (NOT fixed by this change):** `legacy_535`
  (closed modules, 535.288.01) does **not** build on kernel 7.1 either —
  verified:
  ```
  nix build …linuxPackages_7_1.nvidiaPackages.legacy_535.mod
    → nvidia/nv.o, nv-dma.o, nv-mmap.o: Error 1  (VGA_CRTC_OFFSET et al.)   EXIT=1
  ```
  A 2023-era 535 driver cannot build against a 7.x kernel, and kernel 7.2 is
  strictly newer than 7.1, so `vexos-desktop-nvidia-legacy535` and
  `vexos-stateless-nvidia-legacy535` are already broken today — this pin
  neither causes nor worsens that. These two outputs are arguably structurally
  unsound: a 535 driver is incompatible with the latest-kernel roles by
  design. Recommend addressing separately (drop the legacy535 variants for
  `desktop`/`stateless`, or give them their own kernel track). Deliberately
  **out of scope** for this change; flagged, not silently altered.

- **Risk:** desktop AMD/Intel/VM variants diverge from NVIDIA on kernel
  version.
  **Mitigation:** intentional and desirable — non-NVIDIA users keep the
  newest kernel. The pin is scoped by GPU precisely to avoid penalising them.

## Success criteria

1. `nix flake show --impure` lists all outputs without error.
2. `nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` exits 0 with
   `nvidia-open` fetched from cache, not built.
3. `nixos-rebuild dry-build` still exits 0 for `.#vexos-desktop-amd` and
   `.#vexos-desktop-vm`, both still on kernel 7.2.
4. `bash scripts/preflight.sh` exits 0.
