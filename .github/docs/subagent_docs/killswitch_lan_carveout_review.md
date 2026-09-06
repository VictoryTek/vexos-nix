# Kill Switch LAN Carve-Out — Review

## Scope

- `modules/network-killswitch-stateless.nix` — added RFC1918 / link-local /
  multicast ACCEPT rules to the `vpn-kill-switch` chain; rewrote the header
  "DNS leaks" comment to document the LAN carve-out and its trade-off.
- `modules/network-killswitch-service.nix` — added the same 5 ACCEPT rules to
  `startScript` (toggleable kill switch, desktop + htpc).

## Findings

- **Spec compliance:** matches `killswitch_lan_carveout_spec.md` exactly.
- **Rule placement:** rules sit after ESTABLISHED/RELATED and DHCP, before the
  VPN bootstrap block and well before the terminal `DROP` — effective.
- **Module Architecture (Option B):** both files are feature-addition modules
  imported only by the relevant roles; no `lib.mkIf` role guards added; no new
  options, files, or conditionals. Compliant.
- **Security:** only local-scope destinations (RFC1918, 169.254/16, 224/4) are
  permitted — no routable public IP is reachable. LAN-resolver DNS while VPN is
  down is documented in-file as the accepted "allow LAN" trade-off. No secrets,
  no world-writable files.
- **Surgical:** pre-existing nixpkgs-fmt drift in `network-killswitch-service.nix`
  left untouched; diff vs HEAD (both normalised) is exactly the 7 added lines.
  `network-killswitch-stateless.nix` passes `nixpkgs-fmt --check`.
- **`stopScript` / `extraStopCommands`:** unchanged — they flush and delete the
  whole chain, so no teardown edit needed.

## Build Validation

| Check | Result |
|-------|--------|
| `nix flake show --impure` | PASS (rc 0) |
| `nix eval …vexos-stateless-amd…toplevel.drvPath` | PASS — drv produced |
| `nix eval …vexos-desktop-nvidia…toplevel.drvPath` | PASS — drv produced |
| `nix eval …vexos-htpc-amd…toplevel.drvPath` | PASS — drv produced |
| `hardware-configuration.nix` tracked | No |
| `system.stateVersion` changed | No |
| New flake inputs | None |
| `bash scripts/preflight.sh` | PASS (rc 0) |

(`sudo nixos-rebuild dry-build` unavailable in this sandbox — "no new privileges";
substituted per-target `nix eval` of `toplevel.drvPath`, the CI-equivalent full
evaluation.)

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 95% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Verdict

PASS
