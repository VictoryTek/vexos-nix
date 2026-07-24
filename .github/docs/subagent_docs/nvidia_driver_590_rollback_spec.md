# Temporary NVIDIA driver rollback to 590.48.01 — Spec

## Current state analysis

`modules/gpu/nvidia.nix` exposes `vexos.gpu.nvidiaDriverVariant`, currently
supporting two choices:

- `"latest"` (default) → `nvidiaPackages.stable`, currently resolving to
  **595.71.05**
- `"legacy_535"` → `nvidiaPackages.legacy_535` (535.288.01) — **not viable**
  for this GPU; the 535 branch predates Blackwell support entirely (RTX 50
  series requires 570+), and `useOpen = variant == "latest"` forces closed
  proprietary kernel modules for this branch, which also don't support
  Blackwell.

No host currently overrides `nvidiaDriverVariant` — every NVIDIA host
(`desktop-nvidia`, `server-nvidia`, `htpc-nvidia`, `vanilla-nvidia`,
`stateless-nvidia`, `headless-server-nvidia`) implicitly uses `"latest"`.

## Problem definition

595.71.05 exhibits a reproducible dma-buf/EGLImage import crash on this
host's hybrid AMD+NVIDIA laptop (`vexos-desktop-nvidia`), affecting
Discord and Vesktop on native Wayland — see
`.github/docs/subagent_docs/discord_vulkan_gpu_select_*` for the full
investigation. Three app-level mitigations (Vulkan device pin, EGL vendor
pin, forcing XWayland) all failed to resolve it; this points to a
driver/compositor-level bug, not something fixable from the app side.

Supporting evidence found: [ublue-os/bazzite#4345](https://github.com/ublue-os/bazzite/issues/4345)
reports the same failure class (`DMA-BUF` import failure breaking Discord
screen-share) triggered specifically by an NVIDIA driver update from
**590.48.01 → 595.45.04** on hybrid GPU hardware. Their only workaround was
rolling back to the pre-590→595 driver. This is the strongest concrete data
point available: 590.48.01 is a specific version confirmed to work, on the
same bug class, immediately prior to the version where it broke.

## Proposed solution

Add a third `nvidiaDriverVariant` choice, `"new_feature"`, mapping to
`nvidiaPackages.new_feature` — nixpkgs currently pins this attribute to
**590.48.01**, matching Bazzite's last-known-good version exactly. (Distinct
from `nvidiaPackages.dc_590`, also 590.48.01 but built from NVIDIA's Tesla/
data-center driver line — a different product line aimed at headless compute
GPUs, using `useFabricmanager = true` and a `tesla/` download URL. The
`new_feature` attribute uses the same desktop/consumer driver template as
`stable`/`latest`, making it the correct choice for a GeForce laptop GPU.)

Confirmed via direct inspection of the nixpkgs source
(`pkgs/os-specific/linux/nvidia-x11/default.nix`) that `new_feature` ships
an open-kernel-module build (`openSha256` present) — required for Blackwell,
same as `"latest"`. `useOpen` logic extended accordingly.

Scope: **`hosts/desktop-nvidia.nix` only.** No other NVIDIA host has
reported or been confirmed to exhibit this bug; changing the module's
default would silently affect five other host configs without evidence.
This stays a targeted, single-host override.

## Important caveat — version drift risk

`nvidiaPackages.new_feature` is nixpkgs' rolling alias for NVIDIA's "New
Feature Branch" — nixpkgs maintainers bump this attribute forward over
time as NVIDIA ships new new-feature releases (distinct from `stable`/
`production`, which tracks the certified-stable branch). This repo runs
automated `nix flake update` via CI (`chore: update flake inputs (daily)` /
`(weekly, all)` commits visible in git history). A future automated update
could silently move `new_feature` past 590.48.01 to a newer version,
re-introducing the exact bug this rollback avoids, without anyone noticing
until Discord/Vesktop break again.

Mitigation chosen: **document the risk inline** rather than hand-write a
fully hash-pinned driver derivation (which would mean duplicating nixpkgs'
`generic {}` NVIDIA driver builder logic locally — significant complexity
for a temporary, revert-when-upstream-fixes-it workaround, against this
project's simplicity-first principle). The host config comment instructs
whoever reviews future `flake.lock` update PRs/commits to check whether
`nvidiaPackages.new_feature` has moved past 590.48.01, and if so, to
re-evaluate whether the bug is fixed upstream or whether a harder pin is
now warranted.

## Implementation steps

1. `modules/gpu/nvidia.nix`:
   - Extend `nvidiaDriverVariant` enum: `[ "latest" "legacy_535" "new_feature" ]`
   - Extend `driverPackage` let-binding with the `new_feature` branch
   - Extend `useOpen` to `variant == "latest" || variant == "new_feature"`
   - Update option description and header comment to document the new
     choice, why it exists, and the version-drift caveat
2. `hosts/desktop-nvidia.nix`:
   - Add `vexos.gpu.nvidiaDriverVariant = "new_feature";` with a comment
     explaining this is a temporary rollback (links to the Bazzite issue
     and the Discord/Vesktop investigation docs), to be reverted to
     `"latest"` once NVIDIA/Mutter ship a fix.

## Dependencies

No new flake inputs. `nvidiaPackages.new_feature` is already present in the
pinned `nixpkgs` input (confirmed via `nix eval`).

## Configuration changes

`hosts/desktop-nvidia.nix` gains one line plus explanatory comment.
`system.stateVersion` untouched. No `hardware-configuration.nix` changes.

## Risks and mitigations

- **Risk:** driver downgrade could break boot/display entirely if 590.48.01
  has its own regressions on this specific hardware (untested on this
  exact GPU/kernel combination).
  **Mitigation:** NixOS generations are reversible — if the switch produces
  a broken display, the previous generation (currently running 595.71.05)
  remains selectable from the bootloader/`nixos-rebuild switch
  --rollback`. This is a standard, low-risk NixOS operation, not a
  destructive change.
- **Risk:** version drift on `nix flake update` silently re-introduces the
  bug (see caveat above).
  **Mitigation:** documented inline in both files; no automated safeguard
  added (would require CI tooling beyond this task's scope) — accepted as
  a known limitation of the "revert when fixed" approach the user
  explicitly requested over a fully-pinned, higher-maintenance derivation.
- **Risk:** `useOpen` mis-set for the new branch causes a kernel module
  build failure.
  **Mitigation:** confirmed `openSha256` is present for `new_feature` in
  nixpkgs source before writing this spec; will be verified again via
  `nix eval --impure` toplevel evaluation in Phase 3.
