# L-12 — nvidia-vaapi-driver incorrectly gated on variant == "latest" — Review

Status: Phase 3 (Review & Quality Assurance)
Spec: `.github/docs/subagent_docs/L-12_nvidia_vaapi_gate_spec.md`

## Modified Files

- `modules/gpu/nvidia.nix`

## Review Against Spec

1. **Specification Compliance** — matches the spec exactly:
   `hardware.graphics.extraPackages` now installs `nvidia-vaapi-driver`
   unconditionally instead of behind `lib.mkIf useOpen`; the stale
   comment claiming exclusion "to avoid broken hardware acceleration"
   was rewritten to explain the actual reasoning (variant is a
   branch-preference axis, not a hardware-generation axis); `useOpen`
   itself was correctly left untouched (still gates `hardware.nvidia.open`,
   a genuinely different, correctly-scoped concern).

2. **Best Practices** — corrected the plan's literal suggestion
   (`variant != legacy_470`) after verifying `legacy_470` no longer
   exists in this codebase (removed by H-02 earlier this session) —
   applying that suggestion mechanically against the current two-value
   enum would be a no-op-disguised-as-a-condition; implemented the
   equivalent, clearer intent (install unconditionally) directly rather
   than adding a dead conditional that always evaluates true.

3. **Consistency** — style matches the surrounding config block; no new
   conventions introduced.

4. **Maintainability** — new comment explains the actual causal
   relationship (driver-branch choice vs. GPU generation are
   independent here) so a future reader doesn't reintroduce the same
   conflation.

5. **Completeness** — verified via direct eval that
   `vexos-desktop-nvidia-legacy535`'s `hardware.graphics.extraPackages`
   now includes `nvidia-vaapi-driver` (previously would have been
   absent under the old `lib.mkIf useOpen` gate, since `useOpen =
   false` for `legacy_535`).

6. **Performance** — negligible; one additional small package in the
   graphics extraPackages closure for `legacy_535` hosts.

7. **Security** — no new vulnerabilities; `nvidia-vaapi-driver` is the
   same trusted nixpkgs package already used for `"latest"`, now also
   applied to `legacy_535`.

8. **API Currency** — verified both external claims directly rather
   than trusting the pre-existing comment: (a) NVIDIA's official 535
   driver-branch documentation confirms Turing/Ampere/Ada support, not
   just Maxwell/Pascal/Volta; (b) `nvidia-vaapi-driver` upstream
   confirms graceful software-decode fallback on hardware without
   NVDEC, rather than breaking.

9. **Build Validation** — via WSL2 Ubuntu (Nix 2.34.1, mounted repo at
   `/mnt/c/Projects/vexos-nix`):
   - Bracket/brace/paren balance on the file: braces 6/6, parens 18/18.
   - `vexos-desktop-nvidia` (`"latest"` variant) → PASS.
   - `vexos-desktop-nvidia-legacy535` (the variant this fix targets) →
     PASS.
   - Directly evaluated
     `nixosConfigurations.vexos-desktop-nvidia-legacy535.config.hardware.graphics.extraPackages`
     and confirmed `nvidia-vaapi-driver` is now present in the
     resulting package-name list — the fix's effect verified against a
     real evaluated closure, not just inferred from the diff.
   - Ran the full `bash scripts/preflight.sh` → **exit 0, "Preflight
     PASSED — safe to push."** Same pre-existing, expected WARNs as
     every prior review this session. Stage `[8/8]` passed.
   - `git ls-files hardware-configuration.nix` → empty, unaffected.
   - No `system.stateVersion` change; no new flake inputs.
   - No FORBIDDEN COMMANDS used.

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
| Build Success | 100% — both nvidia variants evaluated, package-list effect confirmed, full `preflight.sh` passed via WSL2 | A |

**Overall Grade: A (100%)**

## Result

**PASS.** Phase 6 (Preflight) has genuinely run and passed for this
change, and the fix's actual effect was directly confirmed against an
evaluated closure. Safe to commit and push.
