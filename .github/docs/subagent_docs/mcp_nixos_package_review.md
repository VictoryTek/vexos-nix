# mcp-nixos Package — Review

## Spec Compliance

Implementation matches spec exactly: one line added to `modules/development.nix`
under the existing `# ── AI tooling ──` section, immediately after
`pkgs.claude-code`. No other files touched.

```
+      pkgs.mcp-nixos # MCP server exposing NixOS/nixpkgs/home-manager option data to MCP-aware tools
```

## Static Checks (executed, results below)

| Check | Result |
|---|---|
| `git ls-files hardware-configuration.nix` | Empty output — not tracked. PASS |
| `system.stateVersion` in all 6 `configuration-*.nix` | All still `"25.11"`, unchanged. PASS |
| New flake inputs requiring `follows` | None added — N/A |
| Module Architecture Pattern (Option B) | Addition is a single package entry in the universal base file's existing unconditional list; no new `lib.mkIf` role/display/gaming guard introduced. PASS |
| Diff surface | `git diff --stat` shows exactly 1 file, 1 insertion. Matches "surgical change" requirement. PASS |

## Build Validation — BLOCKED (environment gap, not a build failure)

Could not execute the mandated build steps (`nix flake show --impure`,
`sudo nixos-rebuild dry-build --flake .#vexos-desktop-{amd,nvidia,vm}`) or
`scripts/preflight.sh`:

```
$ command -v nix; command -v nixos-rebuild
(both empty — neither binary exists in this shell)
```

This session is running in a Windows Git Bash shell, not on a NixOS host. This
matches `scripts/preflight.sh`'s own header comment: *"NOTE (Windows users): This
script must be made executable on the NixOS host."* There is no Nix installation
reachable from here to evaluate against — this is an environment limitation, not
an observed build failure, and I have not run these commands, so I am not
asserting a build result either way.

**I have not verified this change builds.** Given the change is a single-attribute
addition of a package already confirmed to exist in nixpkgs
(`mcp-nixos_package_spec.md`), the risk is low, but "low risk" is not the same as
"verified" and per project rules I will not report a build result I did not
observe.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | N/A — unverified | — |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | N/A | — |
| Consistency | 100% | A |
| Build Success | **Not executed (no Nix on this host)** | — |

**Overall: PASS on all static/reviewable criteria. Build Validation and Preflight
(Phase 6) cannot be executed from this machine and must be run on the NixOS host
before this is considered done, per CLAUDE.md ("Work is NOT complete until Phase 6
passes").**

## Returns

- **NEEDS_REFINEMENT is not applicable** — there is no failure to fix; the gate
  simply cannot run here.
- Recommended next action: user runs, on the actual NixOS host:
  ```
  nix flake show --impure
  sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
  sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
  sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
  bash scripts/preflight.sh
  ```
  If `pkgs.mcp-nixos` is not found in the pinned `nixpkgs` input, swap to
  `pkgs.unstable.mcp-nixos` in `modules/development.nix` (per the mitigation
  already documented in the spec).
