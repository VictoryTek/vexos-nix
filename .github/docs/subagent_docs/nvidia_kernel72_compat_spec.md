# NVIDIA on kernel 7.2 — Phase 1 Spec

> Supersedes `nvidia_kernel71_pin_spec.md`. That plan (pin NVIDIA hosts to
> kernel 7.1) is retained only as a documented fallback — it is no longer the
> recommendation, because staying on kernel 7.2 has been verified to work.

## Problem

`vexos-desktop-nvidia` cannot build. `configuration-desktop.nix` uses
`modules/system-latest-kernel.nix` (`linuxPackages_latest` = **kernel 7.2**),
and `modules/gpu/nvidia.nix` selects `nvidiaPackages.stable` = `production` =
**595.71.05**, whose open kernel modules do not compile against 7.2:

1. `strncpy` removed from kernel-space `include/linux/string.h` (replaced by
   `strscpy`) — 5 call sites across 4 files in `kernel-open/`.
2. DRM atomic API renamed: `drm_atomic_state*` → `drm_atomic_commit*`.

## Key finding — upstream already solved this

CachyOS maintains per-kernel NVIDIA compat patches, and nixpkgs **already
vendors them** (`gpl_symbols_linux_615_patch`, `kernel_6_19_patch` in
`pkgs/os-specific/linux/nvidia-x11/default.nix` are `fetchpatch` calls
pointing at CachyOS URLs). nixpkgs simply has not pulled the 7.2 one in yet.

`CachyOS/kernel-patches` → `7.2/misc/nvidia/0001-make-Add-support-for-7.2-Kernel.patch`
touches exactly the five files diagnosed above. The DRM half — which an
earlier pass in this project wrote off as "real driver engineering" — is in
fact a mechanical rename map, because the 7.2 change was a pure rename:

```c
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 2, 0)
#define drm_atomic_state       drm_atomic_commit
#define drm_atomic_state_put   drm_atomic_commit_put
...
#endif
```

## Verification performed

| test | result |
|---|---|
| `linuxPackages_7_2` + production 595.71.05 + CachyOS patch | ✅ **builds** — 5 modules installed, store path valid |
| `linuxPackages_7_2` + production 595.71.05, unpatched | ❌ `strncpy` + DRM errors |
| `linuxPackages_7_1` + production 595.71.05 | ✅ builds, **prebuilt on cache.nixos.org** |
| `linuxPackages_7_1` + legacy_580 (580.173.02) | ✅ builds |
| `linuxPackages_7_2` + legacy_580 (580.173.02) | ❌ **only** `strncpy` at `os-interface.c:732`; no DRM errors |
| `linuxPackages_7_1` + legacy_535 (535.288.01) | ❌ fails |
| `linuxPackages_7_2` + legacy_535 (535.288.01) | ❌ fails |

Successful 7.2 build output:
```
/nix/store/j4kzrwvd5wkhx0y935fw5m9r161865qz-nvidia-open-595.71.05-7.2
  nvidia.ko.xz  nvidia-uvm.ko.xz  nvidia-modeset.ko.xz
  nvidia-drm.ko.xz  nvidia-peermem.ko.xz
```

## Proposed solution

### Part A — main NVIDIA path stays on kernel 7.2

Carry the CachyOS 7.2 patch via `patchesOpen` on the production driver in
`modules/gpu/nvidia.nix`. **No kernel change** — desktop and stateless stay on
`linuxPackages_latest`. This mirrors nixpkgs' own established pattern.

- Patch must be a `fetchpatch` pinned to a **commit SHA, not `master`**, with
  an explicit hash, so the build is reproducible and cannot shift underneath.
- Applies only to the open-module path (`patchesOpen`), so closed-module
  variants are untouched.

### Part B — Pascal / Quadro P620 support

The user runs a **Quadro P620 (Pascal)** in secondary machines. Current state
is worse than assumed:

- NVIDIA's **580 branch is the last** supporting Maxwell/Pascal/Volta; 590+
  dropped them. So the default `latest` (595.71.05) does **not** support the
  P620 at all.
- `latest` also sets `hardware.nvidia.open = true`, and open modules require
  **Turing or newer** — unusable on Pascal regardless of driver version.
- `legacy_535` — the only legacy branch currently wired up — fails to build on
  both 7.1 and 7.2 (verified). It is a dead option.

So the P620 is **already broken today**, on every available variant.

Fix: replace `legacy_535` with `legacy_580` (580.173.02, in nixpkgs, uses
proprietary non-open modules — correct for Pascal). `modules/gpu/nvidia.nix`
already carries a TODO for this: *"legacy_580 support is planned once nixpkgs
issue #503740 is resolved."*

Two sub-options for the kernel on those machines:

- **B1 (verified):** `legacy_580` + kernel **7.1** pinned to that variant
  only. Builds today, no patch needed. 7.1 is current mainline, not LTS.
- **B2 (unverified, likely tractable):** `legacy_580` + kernel **7.2** + a
  small `strncpy`→`strscpy` patch against the *closed* module source
  (`kernel/` paths, so nixpkgs' `patches` parameter, not `patchesOpen`). The
  580-on-7.2 build produced exactly one error class and **no DRM errors**,
  so the scope looks small — but it must be written and build-verified before
  being claimed.

Recommendation: implement **B2**, falling back to **B1** if it does not build
cleanly within a bounded attempt. B2 keeps every machine on latest, which is
the project's stated goal.

## Risks and mitigations

- **Risk:** patched driver is not on `cache.nixos.org`, so it compiles locally
  (~minutes) on each driver or kernel bump.
  **Mitigation:** accepted tradeoff for staying on latest. The 7.1 route
  (cache-only, one minor behind) is documented as a fallback.
- **Risk:** nixpkgs bumps NVIDIA past 595.71.05 (upstream is already at
  610.57.04) and the patch stops applying.
  **Mitigation:** fails loudly at patch time, never silently. Revert trigger
  documented in the module: when nixpkgs ships a 7.2-capable driver or adds
  its own kernel-7.x `patchesOpen` entry, delete the local patch.
- **Risk:** pinning the patch to `master` would make builds non-reproducible.
  **Mitigation:** pin to a commit SHA + hash, as nixpkgs does.
- **Risk:** dropping `legacy_535` removes a variant someone depends on.
  **Mitigation:** it does not build on any kernel this project ships, so
  nothing functional is lost; `legacy_580` strictly supersedes it for the
  hardware it targeted.
- **Note:** CI (`ci.yml:202`) runs `nix eval …drvPath`, which evaluates without
  compiling — it cannot catch a driver that fails to build. That is why
  `legacy_535` appeared healthy for months. Worth addressing separately;
  out of scope here.

## Success criteria

1. `nix flake show --impure` lists all outputs without error.
2. `nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` exits 0, still on
   kernel 7.2.
3. The patched `nvidia-open-595.71.05-7.2` derivation builds (already
   demonstrated out-of-tree).
4. A Pascal variant exists that builds and uses non-open modules.
5. `nixos-rebuild dry-build` still exits 0 for `.#vexos-desktop-amd` and
   `.#vexos-desktop-vm`.
6. `bash scripts/preflight.sh` exits 0.
