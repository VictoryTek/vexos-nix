# Remote Desktop — Bidirectional Spec

## Current State Analysis

The original remote desktop feature (`remote_desktop_spec.md`) enabled the **receive** side
only: `services.gnome.gnome-remote-desktop.enable = true` + `networking.firewall.allowedTCPPorts = [ 3389 ]`
were added to `modules/gnome.nix`. This covers four roles: `desktop`, `htpc`, `stateless`, `server`.

**Gaps identified:**

| Gap | Detail |
|-----|--------|
| No RDP client on any role | `gnome-connections` is in `environment.gnome.excludePackages`; no other client installed |
| `vanilla` role missing entirely | Does not import `gnome.nix`; has no remote desktop service declaration, no port 3389 open, no client |

## Problem Definition

Every role with a DE should be able to:
1. **Receive** incoming RDP connections (already done for gnome.nix roles; missing for vanilla)
2. **Send** outgoing RDP connections to other machines (missing for all roles)

## Roles With a DE

| Role | DE | Imports gnome.nix | Receive configured | Client installed |
|------|----|-------------------|--------------------|-----------------|
| desktop | GNOME | ✅ | ✅ | ❌ |
| htpc | GNOME | ✅ | ✅ | ❌ |
| stateless | GNOME | ✅ | ✅ | ❌ |
| server | GNOME | ✅ | ✅ | ❌ |
| vanilla | GNOME | ❌ | ❌ | ❌ |
| headless-server | none | ❌ | n/a | n/a |

## Proposed Solution

### Client: Remmina

Add `pkgs.remmina` to `environment.systemPackages` in `modules/gnome.nix`. This covers
`desktop`, `htpc`, `stateless`, `server` in one change.

Remmina supports RDP, VNC, SSH, and SPICE. It is in nixpkgs stable and works under
Wayland via XWayland. `gnome-connections` remains excluded — it is strictly less capable.

### Vanilla: Full remote desktop stack

`configuration-vanilla.nix` has `services.desktopManager.gnome.enable = true`, which
causes NixOS upstream to set `services.gnome.gnome-remote-desktop.enable = lib.mkDefault true`.
The service is therefore already enabled by default. However:
- Port 3389 is **not** opened in the firewall
- No RDP client is installed

Add to `configuration-vanilla.nix`:
1. `services.gnome.gnome-remote-desktop.enable = true;` — explicit declaration for clarity
2. `networking.firewall.allowedTCPPorts = [ 3389 ];` — open RDP port
3. `environment.systemPackages = [ pkgs.remmina ];` — RDP client

## Implementation Steps

### Step 1 — `modules/gnome.nix`

Add `pkgs.remmina` to the existing `environment.systemPackages` list.

### Step 2 — `configuration-vanilla.nix`

Add a `# ── Remote Desktop ──` block with the three lines above, placed after the
audio block (near line 42) and before the dconf theme block.

## Files Modified

| File | Change |
|------|--------|
| `modules/gnome.nix` | Add `pkgs.remmina` to `environment.systemPackages` |
| `configuration-vanilla.nix` | Add service declaration, port 3389, Remmina |

## Dependencies

No new flake inputs. `pkgs.remmina` is in nixpkgs stable. No Context7 lookup required.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Remmina pulls in large GTK dependency tree | Acceptable on DE roles; these are full workstation installs |
| Port 3389 open on vanilla (minimal role) | Vanilla is intentionally a restore baseline; GNOME Remote Desktop requires explicit credential setup by the user — no anonymous access |
