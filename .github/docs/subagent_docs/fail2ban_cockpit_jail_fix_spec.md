# fail2ban_cockpit_jail_fix — Specification

## Current State

`modules/security-server.nix` configures fail2ban with two jails:
- `recidive` — escalating ban for repeat offenders (works correctly)
- `cockpit` — references `filter = cockpit` which does not exist in nixpkgs or
  fail2ban's default filter library

On service start, fail2ban cannot resolve the `cockpit` filter and refuses to start,
which means the `sshd` and `recidive` jails also never load. All server roles have
zero brute-force protection despite fail2ban being enabled.

## Problem

There is no built-in `cockpit` filter in nixpkgs. Writing a custom filter was
researched but is not viable: Cockpit's PAM authentication logs do not include the
remote client IP address (`rhost=` is empty — upstream bug open since 2014, issues
#722 and #15760 in cockpit-project/cockpit). Without the IP, fail2ban cannot ban
anyone, making the jail security theatre regardless of the filter.

## Proposed Solution

Remove the `jails.cockpit` block from `services.fail2ban` entirely.

Result:
- fail2ban starts cleanly on all server roles
- SSH (`sshd`) and recidive jails load and function correctly
- No false impression of Cockpit protection
- Header comment updated to remove the Cockpit claim

## Files Modified

- `modules/security-server.nix`

## Risks

None. The cockpit jail was non-functional (causing a crash). Removing it restores
correct fail2ban operation. The cockpit jail can be re-added if upstream resolves
the IP logging issue.
