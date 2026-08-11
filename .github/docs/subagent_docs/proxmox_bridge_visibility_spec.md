# Proxmox VE bridge not available for VM creation — spec

## Current state analysis

`modules/server/proxmox.nix` enables `services.proxmox-ve` and creates the
`vmbr0` bridge at the OS level via `networking.networkmanager.ensureProfiles`
(NetworkManager master + slave profiles enslaving `cfg.bridgeInterface` into
`vmbr0`). This part works: the bridge exists at the kernel level.

The `proxmox-nixos` (SaumonNet) module exposes a **separate, independent**
option: `services.proxmox-ve.bridges` (list of strings). Per upstream docs,
this option populates the list of bridges the Proxmox web UI offers when
creating a VM/CT network device. Upstream explicitly states this option
"doesn't affect your OS level network config in any way" — it is a pure
UI-registration list, decoupled from how the bridge is actually created
(scripted networking, systemd-networkd, or in our case NetworkManager).

`modules/server/proxmox.nix` never sets `services.proxmox-ve.bridges`. The
option defaults to empty, so the Proxmox web UI's VM-creation dialog shows no
bridge to attach a VM's NIC to, even though `vmbr0` exists and is up.

## Problem definition

`vexos.server.proxmox.enable = true` creates a working `vmbr0` bridge, but
the Proxmox web UI does not offer it as an option when creating a VM, because
`services.proxmox-ve.bridges` was never populated with `"vmbr0"`.

## Proposed solution

In `modules/server/proxmox.nix`, add:

```nix
services.proxmox-ve = {
  enable       = true;
  ipAddress    = cfg.ipAddress;
  openFirewall = cfg.openFirewall;
  bridges      = [ "vmbr0" ];
};
```

`vmbr0` is already a hardcoded literal throughout this file (profile names,
comments), so hardcoding it here too is consistent with existing style — no
new option is needed.

## Implementation steps

1. Edit `modules/server/proxmox.nix`: add `bridges = [ "vmbr0" ];` to the
   existing `services.proxmox-ve = { ... }` block (module architecture
   pattern unaffected — this is a single-module, single-option addition, not
   a new shared/role split).

## Dependencies

None new. `services.proxmox-ve.bridges` is an existing option on the already
consumed `proxmox-nixos` input (verified against upstream README).

## Configuration changes

None beyond the one-line addition above. No new `vexos.*` option is needed
since `vmbr0` is already a fixed convention in this module.

## Risks and mitigations

- Risk: none identified — purely additive, UI-registration-only option;
  does not touch OS-level network config, so it cannot destabilize the
  existing NetworkManager-based bridge creation.
- Users who already ran `just enable proxmox` and hit this bug need to
  rebuild (`nixos-rebuild switch`, user-initiated) to pick up the change;
  no data migration required.
