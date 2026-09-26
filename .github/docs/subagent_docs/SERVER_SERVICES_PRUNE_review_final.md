# SERVER_SERVICES_PRUNE — Final Review

Phase 5 output, refinement cycle 1. Follows
`SERVER_SERVICES_PRUNE_review.md`.

---

## 1. Trigger

Phase 6 preflight failed, exit 1, at CHECK 10 — the stage added by this change:

```
[10/10] Verifying the server service name list still derives...
sed: can't read warning: Git tree '/mnt/c/Projects/vexos-nix' is dirty
/nix/store/…-vexos-prune-services/bin/vexos-prune-services: No such file or directory
✗ FAIL  derived service list is EMPTY — prune tooling would treat every entry as dead
```

Per CLAUDE.md a preflight failure is CRITICAL and overrides the Phase 3 PASS.

---

## 2. Issue Fixed

### 2.1 CRITICAL — CHECK 10 captured stderr into the store path

`nix build --print-out-paths … 2>&1` folded Nix's own diagnostics ("Git tree is
dirty", the two untrusted-flake-config warnings) into the captured stdout. The
result was used directly as a store path, so `sed` was handed a path with
warning text embedded, found nothing, and the stage reported an empty service
list.

This was a defect in the check, not in the derivation it guards — the tool had
58 names baked in throughout. But the failure mode was the dangerous direction:
a **false** "list is EMPTY" report. Had the logic been reused anywhere that
acts on the count rather than merely failing, it would have implied every entry
was dead.

Fixed in `scripts/preflight.sh`:

- stderr redirected to its own temp file instead of `2>&1`, and printed only on
  build failure;
- `tail -1` on the captured stdout, since `--print-out-paths` may emit several
  lines;
- an explicit guard that the binary exists before `sed` reads it, so a missing
  file can never again present as an empty list.

### 2.2 Verification of the fix

- `shellcheck -S warning scripts/preflight.sh` — clean.
- CHECK 10 now reports `server service names derive (58 services)`.

---

## 3. Confirmation of Phase 3 Findings

Both CRITICAL issues from Phase 3 remain fixed and are exercised by the passing
preflight run:

| Phase 3 issue | State |
|---|---|
| 5.1 — missing app treated as "dead entries found" | Fixed; `pkgs.vexos.vexos-update` builds, shellcheck passes (CHECK 8) |
| 5.2 — pruning against the restored lock deadlocks | Fixed; recipe uses main, both call sites commented |

---

## 4. Outstanding Items From Phase 3 Review

| Item | State |
|---|---|
| 6.1 — preflight blocked by untracked files | **Resolved.** Files committed in `8d3b48c`; `nix flake show` passes, 30 configs listed, CI matrix fully covered |
| 6.2 — no `nixos-rebuild dry-build` | **Largely closed.** See §4.1 — full evaluation run per variant instead |
| 6.3 — on-host end-to-end flow unexercised | **Still outstanding.** First real run will be on `vexos-headless-server-intel` |
| 6.4 — `nix run` against a real GitHub revision | **Still outstanding.** Cannot be exercised until pushed |

6.3 and 6.4 are environmental, not defects, and cannot be closed from this
workstation. They are the user's first-run risks and are stated as such rather
than assumed away.

### 4.1 Per-variant full evaluation (replaces the missing dry-build)

WSL Ubuntu carries Nix 2.34.1 but is not NixOS — no `/etc/NIXOS`, no
`nixos-rebuild` — so CHECK 2 cannot run. CLAUDE.md names the substitute:
forcing `config.system.build.toplevel.drvPath`, the same technique CI uses and
the stated equivalent of `nix flake check --no-build` for a single target. It
performs the evaluation half of a dry-build, which is exactly the half that
"option does not exist" failures live in.

Run sequentially to keep peak RAM flat. All eight succeeded:

| Variant | Result |
|---|---|
| `vexos-headless-server-intel` | OK — the variant that reported the original failure |
| `vexos-desktop-amd` | OK |
| `vexos-desktop-nvidia` | OK |
| `vexos-desktop-vm` | OK |
| `vexos-server-amd` | OK |
| `vexos-headless-server-amd` | OK |
| `vexos-stateless-amd` | OK |
| `vexos-htpc-amd` | OK |

This covers every variant CLAUDE.md's Phase 3 requires, plus the reporting
variant, and confirms the change leaves the system closure intact across all
six roles.

What remains genuinely unverified is only the *build* half — realising the
derivations and reporting what would be fetched or compiled. That requires a
NixOS host and is the user's step.

---

## 5. Preflight Result

`bash scripts/preflight.sh` — **exit 0**, all ten stages:

| Stage | Result |
|---|---|
| 0 tools | PASS |
| 1 flake structure + CI matrix | PASS — 30 nixosConfigurations, full coverage |
| 2 dry-build | SKIP — not a NixOS host |
| 3 hardware-configuration.nix untracked | PASS |
| 4 system.stateVersion ×6 | PASS |
| 5 flake.lock | PASS — tracked, all inputs pinned |
| 6 Nix formatting | WARN — pre-existing, 111/190 files; both new files clean |
| 7 secret hygiene | PASS on hard checks; pre-existing WARNs unchanged |
| 8 vexos-update builds | PASS — shellcheck |
| 9 shellcheck scripts/ | PASS |
| 10 service name derivation | PASS — 58 services |

The stage 6 and 7 warnings predate this change and are not introduced by it.

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 95% | A |
| Consistency | 100% | A |
| Build Success | 95% | A |

**Overall Grade: A (99%)**

Build Success is no longer marked down for flake structure, which now passes,
nor for the missing dry-build, which §4.1 replaces with a full per-variant
evaluation across all eight targets. It remains short of full marks only
because the build half — realising derivations — needs a NixOS host.

Functionality and Performance are held at 95% for the composition risk in §4,
items 6.3 and 6.4: every component is verified individually, but the on-host
sequence has not been run end to end.

---

## 7. Verdict

**APPROVED.**

One refinement cycle used. The CRITICAL preflight failure is resolved and
re-verified, no new issues were introduced, and Phase 6 has been observed
exiting 0.
