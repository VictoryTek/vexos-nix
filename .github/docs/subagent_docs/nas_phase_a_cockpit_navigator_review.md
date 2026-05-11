# NAS Phase A — Cockpit Navigator: Phase 3 Review

**Project:** vexos-nix
**Phase reviewed:** A (Phase 2 implementation output)
**Spec under review:** [.github/docs/subagent_docs/nas_phase_a_cockpit_navigator_spec.md](nas_phase_a_cockpit_navigator_spec.md)
**Date:** 2026-05-11
**Reviewing agent:** Phase 3 Review & Quality Assurance subagent
**Build environment limitation:** Windows authoring host — cannot execute `nix flake check` or `nixos-rebuild dry-build`. Build Success scored on **static evaluability analysis** only. Operator must run live builds on the Linux/NixOS host.

---

## 1. Executive summary

Phase 2 delivered a correctly architected, idiomatic implementation: the
overlay layout (`pkgs/default.nix` + `pkgs/cockpit-navigator/default.nix`),
the universal `customPkgsOverlayModule` wiring across all five roles
(including the `mkBaseModule` `nixpkgs.overlays` list), and the
`modules/server/cockpit.nix` extension all match the spec's intent and
the project's Option B architecture rule. The three "deviations" the
implementer flagged (version `v0.5.12`, license `gpl3Only`, install
path `navigator/` at repo root) are **all upstream-correct** and
represent the implementer fixing latent errors in the spec — not bugs
in the implementation. The single blocker is the `lib.fakeHash`
placeholder in [pkgs/cockpit-navigator/default.nix](../../../pkgs/cockpit-navigator/default.nix#L25-L29):
this guarantees `nix flake check` and every dry-build will fail at the
fetch stage, which automatically fails Phase 6 preflight (`nix flake
check` is the first stage). It must be resolved before APPROVED.

---

## 2. Verification of implementer-flagged deviations

I cross-checked the upstream `45Drives/cockpit-navigator` repository
(README, releases page, repo tree at `master`, and the `LICENSE` file)
to adjudicate each of the three deviations.

| # | Deviation                              | Spec value         | Implemented value | Upstream truth                                                                                                                                                                  | Verdict on implementer        |
| - | -------------------------------------- | ------------------ | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| 1 | `version`                              | `0.5.10` (example) | `0.5.12`          | Latest stable release tag is **v0.5.12** (Sep 16 2025). v0.6.0 and v0.6.1 exist but are explicitly marked **Pre-release**. Spec §3.1 itself instructed the implementer to "re-verify the latest tag." | **Correct.** Spec example was stale; implementer followed the spec's own re-verification clause. |
| 2 | `license`                              | `lgpl3Only`        | `gpl3Only`        | GitHub repository sidebar AND `LICENSE` file body both state **"GNU General Public License v3.0"** (full GPL, not LGPL). Spec §3.1 was wrong.                                  | **Correct.** Spec was factually wrong; using `licenses.gpl3Only` is accurate. |
| 3 | `installPhase` source path             | `dist/navigator/`  | `navigator/` at repo root, copied wholesale to `$out/share/cockpit/` | Repo tree at `v0.5.12` has a top-level `navigator/` directory containing `manifest.json` and runtime assets. Upstream `Makefile` does `cp -rpf navigator $(DESTDIR)/usr/share/cockpit` — exactly mirrored by the implementer. There is no `dist/` directory. | **Correct.** Spec §3.3 example was speculative; implementer matched upstream's actual layout and Makefile install target verbatim. |

All three deviations are vindicated. **No CRITICAL findings on this
axis.** The spec should be amended in a future docs pass to remove the
incorrect example values, but that is out of scope for Phase A
implementation review.

---

## 3. Verdict on the `lib.fakeHash` placeholder

**Severity: CRITICAL — must be resolved before APPROVED.**

### Why it cannot be left in the tree

- Spec §6.3 (Acceptance Criteria) requires `nix flake check` and four
  dry-builds to succeed. With `lib.fakeHash`, Nix will refuse to fetch
  the source and every one of those commands will fail with the
  characteristic `error: hash mismatch in fixed-output derivation … got: sha256-…`
  message before any other evaluation continues.
- Phase 6 preflight ([scripts/preflight.sh](../../../scripts/preflight.sh))
  runs `nix flake check` as its first stage. A fake hash → preflight
  exit code ≠ 0 → automatic NEEDS_REFINEMENT under the orchestrator's
  Phase 6 governance ("Build or Preflight failure ALWAYS results in
  NEEDS_REFINEMENT").
- Spec §7 step 12 ("Manual smoke test … is NOT a Phase A blocker") only
  exempts the **runtime browser smoke test**, not the build-time
  evaluation gates of step 9 (`nix flake check`) or step 10 (dry-builds).
  The implementer's framing of `lib.fakeHash` as a "Phase 3 follow-up
  per §7 step 12" is a misreading: that step exempts §6.2 (functional),
  not §6.1 (static/build).

### Why the Windows-host limitation does not waive the gate

The project's preflight runs on the operator's Linux host, not on
Windows. The orchestrator workflow requires the work to be Phase 6
ready, which means **the working tree must contain a real SRI hash that
will let `nix flake check` succeed when the operator (or the next
subagent in WSL) runs preflight**. The fix is one round-trip:

```bash
nix-prefetch-github 45Drives cockpit-navigator --rev v0.5.12
# or
nix flake prefetch github:45Drives/cockpit-navigator/v0.5.12
```

Paste the resulting SRI string into [pkgs/cockpit-navigator/default.nix](../../../pkgs/cockpit-navigator/default.nix#L29).
This is appropriate work for the Phase 4 Refinement subagent invoked
on a host with `nix` available, or for the operator to perform once
before the next preflight cycle. Either way, the placeholder cannot
ship as the final state of Phase A.

---

## 4. Per-file findings

### 4.1 [pkgs/cockpit-navigator/default.nix](../../../pkgs/cockpit-navigator/default.nix)

| Observation                                                                                              | Severity         |
| -------------------------------------------------------------------------------------------------------- | ---------------- |
| `hash = lib.fakeHash;` placeholder will fail every Nix build until replaced.                             | **CRITICAL**     |
| `stdenvNoCC.mkDerivation` correct — no compiler needed; closure stays minimal.                           | OK               |
| `dontConfigure = true; dontBuild = true;` correct — upstream has no configure or build step.             | OK               |
| `installPhase` mirrors upstream Makefile (`cp -rpf navigator $(DESTDIR)/usr/share/cockpit`) exactly.    | OK               |
| `runHook preInstall` / `runHook postInstall` correctly preserved (best practice for hook compatibility). | OK               |
| `meta.license = licenses.gpl3Only` matches upstream `LICENSE` (full GPL-3.0).                            | OK               |
| `meta.platforms = platforms.linux` correct — Cockpit is Linux-only.                                      | OK               |
| `meta.maintainers = [ ]` acceptable for a personal flake (spec §3.3 explicitly allows empty list).       | OK               |
| Source pinned to a specific tag (`v${version}` → `v0.5.12`), not a branch — supply-chain hygiene.        | OK               |
| Comment block at the top documents upstream layout decision and references the spec — good auditability. | OK (NICE)        |
| `version = "0.5.12"` is the current latest **stable** (v0.6.x are explicitly pre-release).               | OK               |

### 4.2 [pkgs/default.nix](../../../pkgs/default.nix)

| Observation                                                                                              | Severity         |
| -------------------------------------------------------------------------------------------------------- | ---------------- |
| `vexos = (prev.vexos or { }) // { … };` — correct forward-compatible overlay merge pattern per spec §4.2. Phases B/C/D can extend `vexos.*` from other overlays without clobbering. | OK |
| Uses `final.callPackage` (not `prev.callPackage`) so dependency overrides downstream of this overlay are honoured. | OK               |
| File is a pure overlay function (`final: prev: { … }`), suitable for `nixpkgs.overlays = [ (import ./pkgs) ];`. | OK           |
| Header comment cleanly explains the `vexos.` namespace rationale.                                        | OK (NICE)        |

### 4.3 [flake.nix](../../../flake.nix)

| Observation                                                                                              | Severity         |
| -------------------------------------------------------------------------------------------------------- | ---------------- |
| `customPkgsOverlayModule` let-binding present (≈ line 73) and structurally identical to `unstableOverlayModule` / `proxmoxOverlayModule`. Syntactically correct overlay-module wrapper. | OK |
| All five role `baseModules` lists include `customPkgsOverlayModule` — verified by inspection of the `roles = { … };` table. The overlay therefore reaches `desktop`, `htpc`, `stateless`, `server`, `headless-server` per spec §4.3. | OK |
| `mkBaseModule`'s `nixpkgs.overlays = [ … (import ./pkgs) ];` literal also includes the custom overlay, keeping the `nixosModules.*Base` exports in sync with `mkHost` (the "no drift" invariant called out in the file). | OK |
| No new flake input introduced — `flake.lock` will not change, matching spec §8.3.                        | OK               |
| Overlay is applied universally even on roles that won't consume `vexos.cockpit-navigator` (desktop, htpc, stateless). This is intentional per spec ("harmless on display roles … forward-consistency with Phases B/C/D") and the overlay is lazy — the package is only realized when referenced. No closure cost on non-consumers. | OK |
| No formatting drift visible vs surrounding overlay blocks.                                               | OK               |

### 4.4 [modules/server/cockpit.nix](../../../modules/server/cockpit.nix)

| Observation                                                                                              | Severity         |
| -------------------------------------------------------------------------------------------------------- | ---------------- |
| Two `lib.mkIf` blocks gate **only** on options (`cfg.enable`, `cfg.enable && cfg.navigator.enable`). No role/display/gaming flag gating. **Option B compliant.** | OK |
| `lib.mkMerge` structure is well-formed: top-level `config = lib.mkMerge [ … ];` with each list element a self-contained attrset wrapped in `lib.mkIf`. Will evaluate cleanly. | OK |
| Reference is `pkgs.vexos.cockpit-navigator` — uses the namespaced overlay attribute. No bare `pkgs.cockpit-navigator` reference (which would fail evaluation). Verified by grep: zero hits in the modified file. | OK |
| `navigator.enable` defaults to `cfg.enable`. This recursive default (`config.vexos.server.cockpit.enable` referenced from a sibling option default) is a legal Nix pattern — option defaults are thunks evaluated in `config` context. No infinite recursion risk. | OK |
| Header comment cites the spec doc — good cross-reference for future audits.                              | OK (NICE)        |
| Module signature `{ config, lib, pkgs, ... }:` matches existing server-module convention.                | OK               |
| `services.cockpit.openFirewall = true` retained — TCP 9090 stays open. Navigator adds no new port, no firewall change needed. Matches spec §5.3. | OK |
| No `systemd.services.cockpit.environment.XDG_DATA_DIRS` override — correct posture per spec §2.4 (only add if the live verification step fails). Implementer correctly deferred this to operator post-deploy verification. | OK |
| Option type/description for `navigator.enable` is clear; documents the "enable Cockpit also installs Navigator" default behaviour. | OK |

### 4.5 [template/server-services.nix](../../../template/server-services.nix)

| Observation                                                                                              | Severity         |
| -------------------------------------------------------------------------------------------------------- | ---------------- |
| Added `# vexos.server.cockpit.navigator.enable = true;       # 45Drives file browser plugin (Phase A)` immediately below the existing cockpit toggle, exactly per spec §5.5. | OK |
| Both lines remain commented — defaults preserved; no behavioural change for hosts that don't deploy this template. | OK |
| Comment column alignment matches the file's existing style.                                              | OK               |

---

## 5. Findings catalogue

### CRITICAL (1)

1. **`lib.fakeHash` in [pkgs/cockpit-navigator/default.nix](../../../pkgs/cockpit-navigator/default.nix#L29)
   blocks all Nix evaluation.** Replace with the real SRI hash from
   `nix-prefetch-github 45Drives cockpit-navigator --rev v0.5.12`.
   Without this, `nix flake check`, every `nixos-rebuild dry-build`,
   and Phase 6 preflight will fail. (Acceptable resolution path: Phase
   4 refinement subagent runs the prefetch on a Linux/WSL host, or the
   operator pastes the hash before re-running preflight.)

### RECOMMENDED (0)

None. The implementation is otherwise tight.

### NICE-TO-HAVE (2)

1. After the hash is in place, consider amending the spec
   ([nas_phase_a_cockpit_navigator_spec.md](nas_phase_a_cockpit_navigator_spec.md))
   §3.1 and §3.3 to record the corrected version, license, and install
   path so future Phase B/C/D subagents don't re-litigate the same
   three points. This is a docs-only follow-up, not a blocker.
2. The optional fallback note about `dist/navigator/` in spec §3.3 is
   now known to be inapplicable to v0.5.12. If the spec is amended,
   the fallback note can be deleted entirely.

---

## 6. Build validation (static evaluability analysis)

The Windows authoring host cannot execute Nix. The following findings
are based on static reading of the changed files against my knowledge
of Nix evaluation semantics and nixpkgs 25.11 module conventions.

| Static check                                                                                                                | Result |
| --------------------------------------------------------------------------------------------------------------------------- | ------ |
| `pkgs/default.nix` is a syntactically valid overlay function (`final: prev: { … }`).                                       | PASS   |
| `pkgs/cockpit-navigator/default.nix` argument set `{ lib, stdenvNoCC, fetchFromGitHub }` is satisfiable by `callPackage`.   | PASS   |
| `flake.nix` `customPkgsOverlayModule` is a well-formed NixOS module fragment (`{ nixpkgs.overlays = [ … ]; }`).             | PASS   |
| All five `baseModules` lists include `customPkgsOverlayModule`.                                                             | PASS   |
| `mkBaseModule` `nixpkgs.overlays` literal includes `(import ./pkgs)`.                                                       | PASS   |
| `modules/server/cockpit.nix` `lib.mkMerge [ lib.mkIf … lib.mkIf … ]` evaluates to a single `config` attrset.                | PASS   |
| `pkgs.vexos.cockpit-navigator` reference resolves to the overlay attribute defined in `pkgs/default.nix`.                   | PASS   |
| `navigator.enable` default referencing `cfg.enable` is legal (option defaults are thunks evaluated in `config` scope).      | PASS   |
| No occurrence of bare `pkgs.cockpit-navigator` (would fail). Confirmed by inspection of all modified files.                 | PASS   |
| No new `lib.mkIf` role gates inside shared modules — Option B preserved.                                                    | PASS   |
| **Source fetch (`fetchFromGitHub` with `lib.fakeHash`)** — guaranteed to fail on first real Nix evaluation.                | **FAIL** |

Net: the **module/overlay/flake wiring would evaluate cleanly**; only
the `fetchFromGitHub` hash blocks an actual build. This is precisely
the kind of single-defect refinement Phase 4 is designed to handle.

---

## 7. Score table

| Category                  | Score | Grade |
| ------------------------- | ----- | ----- |
| Specification Compliance  | 92%   | A−    |
| Best Practices            | 95%   | A     |
| Functionality             | 65%   | D     |
| Code Quality              | 95%   | A     |
| Security                  | 85%   | B+    |
| Performance               | 100%  | A+    |
| Consistency               | 95%   | A     |
| Build Success (static)    | 50%   | F     |

**Overall Grade: B− (84.6%)**

Score notes:
- **Specification Compliance** docked 8 pts because the implementer
  silently changed three values without amending the spec (even though
  all three changes were upstream-correct). The implementation is
  faithful to the spec's *intent*; the deductions reflect the
  documentation gap, not a defect.
- **Functionality** docked heavily: the package literally cannot be
  built right now, which means no host can install Navigator until the
  hash lands.
- **Build Success** scored 50% per the policy you set: static analysis
  shows everything is wired correctly and would evaluate, but the
  guaranteed `fetchFromGitHub` hash mismatch is a real fail in the
  build pipeline that I am marking honestly.
- **Security** at 85%: the source is pinned to a tag (not a branch),
  uses `fetchFromGitHub` (which strips the `.git` directory and pins
  via SRI), and exposes no secrets. The 15-pt deduction reflects that
  until the real hash is in place, the supply-chain integrity of the
  fetch is unverified.

---

## 8. Final verdict

**NEEDS_REFINEMENT**

Single blocker: replace `lib.fakeHash` in
[pkgs/cockpit-navigator/default.nix](../../../pkgs/cockpit-navigator/default.nix#L29)
with the real SRI256 hash for `45Drives/cockpit-navigator` tag
`v0.5.12`. Once that one line is changed, all other findings clear and
this implementation should sail through Phase 5 re-review and Phase 6
preflight.

The implementer's deviations are not refinement items — they are
correct upstream-grounded fixes. Do **not** revert them.
