---
name: localsend-desktop-server
description: Add localsend to GUI display roles via packages-desktop.nix
metadata:
  type: project
---

# Spec: Add LocalSend to Desktop and GUI Server Roles

## Current State

`modules/packages-desktop.nix` is the shared GUI packages module imported by all four
display-server roles: `desktop`, `server`, `htpc`, `stateless`. It currently contains:
`brave`, `gparted`, `jdk21`, `mpv`.

## Problem

`localsend` (open-source cross-platform AirDrop alternative) is not installed on any role.
The user wants it available on desktop and GUI server.

## Proposed Solution

Add `localsend` to `modules/packages-desktop.nix`.

**Why this file:** It is already the canonical home for GUI packages shared across display
roles. Both `configuration-desktop.nix` and `configuration-server.nix` import it. Adding
here avoids duplicating an `environment.systemPackages` entry across two configuration
files, which would violate the Module Architecture Pattern (Option B).

**Side-effect:** `htpc` and `stateless` also import `packages-desktop.nix`, so they will
also receive `localsend`. This is consistent with the file's stated scope ("GUI packages
for roles with a display server") and is a net benefit rather than a concern — LocalSend
is a general-purpose file-sharing utility appropriate on any display role.

## Package Availability

- Package name: `localsend`
- Nixpkgs stable: version 1.17.0 (confirmed via `nix search nixpkgs localsend`)
- No unstable overlay required

## Implementation Steps

1. Edit `modules/packages-desktop.nix` — append `localsend` to `environment.systemPackages`

## Risks and Mitigations

- None: `localsend` is in stable nixpkgs, has no known conflicts, and adds ~50MB to the closure.
