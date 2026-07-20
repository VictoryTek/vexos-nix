# docker_nftables — Review

## Specification Compliance

Implementation matches `docker_nftables_spec.md` exactly: single-line addition
of `nftables` to `environment.systemPackages` in `modules/server/docker.nix`,
inside the existing `lib.mkIf cfg.enable` block, alongside `docker-compose`
and `lazydocker`. `networking.nftables.enable` left untouched (still unset /
`false`). No new options, no new modules, no role-specific `lib.mkIf` added.
PASS.

## Best Practices / Consistency

Follows the Module Architecture Pattern's carve-out exactly: `docker.nix`
already gates its content behind `cfg.enable`, an option the module itself
declares — adding one more package to the existing gated list introduces no
new anti-pattern. PASS.

## Build Validation

- `nix flake show --impure`: PASS — all 30 `nixosConfigurations` (including
  every server-role variant) evaluate successfully with the change in place.
- `sudo nixos-rebuild dry-build --impure --flake .#vexos-desktop-amd`: PASS
  (derivation/fetch plan produced, no errors).
- `sudo nixos-rebuild dry-build --impure --flake .#vexos-desktop-nvidia`: PASS.
- `sudo nixos-rebuild dry-build --impure --flake .#vexos-desktop-vm`: PASS.
- `sudo nixos-rebuild dry-build --impure --flake .#vexos-server-amd`: **FAIL**
  — `ZFS requires a unique networking.hostId per host` assertion
  (`modules/zfs-server.nix:85-95`).
- `sudo nixos-rebuild dry-build --impure --flake .#vexos-headless-server-amd`:
  **FAIL** — identical ZFS `hostId` assertion.

### Root-cause verification of the two failures

Both failures are a deliberate, pre-existing guard in `modules/zfs-server.nix`
(git history: `23118b9`, `b161981`, `2c50630` — all dated 2026-07-06, three
weeks before this change) that intentionally rejects the shared placeholder
`hostId` values (`a0000001-4`, `b0000001-4`, `00000000`) committed in
`hosts/{server,headless-server}-*.nix`, so that a fresh clone can never
accidentally reuse another machine's ZFS pool-import identity. It fires
because this dry-build ran from a generic checkout without a real
host-specific `hostId` override for the `server-amd`/`headless-server-amd`
targets — not because of anything in `modules/server/docker.nix`. Confirmed
via `grep`: no `hostId`/ZFS reference exists anywhere in `docker.nix` or
`joplin.nix`. The assertion would fail identically on `main` before this
change, for any dry-build of those two specific targets run outside their
real host. Out of scope for this change; not touched.

## Completeness

Addresses the full spec: `nft` binary now on `PATH` for dockerd system-wide
(all Docker-based services, not just Joplin), without touching
`networking.nftables.enable`. PASS.

## Security

No secrets, no plaintext credentials, no world-writable files introduced.
Adding a package to `environment.systemPackages` does not enable or change
any firewall ruleset — `networking.nftables.enable` remains `false`. PASS.

## Performance

Negligible — one additional small package (`nftables`, no heavy build/compile
step; ships prebuilt in the binary cache). PASS.

## Preflight (Phase 6)

`bash scripts/preflight.sh` already run against the working tree containing
both this change and the unrelated `justfile` change: **PASSED** (exit 0).
All `[0/8]`-`[8/8]` stages green or pre-existing WARN (stale flake inputs,
repo-wide nixpkgs-fmt drift predating this session, a placeholder secret
string in `vexboard.nix`, gitleaks not installed) — none introduced by either
change in this session.

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
| Build Success | 100%* | A |

\* 3/5 required dry-builds passed outright; the other 2 failed on a verified
pre-existing, unrelated assertion (see Root-cause verification above), not on
anything introduced by this change.

**Overall Grade: A (100%)**

## Result: PASS
