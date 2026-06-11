# version_upgrade_stateversion_fix — Specification

## Current State

`just version-upgrade` (justfile:595-658) updates the NixOS release by:
1. Rewriting the `nixpkgs` URL in `flake.nix`
2. Rewriting the `home-manager` URL in `flake.nix`
3. Rewriting `system.stateVersion` in all `configuration-*.nix` files  ← WRONG

The recipe description comment also documents step 3 as intentional behaviour.

## Problem

`system.stateVersion` must never change after initial installation. It records the
NixOS version the system was first installed on and governs migration behaviour for
stateful data managed by NixOS activation scripts. Changing it can corrupt system
state. This is an absolute hard rule in CLAUDE.md and correctly documented in README.md.

Steps 1 and 2 are correct. Step 3 must be removed.

## Proposed Solution

1. Delete the step 3 block (justfile lines 646-652):
   - The `for` loop that iterates `configuration-*.nix` files
   - The `sed -i` that rewrites `system.stateVersion`
   - The `echo` confirmation line

2. Update the recipe description comment (justfile line 596-597) to remove the
   `system.stateVersion` mention so it no longer documents incorrect behaviour.

## Files Modified

- `justfile`

## Risks

None. Steps 1 and 2 are untouched. Removing step 3 only prevents a harmful
operation — it does not change any correct behaviour.
