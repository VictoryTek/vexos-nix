# M-05 — `lib.mkDefault [ "btrfs" ]` discarded by generated hardware-configuration.nix

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-05 · `modules/stateless-disk.nix`

## Current State

```nix
boot.initrd.kernelModules = lib.mkDefault [ "btrfs" ];
```

`nixos-generate-config` always emits its own `boot.initrd.kernelModules = [ ... ];` in
`hardware-configuration.nix` as a **plain (priority-100)** assignment — even when the
list it emits is empty (no extra modules autodetected as needed). NixOS's module system
resolves list-type options by taking only the definitions at the *highest-priority*
tier present (lowest numeric priority) and merging (concatenating) those — definitions
at any lower-priority tier (like `mkDefault`'s 1000) are discarded **entirely**,
regardless of whether the winning tier's list is non-empty. So whenever
`hardware-configuration.nix`'s emitted list happens to be empty (common — most modules
needed for early initrd already come from `availableKernelModules`/initrd auto-detect),
the module's own `mkDefault [ "btrfs" ]` is silently dropped completely, and `btrfs`
never gets force-loaded in early initrd — exactly the scenario the module's own
preceding comment says it exists to prevent ("relies on udev hotplug ordering which is
unreliable in early initrd").

## Problem Definition

`btrfs` must always be present in `boot.initrd.kernelModules` for the stateless role,
regardless of whatever `hardware-configuration.nix` declares.

## Proposed Solution

Change `lib.mkDefault [ "btrfs" ]` to a plain `[ "btrfs" ]` — same priority (100) as
`hardware-configuration.nix`'s own definition. NixOS merges multiple same-priority
definitions of a list-type option by concatenation, not override, so this guarantees
`btrfs` is always present in the final list alongside whatever
`hardware-configuration.nix` adds, regardless of whether that list is empty.

## Implementation Steps

1. `modules/stateless-disk.nix` — `boot.initrd.kernelModules = lib.mkDefault [ "btrfs" ];`
   → `boot.initrd.kernelModules = [ "btrfs" ];`.

## Configuration Changes

None.

## Risks and Mitigations

- **Loses overridability** — intentional and correct: the whole point of this line is
  that `btrfs` must always be loaded for the stateless role; there's no legitimate
  reason for anything to remove it, so plain-priority (merge-only) semantics are exactly
  what's wanted, not something to preserve overridability for.
- **Verify the merge actually behaves as claimed** — confirmed via a synthetic build
  combining this module with a stub `hardware-configuration.nix` that declares its own
  (non-empty, to prove concatenation not just single-value luck)
  `boot.initrd.kernelModules`, checking the final merged list contains both.
