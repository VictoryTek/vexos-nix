---
feature: killswitch_dns_bootstrap_fix
phase: 3-review
date: 2026-09-07
---

# Review: Fix VPN Kill Switch DNS Bootstrap Deadlock

## 1. Specification Compliance

All three implementation steps from §4 of the spec were applied exactly as designed:

- `modules/network.nix`: `vexos.network.forceFixedDns` option added; new
  `ensureProfiles.profiles` mkMerge entry adds `ipv4.ignore-auto-dns` /
  `ipv4.dns` keys to the existing `"wired-fallback"` profile without touching
  its `ipv4.method` key (verified no leaf-key collision — see §3 Consistency).
- `modules/network-killswitch-stateless.nix`: `forceFixedDns = true;` set;
  four fixed-resolver ACCEPT rules inserted between the tunnel-interface
  ACCEPTs and the DNS guard DROP (order matches the file's own "RULE ORDER IS
  LOAD-BEARING" requirement); header comment updated to describe the new
  exception.
- `modules/network-killswitch-service.nix`: same four ACCEPT rules mirrored
  into `startScript`, with no DNS-option wiring, and a comment explaining why
  (matches spec §3c / §5 Risks exactly).
- `configuration-stateless.nix` left untouched, as specified.

**Verdict: full compliance.**

## 2. Best Practices (Nix / NixOS / nixpkgs)

- New option follows existing project convention (`vexos.network.*` namespace,
  `lib.mkOption` with `type`/`default`/`description`).
- `lib.mkIf config.vexos.network.forceFixedDns` in `network.nix` gates a block
  by an option **that same module declares** — the explicit CLAUDE.md carve-out
  for toggleable-subsystem guards, not the role-smuggling anti-pattern.
- iptables additions follow the exact style of neighboring rules in both files
  (same flag ordering, same comment-block convention).

## 3. Consistency (Module Architecture Pattern — Option B)

- `modules/network.nix` is the universal base; the new option defaults to
  `false` and is a no-op for every role except stateless. No role/display/gaming
  `lib.mkIf` was added to it — the only `mkIf` added is the same-module carve-out.
- `modules/network-killswitch-stateless.nix` (role addition, stateless-only)
  sets the option to `true` — the "addition file expresses its role through
  content" pattern, unchanged from how the file already worked.
- `modules/network-killswitch-service.nix` (desktop/htpc addition) deliberately
  does **not** set the option, preserving the toggle's default-off behavior on
  those roles. This was the main design risk identified in Phase 1 and is
  correctly resolved in the diff — confirmed by re-reading the applied patch.
- Confirmed via `mcp__nixos__nix` option lookup that
  `ensureProfiles.profiles` is an attrs-of-INI-section type, so the new
  `mkMerge` entry merges its `ipv4.{ignore-auto-dns,dns}` keys into the
  existing `"wired-fallback".ipv4` section (which only sets `method`) with no
  conflicting-definition error — the mechanism the spec relies on is real, not
  assumed.

## 4. Maintainability

Every new block carries a comment explaining *why*, cross-referencing the
sibling file/option responsible (`network.nix` ↔ `network-killswitch-stateless.nix`),
consistent with the existing file headers' heavily-annotated style.

## 5. Completeness

Addresses all 6 requirements in spec §2:
1. Bootstrap DNS resolution now possible on stateless. ✅
2. Allowance scoped to exactly two fixed non-LAN IPs. ✅
3. `forceFixedDns` makes the allowance actually used (the specific defect in
   the unimplemented July spec). ✅
4. Stateless kill switch remains always-on; no new toggle introduced there. ✅
5. `network-killswitch-service.nix` mirrors the firewall rules; DNS override
   explicitly and correctly scoped out with rationale. ✅
6. No new flake inputs or packages — confirmed via `git diff --stat -- flake.nix flake.lock` (empty). ✅

## 6. Performance

Four additional narrow iptables rules per chain; negligible.

## 7. Security

- No hardcoded secrets, no plaintext credentials.
- Does not reopen the leak `0a21f82` closed: the DNS guard's blanket DROP is
  still present and still precedes the LAN carve-out; the new ACCEPTs match
  only two specific non-RFC1918 destination IPs, not the LAN/router resolver.
- `forceFixedDns` only takes effect where explicitly set `true`
  (stateless), so no other role's default DNS behavior changes.

## 8. API Currency

No external library/API surface touched (internal NixOS module options only).
Context7 not applicable, consistent with spec §6.

## 9. Build Validation

`sudo nixos-rebuild dry-build` is unavailable in this session (`sudo` is
blocked by the sandbox's "no new privileges" flag — a session limitation, not
a build failure). Used the CI-equivalent forcing-evaluation check instead
(`nix eval --impure ".#nixosConfigurations.<name>.config.system.build.toplevel.drvPath"`,
per the project's documented Test Command list) against all four targets named
in the spec's validation plan, plus `nix flake show --impure` for structure:

| Check | Result |
|---|---|
| `nix flake show --impure` | ✅ full output enumerated, no eval errors |
| `nix eval` `vexos-desktop-amd` toplevel | ✅ `.drv` path produced |
| `nix eval` `vexos-desktop-nvidia` toplevel (this dev host's own variant) | ✅ `.drv` path produced |
| `nix eval` `vexos-stateless-amd` toplevel | ✅ `.drv` path produced (pre-existing, unrelated locked-password warning only) |
| `nix eval` `vexos-htpc-amd` toplevel | ✅ `.drv` path produced |
| `git ls-files hardware-configuration.nix` | ✅ empty — not committed |
| `system.stateVersion` in all `configuration-*.nix` | ✅ unchanged (`25.11` / `26.05` per role, no diff) |
| New flake inputs / `follows` | ✅ none added — `flake.nix`/`flake.lock` diff empty |

No `sudo nixos-rebuild dry-build` was run against real hardware in this
session; the derivation-forcing eval is the same check CI performs
(`nix eval --impure ... .drvPath`, documented as "equivalent to `nix flake
check --no-build` for a single target"). Recommend the user run the actual
`dry-build` commands from the spec's validation plan on a real NixOS host
before pushing, plus the runtime smoke test (kill switch active → PIA
hostname resolves → tunnel comes up → clearnet still blocked pre-tunnel).

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A | 
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A- |

**Overall Grade: A (98%)**

Functionality/Build Success are marked slightly below 100% only because full
`nixos-rebuild dry-build` and the runtime PIA-connect smoke test could not be
executed from this sandboxed session (no root) or against the actual stateless
hardware — not because any check that *could* run failed.

## Returns

- **PASS**
- No CRITICAL issues found. No refinement cycle needed.
