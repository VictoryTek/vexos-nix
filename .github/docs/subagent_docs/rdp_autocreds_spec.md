# RDP Auto-Credentials — VexOS Spec

## Current State

`modules/gnome.nix` enables GNOME Remote Desktop and opens port 3389 on all four display
roles. The user must still call `grdctl rdp enable` and `grdctl rdp set-credentials`
manually on every machine before the RDP server accepts connections.

## Problem Definition

Eliminate per-machine manual credential setup. After running one `just` recipe, the
RDP server should configure itself automatically on every GNOME session start — no further
action needed on rebuild, reboot, or role switch.

## Scope

Roles receiving auto-credential setup: **desktop, server, htpc**
Excluded: **stateless** — home directory is on a tmpfs root; GNOME Keyring state
(where grdctl stores credentials) is ephemeral and does not survive reboots. There is no
persistent location to store the password file on stateless without extra impermanence
configuration.
Excluded: **headless-server, vanilla** — no GNOME session; grdctl is meaningless.

## Solution

### Component 1 — `modules/remote-desktop.nix` (new)

A NixOS module that declares:

**Option:**
```
vexos.remoteDesktop.passwordFile (str)
  default: "/etc/nixos/secrets/rdp-password"
```

The default path is created by `just setup-rdp`. No Nix-store exposure — the file lives
on the local filesystem only.

**Config (unconditional):**
```nix
systemd.user.services.vexos-rdp-setup = {
  wantedBy = [ "graphical-session.target" ];
  after    = [ "graphical-session.target" ];
  partOf   = [ "graphical-session.target" ];
  path     = [ pkgs.gnome-remote-desktop ];
  script   = ''
    if [ ! -f <passwordFile> ]; then exit 0; fi
    password=$(cat <passwordFile>)
    grdctl rdp enable
    grdctl rdp set-credentials <username> "$password"
  '';
  serviceConfig.Type = "oneshot";
  serviceConfig.RemainAfterExit = true;
};
```

The service is unconditional — no `lib.mkIf` guard needed. When the password file is
absent the script exits 0 silently (not-yet-configured state). When present it calls
grdctl idempotently on every GNOME session start, keeping credentials in sync if the
file changes.

`config.vexos.user.name` supplies the username automatically.

No `lib.mkIf` guards gating by role — the module is only imported by the three
configuration files that need it (Option B pattern: import list = role membership).

### Component 2 — Import in three configuration files

Add `./modules/remote-desktop.nix` to the imports list of:
- `configuration-desktop.nix` — under the existing GNOME/flatpak imports
- `configuration-server.nix` — same location
- `configuration-htpc.nix` — same location

`configuration-stateless.nix` is **not** modified.

### Component 3 — `justfile` recipe `setup-rdp`

```
setup-rdp
```

Interactive recipe that:
1. Prompts for password (silent input, confirmed twice)
2. Creates `/etc/nixos/secrets/` (0700 root:root) if absent
3. Writes password to `/etc/nixos/secrets/rdp-password` (0600 root:root)
   using `printf '%s'` — no trailing newline, to avoid grdctl receiving `password\n`
4. Prints a rebuild reminder

No role guard — the recipe works on any VexOS machine. Writing the file on a stateless
machine is harmless (the NixOS module is not imported there).

## Security Properties

| Property | Status |
|----------|--------|
| Plaintext in Nix store | ✗ Never — file is on local filesystem only |
| File permissions | ✓ 0600 root:root |
| Directory permissions | ✓ 0700 root:root |
| Exposed in `nix show-config` | ✗ No — not a Nix option value |
| Keyring storage | ✓ grdctl stores in GNOME Keyring (libsecret), unlocked at login |

## Files Modified

| File | Change |
|------|--------|
| `modules/remote-desktop.nix` | New module |
| `configuration-desktop.nix` | Add import |
| `configuration-server.nix` | Add import |
| `configuration-htpc.nix` | Add import |
| `justfile` | Add `setup-rdp` recipe |

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| grdctl fails if GNOME Keyring is locked at service start | Service runs after `graphical-session.target`; keyring is auto-unlocked by GDM PAM on login (including auto-login) |
| Password file absent after nixos-rebuild on a new machine | Service exits 0 silently — no error, no broken unit; user runs `just setup-rdp` once |
| Server role has no display by default | Server role imports gnome.nix (GDM + GNOME session enabled) — grdctl is valid there |
| stateless: grdctl credentials lost on reboot | Excluded from scope; stateless users must configure grdctl manually if desired |
