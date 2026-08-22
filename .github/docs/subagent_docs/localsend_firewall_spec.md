# LocalSend Firewall Fix — Spec

## Current State Analysis

- `localsend` package is installed via [modules/packages-desktop.nix:14](../../../modules/packages-desktop.nix#L14),
  imported (directly or via home-*.nix) by all display roles: `desktop`, `stateless`,
  `server`, `htpc`.
- `modules/network-desktop.nix` is the existing role-addition module for
  "any configuration with a display" networking concerns (SMB/NFS/WSD discovery via
  Avahi/samba-wsdd). It is imported by exactly the same four role configs:
  `configuration-desktop.nix`, `configuration-stateless.nix`, `configuration-htpc.nix`,
  `configuration-server.nix`.
- `networking.firewall.enable = true` is set globally in `modules/network.nix`
  with no LocalSend exception anywhere in the repo (confirmed via grep — no
  reference to `53317` or `localsend` firewall rule exists).
- Every other LAN-discovery service in this repo (Avahi publish, samba-wsdd) opens
  its own explicit firewall rule; LocalSend has none, so discovery broadcasts between
  the iPhone app and this host are silently dropped by the default-deny firewall.

## Problem Definition

LocalSend cannot discover peers on the LAN (iPhone ↔ laptop) because the firewall
blocks both:
- **UDP 53317** — used for multicast/broadcast peer discovery
- **TCP 53317** — used for the actual HTTP-based file transfer

## Proposed Solution

Open TCP+UDP port 53317 in the firewall, scoped to the same role set that already
has LocalSend installed and already has `network-desktop.nix` imported. No new
module file is needed — this is a small, permanent addition to the existing
display-role networking module, consistent with Option B (role-addition file,
no `lib.mkIf` role-gating inside).

## Implementation Steps

1. Edit `modules/network-desktop.nix`:
   - Add a new section (mirroring the existing WS-Discovery section's comment style)
     opening:
     ```nix
     networking.firewall.allowedTCPPorts = [ 53317 ];
     networking.firewall.allowedUDPPorts = [ 53317 ];
     ```
   - Document why (LocalSend LAN discovery + transfer) with a short comment,
     consistent with existing commenting style in the file.

No other files need changes — this module is already scoped to exactly the roles
where `localsend` is installed.

## Dependencies

None. `networking.firewall.allowedTCPPorts` / `allowedUDPPorts` are core NixOS
options; LocalSend itself is already packaged via nixpkgs (`pkgs.localsend`), no
new external library or Context7 lookup required (no new dependency, per the
Dependency Policy's "Context7 NOT required" carve-out — internal firewall config
change only).

## Configuration Changes

- `modules/network-desktop.nix`: add `networking.firewall.allowedTCPPorts`/`allowedUDPPorts`
  for port 53317.

## Risks and Mitigations

- **Risk:** Opening a port broadens attack surface.
  **Mitigation:** Port 53317 is only reachable on the LAN (no NAT/port-forward
  involved), and is scoped to display roles only (not `headless-server`, not
  `vanilla`), consistent with where LocalSend is actually used.
- **Risk:** Conflict with existing firewall rules.
  **Mitigation:** `allowedTCPPorts`/`allowedUDPPorts` lists merge across modules
  in NixOS (list-type option), so no conflict with other modules setting the same
  options elsewhere.
