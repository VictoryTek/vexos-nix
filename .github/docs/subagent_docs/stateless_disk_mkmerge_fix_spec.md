# Spec: Fix duplicate fileSystems attribute in stateless-disk.nix

## Current State Analysis

`modules/stateless-disk.nix` defines two attributes for the same path in a single Nix
attrset expression:

- Line 91: `fileSystems."/nix" = lib.mkDefault { ... };`
- Line 113: `fileSystems."/nix".neededForBoot = lib.mkForce true;`

Nix rejects this at parse time with:
```
error: attribute 'fileSystems."/nix"' already defined at ...stateless-disk.nix:91:7
       at ...stateless-disk.nix:113:7
```

This was introduced in commit `ad6d817` and breaks all five stateless CI targets.

## Problem Definition

Nix does not allow two definitions of the same attribute path within a single attrset
literal. The NixOS module system can merge *across separate modules*, but within a single
module's returned config attrset, every key must be unique.

The intent of the split was correct: the full filesystem entry is at `lib.mkDefault`
priority (1000) so `hardware-configuration.nix` can override it; the `neededForBoot` flag
is forced at `lib.mkForce` priority (0) so it survives any `hardware-configuration.nix`
override. But the implementation produces a Nix parse error.

## Proposed Solution

Wrap the config body in `lib.mkMerge [...]`. `lib.mkMerge` creates a list of config
values that the NixOS module system merges at evaluation time — each element is a
separate attrset, so the same key may appear in different elements without triggering
a parse error.

```nix
config = lib.mkIf cfg.enable (
  let
    isNvmeStyle = builtins.match ".*(nvme|mmcblk).*" cfg.device != null;
    bootPart    = if isNvmeStyle then "${cfg.device}p1" else "${cfg.device}1";
    rootPart    = if isNvmeStyle then "${cfg.device}p2" else "${cfg.device}2";
  in
  lib.mkMerge [
    {
      boot.initrd.kernelModules = lib.mkDefault [ "btrfs" ];

      fileSystems."/boot" = lib.mkDefault { ... };
      fileSystems."/nix" = lib.mkDefault { ... };
      fileSystems."/persistent" = lib.mkDefault { ... };
    }
    {
      # Separate attrset — no parse conflict.
      fileSystems."/nix".neededForBoot       = lib.mkForce true;
      fileSystems."/persistent".neededForBoot = lib.mkForce true;
    }
  ]
);
```

## Implementation Steps

1. Edit `modules/stateless-disk.nix`:
   - Replace the single attrset body `{ ... }` inside `lib.mkIf cfg.enable (let ... in { ... })`
     with `lib.mkMerge [ { ... } { ... } ]`.
   - First element: all existing declarations (boot.initrd.kernelModules + all three fileSystems).
   - Second element: only the two `lib.mkForce` neededForBoot declarations.
   - Keep the `let` binding for `bootPart`/`rootPart` in scope for both elements.

## Files to Modify

- `modules/stateless-disk.nix`

## Dependencies

None — this is a pure Nix language fix, no new dependencies.

## Risks and Mitigations

- **Risk:** `lib.mkMerge` changes merge semantics for the containing `lib.mkIf`.
  **Mitigation:** `lib.mkMerge` inside `lib.mkIf` is a standard NixOS pattern; the `mkIf`
  condition still gates everything. The `mkMerge` only affects how the inner attrsets are
  merged by the module system — it does not change priorities or evaluation order.
- **Risk:** The second attrset's `fileSystems."/nix".neededForBoot` sub-path might not
  merge cleanly with the first attrset's full `fileSystems."/nix"` definition.
  **Mitigation:** NixOS `fileSystems` is typed as `attrsOf submodule`; sub-module options
  merge via the module system, not as raw attrsets. `lib.mkMerge` feeds two separate
  config values into the module system which handles the merge correctly.
