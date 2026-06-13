# Spec: NVIDIA open-driver cache reality + latest kernel for desktop/stateless

## Current state analysis (all verified against cache.nixos.org)

The installer repeatedly stops on NVIDIA desktop installs with "No cached packages
found in recent nixpkgs history" and a build-from-source / abort prompt. Extensive
probing established the true cause:

1. **Proprietary NVIDIA is never on cache.nixos.org.** `nvidia-x11` (userspace),
   `NVIDIA-*.run`, `nvidia-settings`, and the firmware are unfree / non-redistributable.
   Verified uncached at the `nixos-25.11` channel tip AND on fully-settled releases
   (`nixos-25.05`, `nixos-24.11`) for every kernel. No nixpkgs revision has cached
   proprietary NVIDIA — so any "roll back nixpkgs to find a cached driver" strategy is
   structurally impossible. This is why the history-walk fallback always returned empty.

2. **The open NVIDIA kernel module IS cached.** `nvidia-open-<kernel>-580.142` is present
   in cache for 6.12.92, 6.18.34, and 7.0.11 (GPL/MIT, redistributable). The desktop
   config already sets `hardware.nvidia.open = true` for the "latest" branch
   (`modules/gpu/nvidia.nix`), and the live `vexos-desktop-nvidia` config resolves the
   loadable module to the cached `nvidia-open`.

3. **The userspace package still builds locally.** `hardware.nvidia.package =
   nvidia-x11-580.142-<kernel>` provides libGL/X driver/settings; its derivation compiles
   the proprietary module (`KBUILD_OUTPUT`, `SYSSRC`, rust-bindgen, pahole) and is unfree,
   so it is never cached and always builds locally (~10-15 min, once per driver bump).
   This is unavoidable for proprietary NVIDIA userspace on NixOS — the open module being
   cached only removes the *separately-cached* loadable module from the build set.

4. **The 6.18 kernel pin was a stale hold.** `modules/system-desktop-kernel.nix` pinned
   `linuxPackages_6_18` "until NVIDIA 595.x", citing a 7.x build failure
   ("unknown pseudo-op .ryte"). `production` (580.142) is NOT marked broken on 7.0 in
   nixpkgs, and `nvidia-open-7.0.11-580.142` is cached (open module builds on 7.0). The
   proprietary userspace build on 7.0 is validated empirically before this change (build
   of `linuxPackages_latest.nvidiaPackages.stable` must succeed).

## Problem definition

- Installer treats the unavoidable, never-cacheable NVIDIA userspace + patched openrazer
  as a cache failure, runs a futile nixpkgs history-walk, and aborts/prompts with a
  misleading "30-60 min / no cached versions" message.
- Desktop (and stateless) are pinned to older kernels (6.18 / 6.12) by stale NVIDIA holds;
  user wants `linuxPackages_latest` for these two roles.

## Proposed solution

### A. Kernel: desktop + stateless → `linuxPackages_latest`

(Gated on the empirical 7.0 proprietary build succeeding.)

- Add `modules/system-latest-kernel.nix`: `boot.kernelPackages = pkgs.linuxPackages_latest;`
- `configuration-desktop.nix`: import `system-latest-kernel.nix` instead of
  `system-desktop-kernel.nix`.
- `configuration-stateless.nix`: import `system-latest-kernel.nix` instead of
  `system-lts-kernel.nix`.
- Delete `modules/system-desktop-kernel.nix` (only desktop imported it).
- `modules/razer.nix`: retarget the openrazer overlay from `linuxPackages_6_18` to
  `linuxPackages_latest` so the patched module tracks the active desktop kernel. (The
  6.18.32+/7.0.9 `hid_report_raw_event` patch is still required on 7.0.11.)
- `modules/system-lts-kernel.nix` stays for server/headless-server/htpc (deliberate LTS).

Module Architecture (Option B) compliance: `system-latest-kernel.nix` is an unconditional
additive module; roles select kernel purely by which kernel module they import. No
`lib.mkIf`.

### B. Installer: proceed with accurate message; drop the futile rollback

In `scripts/install.sh`:
- Remove the `--override-input nixpkgs` pre-pin block and the `find_cached_nixpkgs_for_attr`
  history-walk helper (both depend on cached proprietary NVIDIA, which cannot exist).
  Keep `nix flake update` + `git add flake.lock`.
- Replace the cache-check fallback: classify the dry-build's source-build list. Items
  matching the unavoidable set — `NVIDIA-Linux-`, `nvidia-x11-`, `nvidia-settings-`,
  `nvidia-persistenced-`, patched `openrazer-[0-9]` — are never cacheable. If those are
  the ONLY local builds, print an accurate one-time-build notice and proceed. If anything
  else needs a local build (a genuine cache miss), abort with the existing wait/retry
  guidance.
- Reword the `kernel-install-override.nix` cleanup comment (no longer "nixpkgs rollback").

## Risks and mitigations

- **7.0 proprietary build failure (.ryte).** Mitigation: build
  `linuxPackages_latest.nvidiaPackages.stable` before applying the kernel change; only
  proceed if it succeeds. If it fails, desktop/stateless stay on a working kernel and the
  user is consulted.
- **`vexos-update` parallel.** `modules/nix.nix` still classifies `nvidia-x11`/`openrazer`
  as HEAVY blockers, so `just update` will pause on NVIDIA bumps (requiring `just update-all`).
  Out of scope for this change (installer-focused); flagged as a follow-up.
- **Patched openrazer on 7.0.** Verified the overlay resolves (`openrazer-3.10.3-7.0.11`);
  it is a small local build, tolerated by the installer's new classification.

## Validation

- `nix flake show --impure` (structure).
- `nix eval` desktop-nvidia / stateless-nvidia: `boot.kernelPackages.kernel.version` == 7.0.x;
  `hardware.nvidia.open` == true; open module cached.
- `bash scripts/preflight.sh`.
- `bash -n scripts/install.sh`.
- Full per-variant `nixos-rebuild dry-build` delegated to CI (local sudo unavailable in
  this environment).
