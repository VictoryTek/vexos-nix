# Spec: Remove deprecated services.asusd.enableUserService

## Current State Analysis

`modules/asus-opt.nix:50` sets `services.asusd.enableUserService = true`.

In nixpkgs 26.05 (the Yarara upgrade), the `asusd` NixOS module removed the
`enableUserService` option because the asusd user service is no longer required by
the upstream daemon. nixpkgs now emits a `Failed assertions` error when this option
is present, blocking every build that enables ASUS hardware support.

## Problem Definition

Every `nixosConfigurations` output that sets `vexos.hardware.asus.enable = true`
(e.g. `vexos-desktop-nvidia`) fails to evaluate with:

```
Failed assertions: - The option definition `services.asusd.enableUserService' in
`.../modules/asus-opt.nix' no longer has any effect; please remove it.
The asusd user service is no longer required.
```

## Proposed Solution

Remove line 50 (`enableUserService = true;  # asusd-user: per-user Aura LED profile control`)
from `modules/asus-opt.nix`. No other file sets this option.

## Implementation Steps

1. Delete line 50 from `modules/asus-opt.nix`.
2. No other files require changes.

## Dependencies

None — internal change only; no new external dependencies.

## Risks and Mitigations

- **Risk:** Aura per-user LED profiles could regress if the user service was still
  needed at runtime. **Mitigation:** nixpkgs explicitly states it is no longer required;
  the upstream asusd >= 6.x handles LED profiles in the system daemon.
- No other risk: single-line removal, no logic change.
