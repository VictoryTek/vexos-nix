# Spec: Fix audit-rules-nixos.service failure — remove non-existent /etc/apparmor.d/ watch

## Current State Analysis

`modules/security-server.nix` sets `security.audit.rules` with the following rule as the
first entry:

```nix
"-w /etc/apparmor.d/ -p wa -k apparmor_policy"
```

`auditctl` requires the watched path to exist at rule-load time. On NixOS, AppArmor does
NOT use `/etc/apparmor.d/` — profiles are compiled and loaded directly from the Nix store
(`/nix/store/…`). The directory `/etc/apparmor.d/` is never created by NixOS, so it does
not exist on the running host.

## Problem Definition

`audit-rules-nixos.service` fails on every boot with:

```
auditctl: There was an error in line 2 of <store-path>/audit.rules
```

Line 2 corresponds to the `-w /etc/apparmor.d/` watch rule. Because this is the first
rule in the list and the load fails, `auditctl` exits non-zero, the service enters
`failed` state, and `nixos-rebuild switch` exits with code 4.

## Root Cause

`-w /path` watch rules in `auditctl` fail immediately if the path does not exist. Unlike
syscall rules (`-a always,exit`), inotify-based watch rules have no "ignore if missing"
semantics. `/etc/apparmor.d/` is a Debian/Ubuntu convention; NixOS AppArmor exclusively
uses the Nix store for profile artifacts.

## Proposed Solution

Remove the single offending rule from `modules/security-server.nix`. The remaining six
rules in the list are all syscall-based (`-a always,exit`) or watch paths that do exist
(`/etc/sudoers`, `/etc/ssh/sshd_config`) and will continue to load correctly.

No replacement rule is needed — AppArmor policy changes on NixOS are tracked at the
flake/git level, not via a file-watch audit rule.

## Implementation Steps

1. In `modules/security-server.nix`, remove the line:
   ```nix
   "-w /etc/apparmor.d/ -p wa -k apparmor_policy"
   ```
   from the `security.audit.rules` list.
2. Leave all other rules unchanged.
3. Validate: `nix flake show --impure` passes.
4. Validate: `sudo nixos-rebuild dry-build --flake .#vexos-server-intel` passes.

## Files Affected

- `modules/security-server.nix`

## Dependencies

None. Internal Nix change only. Context7 not required.

## Risks and Mitigations

- **Risk:** Loss of AppArmor policy-change audit trail.
  **Mitigation:** None needed — NixOS AppArmor profiles are immutable Nix store artifacts.
  Changes are tracked by flake.lock / git history, not by auditctl watches. The rule
  provided no real audit coverage on NixOS.
- **Risk:** Other watch rules (`/etc/sudoers`, `/etc/ssh/sshd_config`) might also be
  absent.
  **Mitigation:** Both paths are created by NixOS at activation time. Verified present on
  the target host before committing this fix.
