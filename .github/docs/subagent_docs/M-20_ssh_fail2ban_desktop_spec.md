# M-20 — SSH password auth + open port 22 + GNOME auto-login, no fail2ban on non-server roles

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-20 (BUGS M19) · `modules/network.nix:156-175`, `modules/gnome.nix:126-130`

**User constraint (explicit, from a prior session): SSH password authentication must
stay enabled.** The user previously tried key-only auth and deliberately reverted to
password auth because they prefer it. The MASTER_PLAN's second suggested fix
(`PasswordAuthentication = false`) is therefore off the table for this pass —
proceeding with the fail2ban option only.

## Current State

`modules/network.nix` (imported by desktop, server, stateless, htpc, headless-server —
confirmed by grep; vanilla doesn't import it and has no SSH server at all) enables
`services.openssh` with password auth left at its default (enabled, intentionally, per
the module's own comment) and no fail2ban anywhere in that file.

Server and headless-server roles already have brute-force protection via
`modules/security-server.nix`'s `services.fail2ban` block (added under a prior item,
H-05) — confirmed by reading that file in full. Desktop, htpc, and stateless import
`modules/network.nix` (hence get password-auth SSH on an open port) but never import
`modules/security-server.nix` (server-only, per its own header comment) — so those
three roles are the ones actually missing fail2ban.

Separately confirmed: `networking.firewall.allowedTCPPorts = [ 22 ];` in
`modules/network.nix:174` is genuinely redundant — verified against the pinned nixpkgs
`sshd.nix` that `services.openssh.openFirewall` defaults to `true`, which already does
`networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall cfg.ports;`
(i.e., opens 22 automatically whenever `services.openssh.enable = true`, with no
`openFirewall = false` override present anywhere in this repo).

`modules/gnome.nix`'s unconditional `services.displayManager.autoLogin.enable = true`
is real compounding context (physical console access bypasses login entirely) but
disabling auto-login is a separate, larger UX decision not requested by this item or
the user — out of scope for this pass.

## Problem Definition

Add SSH brute-force protection to the three roles that currently lack it, without
touching password authentication; remove the redundant firewall line.

## Proposed Solution

New role-addition module `modules/security-desktop.nix` (Option B pattern, matching
`security-server.nix`'s own structure and header-comment convention), containing just
the `services.fail2ban` block from `security-server.nix` (sshd jail auto-enabled by
NixOS whenever both `fail2ban` and `openssh` are enabled, plus the recidive jail for
repeat offenders) — no auditd (that's a server-specific addition for a different
reason, out of scope here). Imported by `configuration-desktop.nix`,
`configuration-htpc.nix`, `configuration-stateless.nix`.

`modules/network.nix` — remove the redundant `networking.firewall.allowedTCPPorts =
[ 22 ];` line.

## Implementation Steps

1. `modules/security-desktop.nix` (new) — fail2ban block, matching
   `security-server.nix`'s exact settings (maxretry 5, bantime 1h, recidive jail).
2. `configuration-desktop.nix`, `configuration-htpc.nix`, `configuration-stateless.nix`
   — import the new module.
3. `modules/network.nix` — remove the redundant `allowedTCPPorts = [ 22 ]` line.

## Configuration Changes

None to `flake.nix`.

## Risks and Mitigations

- **PasswordAuthentication unchanged** — explicit user constraint, verified no line in
  this change touches it.
- **Redundant port line removal must not actually remove SSH's firewall access** —
  verified by evaluating the merged `networking.firewall.allowedTCPPorts` before/after
  to confirm 22 is still present (supplied by `openssh.openFirewall`, not the module).
- **fail2ban duplicate/conflict with server roles** — n/a, the new module is only
  imported by the three roles that don't already have `security-server.nix`.
