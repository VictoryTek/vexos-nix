# Specification: Add system-nosleep.nix to configuration-stateless.nix

**Feature:** stateless_nosleep  
**Date:** 2026-04-27  
**Status:** Ready for Implementation  

---

## Current State

`configuration-stateless.nix` imports 16 modules but does **not** import `./modules/system-nosleep.nix`. The stateless role (kiosk/ephemeral) has no sleep/suspend/hibernate prevention configured anywhere in its import chain. No stateless-specific module (`gnome-stateless.nix`, `impermanence.nix`) contains sleep-related settings.

## Problem

A stateless/kiosk system must never sleep, suspend, or hibernate. Without `system-nosleep.nix`, systemd can still honour suspend keys, idle timeouts, and GNOME power-management defaults — causing the ephemeral kiosk to go to sleep unexpectedly.

## Proposed Solution

Add `./modules/system-nosleep.nix` to the imports list in `configuration-stateless.nix`, following the same pattern used by `configuration-htpc.nix`.

Additionally, update the header comment in `modules/system-nosleep.nix` (line 3) to reflect that the module is now also imported by the stateless role.

## Implementation Steps

### Step 1 — Add import to `configuration-stateless.nix`

Insert the following line into the `imports` array, after `./modules/system.nix` (line 17):

```nix
    ./modules/system-nosleep.nix    # disable sleep/suspend/hibernate on stateless
```

This mirrors the placement in `configuration-htpc.nix` where `system-nosleep.nix` appears directly after `system.nix`.

### Step 2 — Update comment in `modules/system-nosleep.nix`

Change line 3 from:

```nix
# Import in configuration-desktop.nix and configuration-htpc.nix.
```

to:

```nix
# Import in configuration-desktop.nix, configuration-htpc.nix, and configuration-stateless.nix.
```

Change line 4 from:

```nix
# Do NOT import in server, headless-server, or stateless roles.
```

to:

```nix
# Do NOT import in server or headless-server roles.
```

## Modified Files

1. `configuration-stateless.nix` — add one import line
2. `modules/system-nosleep.nix` — update two header comment lines

## Dependencies

None. `system-nosleep.nix` already exists and is functional.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Conflict with existing sleep settings | None | Verified: no sleep/suspend/hibernate config exists in the stateless import chain |
| Module evaluation error | Minimal | Module is already imported successfully by desktop and HTPC roles |
| Unintended side-effects | None | Purely additive; the module only disables sleep — it does not enable anything |

## Verification

- `nix flake check` must pass
- `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` (and nvidia/intel/vm variants) must succeed
- Confirm `system-nosleep.nix` settings appear in the stateless system closure
