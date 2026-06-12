# Spec: Fix vexos-vanilla-nvidia-legacy535 evaluation failure

## Current State Analysis

- CI fails on `vexos-vanilla-nvidia-legacy535` with:
  `The option 'vexos.gpu' does not exist.`
- `mkHost` in `flake.nix` (lines 197–224) injects
  `{ vexos.gpu.nvidiaDriverVariant = nvidiaVariant; }` (`legacyExtra`) for any
  hostList entry with `nvidiaVariant`, while reusing the
  `hosts/<role>-<gpu>.nix` host file.
- For desktop/stateless/server/headless-server/htpc, `hosts/<role>-nvidia.nix`
  imports `modules/gpu/nvidia.nix`, which declares the
  `vexos.gpu.nvidiaDriverVariant` option — so those legacy outputs evaluate.
- `hosts/vanilla-nvidia.nix` deliberately uses kernel nouveau and does NOT
  import `modules/gpu/nvidia.nix`, so the option is undeclared → evaluation
  error for the vanilla legacy entry added in commit 9eb89e3.
- Intent per commit 9eb89e3 and `template/etc-nixos-flake.nix:335`:
  `vexos-vanilla-nvidia-legacy535` = vanilla role + proprietary legacy_535
  driver (`gpuNvidia` module + option). The main flake must match.

## Problem Definition

`vexos-vanilla-nvidia-legacy535` sets an option that no imported module
declares. Plain `vexos-vanilla-nvidia` must remain nouveau.

## Proposed Solution

In `mkHost`, make `legacyExtra` also import the nvidia module:

```nix
legacyExtra = lib.optional (nvidiaVariant != null) {
  imports = [ ./modules/gpu/nvidia.nix ];
  vexos.gpu.nvidiaDriverVariant = nvidiaVariant;
};
```

- Vanilla legacy output: gains the module that declares the option and
  applies the proprietary legacy_535 driver — semantics now identical to the
  template's `vexos-vanilla-nvidia-legacy535`.
- All other legacy outputs: the same path is already imported by their host
  file; the NixOS module system deduplicates path imports, so behavior is
  unchanged.
- No host file or shared module is touched; no `lib.mkIf` added (Option B
  pattern preserved).
- Update the `mkHost` ordering comment (item 6) to mention the import.

## Implementation Steps

1. Edit `flake.nix` `legacyExtra` and the adjacent comment.
   → verify: `nix eval --impure
     .#nixosConfigurations.vexos-vanilla-nvidia-legacy535.config.system.build.toplevel.drvPath`
2. Regression: same eval for `vexos-desktop-nvidia-legacy535` and
   `vexos-vanilla-nvidia` (must still evaluate; vanilla-nvidia must not gain
   the nvidia driver — check `services.xserver.videoDrivers`).
3. Preflight.

## Dependencies

None new; no flake inputs touched (Context7 not applicable).

## Configuration Changes

`vexos-vanilla-nvidia-legacy535` now actually enables the proprietary
legacy_535 driver (previously it failed to evaluate at all, so no working
system changes behavior).

## Risks and Mitigations

- Risk: double import altering non-vanilla legacy outputs — mitigated by
  module-system path deduplication; verified via desktop legacy eval.
- Risk: vanilla baseline polluted — only the legacy entry receives the
  import; verified via plain vanilla-nvidia eval.
