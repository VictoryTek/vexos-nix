# Remote Desktop — VexOS Spec

## Current State Analysis

VexOS ships `com.rustdesk.RustDesk` as a Flatpak in `modules/flatpak.nix` `defaultApps`
(installed on all display roles). A separate `modules/server/rustdesk.nix` provides an
opt-in self-hosted RustDesk relay/signal server — unrelated to the client and unaffected
by this change.

**Problem:** RustDesk's host (screen-sharing) path does not work reliably on Wayland.
It requires either X11 or kernel-level DRM/KMS capture; neither is available in a GNOME
Wayland session. Every VexOS display role (desktop, server, htpc, stateless) runs GNOME
on Wayland exclusively. The client cannot receive incoming remote desktop connections.

## Problem Definition

Replace the broken RustDesk Flatpak client with a Wayland-native remote desktop solution
that works out-of-the-box on every VexOS display role.

## Solution: GNOME Remote Desktop (RDP over PipeWire)

### Why GNOME Remote Desktop

- **Wayland-native:** uses the PipeWire screen-cast portal (`xdg-desktop-portal-gnome`),
  already enabled in `modules/gnome.nix` — no extra plumbing needed
- **Built into GNOME:** `gnome-remote-desktop` 50.1 ships in nixpkgs stable; the
  NixOS GNOME module already sets
  `services.gnome.gnome-remote-desktop.enable = lib.mkDefault true` at line 383 of
  `nixos/modules/services/desktop-managers/gnome.nix`
- **Standard protocol:** exposes an RDP endpoint (port 3389 TCP); any standard RDP
  client works — Windows built-in Remote Desktop, Remmina on Linux, Microsoft RD on
  macOS/iOS/Android. No proprietary client required.
- **User-managed credentials:** the user enables sharing and sets a PIN/password in
  GNOME Settings → System → Remote Desktop. Credentials are stored in GNOME Keyring
  (libsecret) and are never committed to the Nix store.

### Why Not the Alternatives

| Option | Reason rejected |
|--------|----------------|
| wayvnc | wlroots-only — incompatible with GNOME compositor |
| xrdp | X11-based — incompatible with Wayland-only sessions |
| Sunshine | Moonlight-protocol streaming host; requires proprietary client; designed for game streaming, not general remote desktop |
| RustDesk (keep) | Host path broken on GNOME Wayland |

## Scope

Display roles (import `gnome.nix` and `network-desktop.nix`): **desktop, server, htpc, stateless**
Excluded: **headless-server** (no display, does not import `gnome.nix`)

The self-hosted RustDesk relay server (`modules/server/rustdesk.nix`) is unrelated to
the client Flatpak and is **not touched**.

## Implementation Steps

### Step 1 — `modules/flatpak.nix`

Remove `"com.rustdesk.RustDesk"` from `defaultApps`.

No stamp-file or exclude-list entry is required: the existing `flatpak-install-apps`
service already uninstalls excluded/removed apps when the hash changes.

### Step 2 — `modules/gnome.nix`

Two additions to the `config` block:

1. **Explicit service declaration:**
   ```nix
   services.gnome.gnome-remote-desktop.enable = true;
   ```
   The NixOS GNOME module already sets this via `mkDefault true`, so this is a
   documentation-level change that makes the intent explicit and guards against a future
   upstream change removing the default.

2. **Firewall port:**
   ```nix
   networking.firewall.allowedTCPPorts = [ 3389 ];
   ```
   Port 3389 is the standard RDP port. `gnome.nix` is the correct location because:
   - All four display roles import it; headless-server does not
   - The port and the service enabling are co-located

## Files Modified

| File | Change |
|------|--------|
| `modules/flatpak.nix` | Remove `"com.rustdesk.RustDesk"` from `defaultApps` |
| `modules/gnome.nix` | Add `services.gnome.gnome-remote-desktop.enable = true` + `networking.firewall.allowedTCPPorts = [ 3389 ]` |

## Files NOT Modified

| File | Reason |
|------|--------|
| `modules/server/rustdesk.nix` | Self-hosted relay server — unrelated to the client Flatpak |
| `modules/network-desktop.nix` | Firewall port belongs in `gnome.nix` next to the service |
| Any `configuration-*.nix` | No role-level changes needed; gnome.nix covers all four display roles |

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Existing RustDesk installs linger on live machines | `flatpak-install-apps` service removes apps no longer in the list when the hash stamp changes — automatic on next `nixos-rebuild switch` |
| Users lose remote access tooling entirely | GNOME Remote Desktop is a strict upgrade: Wayland-native, standard protocol, no proprietary dependency |
| Port 3389 exposed on server role | Already has Fail2ban + SSH hardening via `security-server.nix`; RDP requires explicit credential setup by the user in GNOME Settings — no anonymous access |
| VNC port (5900) not opened | GNOME Remote Desktop also supports VNC but VNC is unencrypted and not opened by default. RDP is the recommended protocol. |

## User Setup (Post-Deploy)

After `nixos-rebuild switch`:
1. Open **GNOME Settings → System → Remote Desktop**
2. Toggle **Remote Desktop** on
3. Set a username and password (stored in GNOME Keyring)
4. Connect from any RDP client to `<hostname-or-ip>:3389`
