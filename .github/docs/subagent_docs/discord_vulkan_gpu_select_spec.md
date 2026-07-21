# Discord/Vesktop Vulkan GPU selection fix — Spec

## Current state analysis

`modules/gaming.nix` installs two Electron-based Discord clients as plain
`environment.systemPackages` entries:

```nix
pkgs.unstable.vesktop # feature-rich Discord client (Vencord-based)
pkgs.discord         # official Discord client
```

Both are gated behind `vexos.features.gaming.enable` via the module's existing
`lib.mkIf cfg.enable` block (`modules/gaming.nix:31`) — the standard
same-module-option carve-out, not role-smuggling.

The affected host is `vexos-desktop-nvidia`, a hybrid AMD+NVIDIA laptop:

- NVIDIA GeForce RTX 5070 Max-Q (`10de:2d58`, PCI `01:00.0`) drives the
  internal panel (`card1-eDP-1: connected`) — this is the GPU Mutter
  compositors against.
- AMD Radeon 780M iGPU (PCI `66:00.0`) has no display output attached; it
  sits idle for graphics output.
- Driver branch is `nvidiaDriverVariant = "latest"` (`modules/gpu/nvidia.nix`),
  currently resolving to 595.71.05 — inside the "580+" series.

## Problem definition

Both apps are Electron 37.x, which added a Vulkan-based Wayland rendering
path. A known Mutter/NVIDIA-580+ regression
([GNOME Mutter #4326](https://gitlab.gnome.org/GNOME/mutter/-/issues/4326))
causes Vulkan device auto-selection on hybrid AMD+NVIDIA laptops to pick the
idle AMD iGPU instead of the NVIDIA GPU actually driving the display. The
result is a cross-GPU dma-buf import that Mutter (compositing on NVIDIA)
cannot accept:

```
libwayland: [destroyed object]: error 7: failed to import supplied dmabufs:
Could not bind the given EGLImage to a CoglTexture2D
```

Symptoms observed on this host, both explained by the same root cause:

- **Discord** crashes immediately after the splash screen (fatal GPU process
  crash from the failed dma-buf import).
- **Vesktop** launches (main window doesn't do full-screen Vulkan capture at
  startup) but screen-share silently does nothing — its hardware-encode
  capture path also probes Vulkan and hits the same wrong-GPU selection.

## Proposed solution

Pin Vulkan device selection for these two packages to the NVIDIA GPU via the
`MESA_VK_DEVICE_SELECT` environment variable (Mesa/Vulkan-loader mechanism,
documented workaround in the linked Mutter issue), scoped only to `discord`
and `vesktop` — not a system-wide session variable — so no other
Vulkan-consuming app (games, `mangohud`, etc.) is affected by a change aimed
at one specific bug.

Each package is wrapped via `overrideAttrs`, appending a `wrapProgram --set`
call in `postFixup` (requires `pkgs.makeWrapper` in `nativeBuildInputs`).
This is the standard nixpkgs technique for adding launch-time env vars to an
existing derivation without touching its `.desktop` entry, icon, or binary
name — `gnome-desktop.nix:89-90` and `home-desktop.nix:222` reference
`vesktop.desktop` / `discord.desktop` by name and must keep working
unmodified.

```nix
let
  # NVIDIA RTX 5070 Max-Q PCI ID (see modules/gpu/nvidia.nix) — pins Vulkan
  # device selection away from the idle AMD iGPU. Works around a Mutter/
  # NVIDIA 580+ regression (GNOME Mutter #4326) where Electron 37's Vulkan
  # Wayland path picks the wrong GPU on hybrid AMD+NVIDIA laptops, causing a
  # cross-GPU dmabuf import failure (Discord crash-on-launch; Vesktop
  # screen-share no-op).
  nvidiaVkSelect = pkg: attr: pkg.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/${attr} --set MESA_VK_DEVICE_SELECT "10de:2d58!"
    '';
  });
in
[
  (nvidiaVkSelect pkgs.unstable.vesktop "vesktop")
  (nvidiaVkSelect pkgs.discord "discord")
]
```

This is a hardware-specific workaround (PCI ID is this host's dGPU). Since
`vexos-nix` is a personal single-owner flake and `nvidia.nix` already
documents driver-branch specifics inline, a code comment noting the PCI ID
source is sufficient — no new option is warranted for a single-host,
single-bug workaround.

## Implementation steps

1. In `modules/gaming.nix`, add a local `let`-bound helper (scoped to the
   file, near existing package list) that wraps a package with
   `MESA_VK_DEVICE_SELECT`.
2. Replace the two plain package references
   (`pkgs.unstable.vesktop`, `pkgs.discord`) in `environment.systemPackages`
   with the wrapped versions.
3. No changes needed to `gnome-desktop.nix` or `home-desktop.nix` — `.desktop`
   file names and binary names are unchanged by `overrideAttrs`.

## Dependencies

No new flake inputs or external packages. `pkgs.makeWrapper` is already in
nixpkgs (used implicitly by many derivations); adding it to
`nativeBuildInputs` for these two `overrideAttrs` calls is sufficient.

## Configuration changes

None outside `modules/gaming.nix`.

## Risks and mitigations

- **Risk:** `overrideAttrs` rebuilds these derivations locally instead of
  pulling the prebuilt binary cache hit, since `postFixup` changes the fixup
  phase.
  **Mitigation:** Both packages are already prebuilt Electron binaries
  vendored via `fetchurl`/AppImage-style extraction with no compilation step;
  `postFixup` wrapping is a tiny, fast local rebuild (seconds), not a full
  source build. Acceptable one-time cost on `nixos-rebuild switch`.
- **Risk:** PCI device ID is hardware-specific; if this flake is ever built
  for a different GPU, the pin would be wrong.
  **Mitigation:** This is a single-owner personal flake for known hardware
  (`hosts/desktop-nvidia.nix`); the comment documents the assumption. If the
  workaround needs to generalize later, it can be moved behind
  `vexos.gpu.nvidiaDriverVariant`-style host option — out of scope for this
  fix.
- **Risk:** Upstream Mutter/NVIDIA fix ships later, making the wrapper inert
  or (unlikely) harmful.
  **Mitigation:** `MESA_VK_DEVICE_SELECT` pinning to the correct GPU is a
  no-op once upstream selects the right GPU by default — it just keeps
  forcing the already-correct choice. Safe to leave in place; comment makes
  it easy to find and remove later if desired.
