# Kill Switch DNS Leak Fix — Review

## Scope

- `modules/network-killswitch-stateless.nix` — reordered the chain (tunnel
  ACCEPTs moved above the new DNS guard), added `udp/tcp --dport 53 -j DROP`,
  removed the `TCP 443` bootstrap ACCEPT, rewrote the header comments.
- `modules/network-killswitch-service.nix` — identical reorder / addition /
  removal inside `startScript`.

## Findings

- **Spec compliance:** matches `killswitch_dns_leak_fix_spec.md` exactly.
- **Regression closed:** the LAN carve-out from `2ee1656` no longer covers the
  router's resolver, so it cannot act as a general-purpose public-name resolver.
- **Structural hole closed:** `TCP 443` to any destination removed from both
  files (verified: 0 occurrences in each module, 0 in the built start script).
- **Order dependence:** verified empirically, not just by reading — the
  evaluated ruleset was loaded into a private network namespace and the
  kernel's own `iptables -S` output confirms tunnel ACCEPTs precede the DNS
  guard, which precedes the LAN ACCEPTs.
- **Discovery preserved:** mDNS is UDP 5353 and multicast `224.0.0.0/4` is still
  ACCEPTed, so Avahi `_smb._tcp` browsing is untouched. No Samba/Avahi config
  was modified.
- **Module Architecture (Option B):** both files remain role/feature-addition
  modules with no `lib.mkIf` role guards. No new files, options, or conditionals.
- **Security:** no secrets, no world-writable files. Net effect is strictly more
  restrictive than before this change.

## Build Validation

| Check | Result |
|-------|--------|
| Chain loads in kernel (`unshare -rn`, real `iptables -S` readback) | PASS — order as designed |
| `TCP 443` present anywhere | 0 occurrences (both modules + built script) |
| `nix flake show --impure` | PASS (rc 0) |
| `nix eval …vexos-stateless-amd…toplevel.drvPath` | PASS |
| `nix eval …vexos-desktop-amd…toplevel.drvPath` | PASS |
| `nix eval …vexos-desktop-nvidia…toplevel.drvPath` | PASS |
| `nix eval …vexos-htpc-amd…toplevel.drvPath` | PASS |
| `nixpkgs-fmt --check` on the rewritten stateless module | PASS |
| `hardware-configuration.nix` tracked | No |
| `system.stateVersion` changed | No (25.11 throughout) |
| New flake inputs | None |
| `bash scripts/preflight.sh` | PASS (rc 0) |

(`sudo nixos-rebuild dry-build` unavailable in sandbox — "no new privileges";
per-target `nix eval` of `toplevel.drvPath` substituted, the CI-equivalent.)

## Residual Notes

- A LAN hostname that only resolves through the router's DNS is unreachable
  while the VPN is down. `.local` (mDNS) names and raw IPs are unaffected. This
  is inherent to closing the leak and is documented in the module header.
- OpenVPN in TCP-443 mode can no longer connect — deliberate and user-approved.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Verdict

PASS
