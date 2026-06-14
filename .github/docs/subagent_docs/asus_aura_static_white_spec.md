# Spec: ASUS Aura static-white keyboard init for asusd 6.x

## Current State Analysis

In asusd 5.x (nixpkgs 25.11), `enableUserService = true` launched `asusd-user` at
login, which applied per-user LED profiles (including keyboard colour). In asusd 6.x
(nixpkgs 26.05), the user service is gone; the system daemon manages all LED state and
persists it to `/etc/asusd/aura_<prod_id>.ron`.

On first boot after the 26.05 upgrade, `/etc/asusd/` does not exist (no `auraConfigs`
entries are declared so NixOS does not create the directory). asusd creates a default
config with its built-in colour (red) — but until the config is applied via its D-Bus
interface the keyboard may remain dark.

The user's keyboard USB product ID is `19b6` (ITE N-KEY HID, `HID_ID=0018:00000B05:000019B6`).
Desired state: static white on every boot.

## Problem Definition

After upgrading to 26.05 with asusd 6.x, the built-in TUF keyboard RGB does not light
up because no LED mode has been applied via the daemon's D-Bus API.

## Proposed Solution

Add a systemd oneshot service `asus-aura-init` inside the existing `lib.mkIf` block in
`modules/asus-opt.nix`. The service:

- Runs after `asusd.service` (Type=dbus — D-Bus name acquired = daemon ready)
- Executes: `${pkgs.asusctl}/bin/asusctl aura static -c ffffff`
- Type=oneshot, RemainAfterExit=true
- Sets keyboard to static white; asusd persists the setting to its own config file

### Why this approach over `auraConfigs`

`auraConfigs` requires writing a valid RON `AuraConfig` struct. That struct includes
`builtins` (a BTreeMap of all supported modes), `enabled` (LaptopAuraPower), and other
fields whose exact serialized names/variants are not documented. A malformed RON file
causes asusd to fail to load the config silently. The CLI approach (`asusctl aura static
-c ffffff`) uses asusd's own D-Bus API, is format-agnostic, and asusd persists the
result to its own runtime config file.

## Implementation Steps

1. Add `systemd.services.asus-aura-init` block inside `config = lib.mkIf ...` in
   `modules/asus-opt.nix`.

## Affected Files

- `modules/asus-opt.nix`

## Risks and Mitigations

- **Risk:** `asusctl` exits non-zero if asusd is not running or doesn't support the mode.
  **Mitigation:** `After = [ "asusd.service" ]` with Type=dbus ensures readiness. Service
  failure is non-fatal (does not block boot).
- **Risk:** Colour persisted by asusd overwritten on rebuild if `auraConfigs` is added
  later. **Mitigation:** No `auraConfigs` is set here; asusd owns `/etc/asusd/aura_19b6.ron`.
