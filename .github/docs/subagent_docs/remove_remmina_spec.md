# Remove Remmina Spec

## Current State Analysis

`pkgs.remmina` (RDP/VNC client) is installed in two places:

1. `modules/gnome.nix:240` — universal GNOME base module, imported by every
   role (desktop, server, htpc, stateless, vanilla via their
   `configuration-*.nix` files). This is the primary system-wide install.
2. `configuration-vanilla.nix:88` — vanilla role's own
   `environment.systemPackages = [ pkgs.remmina ];`, a second, independent
   install specific to the vanilla role.

`pkgs.moonlight-qt` is already installed alongside remmina in
`modules/gnome.nix:243`, with the comment "connect to other machines'
Sunshine hosts (modules/sunshine.nix)" — confirming Sunshine/Moonlight is
the already-adopted replacement remote-desktop stack.

`modules/remote-desktop.nix:50` contains a comment mentioning "Remmina,
mstsc" as generic illustrative examples of RDP clients in a note about GNOME
Remote Desktop's TLS cert requirement. This is not a package reference and
does not name Remmina as the project's chosen client — it's incidental
prose. Out of scope per the Surgical Changes principle.

No other `.nix` file references `remmina`.

## Problem Definition

The project has standardized on Sunshine (host) + Moonlight (client) for
remote desktop/streaming and no longer wants Remmina installed.

## Proposed Solution

Remove the two `pkgs.remmina` package references:
- `modules/gnome.nix:240` (and its now-orphaned "RDP/VNC client" comment
  header at line 239, since moonlight-qt already has its own comment below)
- `configuration-vanilla.nix:87-88` (comment + package line)

No replacement needed in `configuration-vanilla.nix` — `modules/gnome.nix`
already provides `pkgs.moonlight-qt` to every role including vanilla, so
vanilla isn't left without a remote-desktop client.

## Implementation Steps

1. `modules/gnome.nix`: delete line 240 (`pkgs.remmina`) and its comment
   header line 239 (`# RDP/VNC client — connect to other machines`).
2. `configuration-vanilla.nix`: delete lines 87-88 (comment + package).
3. Leave `modules/remote-desktop.nix:50` untouched (illustrative comment,
   not a package reference).

This follows the Module Architecture Pattern trivially — no `lib.mkIf`
guards involved, just deleting package list entries from an existing
universal base file and a role file's own package list.

## Dependencies

None — pure removal, no new packages or libraries. Context7 not applicable.

## Configuration Changes

None beyond the package list edits above.

## Risks and Mitigations

- Risk: vanilla role loses a remote-desktop *client* capability.
  Mitigation: `pkgs.moonlight-qt` is already provided to all roles via
  `modules/gnome.nix`, so vanilla retains a client (for Sunshine hosts).
- Risk: none to receive-side RDP (GNOME Remote Desktop / grd) — that is
  unaffected; only the outbound client package is removed.
