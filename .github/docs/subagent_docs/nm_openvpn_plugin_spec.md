---
feature: nm_openvpn_plugin
phase: 1-spec
date: 2026-06-13
---

# Spec: Add networkmanager-openvpn to all GNOME roles

## Current State

`modules/network.nix` enables NetworkManager (`networking.networkmanager.enable = true`)
for all roles. No OpenVPN NM plugin is installed anywhere in the repo, so `.ovpn` files
cannot be imported via GNOME Settings → VPN or `nmcli connection import`.

## Problem

Users on any GNOME-based role cannot import `.ovpn` configuration files through the
NetworkManager GUI or CLI because `networkmanager-openvpn` — the NM plugin that provides
OpenVPN support — is absent from the system.

## Affected Roles

All four roles that import `modules/gnome.nix`:
- `desktop`
- `server`
- `htpc`
- `stateless`

Non-GNOME roles (`headless-server`, `vanilla`) are NOT affected — NetworkManager is
present but OpenVPN GUI integration is not needed there.

## Proposed Solution

Add `networking.networkmanager.packages = [ pkgs.networkmanager-openvpn ];` to
`modules/gnome.nix`. This is the correct Option B placement:

- `modules/gnome.nix` is the universal GNOME base imported by all GNOME roles.
- Non-GNOME roles do not import it, so they are unaffected.
- No `lib.mkIf` guard is needed or permitted per the Module Architecture Pattern.
- No new flake input is required — `networkmanager-openvpn` is in nixpkgs stable.

## Implementation Steps

1. Edit `modules/gnome.nix`: add a `networking.networkmanager.packages` stanza inside
   the `config` block, after the Bluetooth section.

## Dependencies

- `pkgs.networkmanager-openvpn` — nixpkgs stable, no new flake input required.
- Context7 not required (internal nixpkgs package, no external API).

## Risks & Mitigations

- Risk: name collision if `networking.networkmanager.packages` is already set elsewhere.
  Mitigation: grepped all modules — the option is not set anywhere; safe to assign.
- Risk: `networkmanager-openvpn` package name wrong in current nixpkgs.
  Mitigation: verified via `nix flake show` dry-build in Phase 3.
