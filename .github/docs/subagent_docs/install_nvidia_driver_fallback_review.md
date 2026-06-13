# Review: NVIDIA Driver Double-Fallback for install.sh

## Specification Compliance

Implementation matches spec exactly:
- `REMAINING_NON_NVIDIA` computed by filtering `REMAINING` with `HEAVY_BUILD_REGEX` ✓
- Conditions checked: `REMAINING_NON_NVIDIA` empty AND `VARIANT=nvidia` AND `NVIDIA_SUFFIX=""` ✓
- `kernel-install-override.nix` upgraded with both `boot.kernelPackages` and `vexos.gpu.nvidiaDriverVariant` ✓
- Third dry-build (`DRY_OUT3` / `REMAINING2`) confirms the combo is fully cached ✓
- Abort path (cleanup + message) preserved for non-NVIDIA remaining misses ✓
- Post-install note updated to distinguish driver fallback from kernel-only fallback ✓
- `else` branch moves success echo inside the `if [ -n "$REMAINING" ]` conditional ✓

## Best Practices

- `lib.mkForce` used for `boot.kernelPackages` (correct — overrides priority 100 set by system-desktop-kernel.nix) ✓
- Plain assignment used for `vexos.gpu.nvidiaDriverVariant` (correct — option default at priority 1500, overridden by normal priority 100) ✓
- Heredoc `NIXEOF` delimiter properly quoted to prevent variable expansion in the Nix content ✓
- `|| true` on grep to prevent set -e from firing on empty output ✓
- Cleanup (`rm`, `git rm --cached`) in all abort paths ✓
- `2>/dev/null` on `grep -q` for the post-install note check ✓

## Consistency

- Same `grep -Ev` exclusion list reused verbatim for `REMAINING2` — consistent with existing `REMAINING` ✓
- Same abort message pattern as all other abort paths ✓
- `HEAVY_BUILD_REGEX` variable reused from the outer scope, not redefined ✓
- Gated by `[ "$ROLE" = "desktop" ]` (inherited from outer condition) — consistent with existing kernel fallback scope ✓

## Logic Verification

Tracing the user's failing scenario:
1. First dry-build → SOURCE_BUILDS has NVIDIA 580 packages
2. All match HEAVY_BUILD_REGEX → NON_KERNEL_BUILDS empty + ROLE=desktop → kernel fallback fires
3. `kernel-install-override.nix` written with `linuxPackages` only
4. Second dry-build → REMAINING has `nvidia-x11-580.142-6.12.92.drv`, `nvidia-settings-580.142.drv`, `NVIDIA-Linux-x86_64-580.142.run.drv`
5. **NEW**: REMAINING_NON_NVIDIA = filter with HEAVY_BUILD_REGEX → empty (all are NVIDIA)
6. VARIANT=nvidia, NVIDIA_SUFFIX="" → driver fallback fires
7. Override upgraded to add `vexos.gpu.nvidiaDriverVariant = "legacy_535"`
8. Third dry-build uses 535 driver against linuxPackages → all packages cached → proceeds to install ✓

## Security

- No secrets introduced ✓
- No world-writable files ✓
- `tee` with heredoc is safe ✓

## Completeness

One edge case to note (not a bug, acceptable behavior):
- If `NVIDIA_SUFFIX = "-legacy535"` (user already chose legacy535 as their variant) and 535 driver is somehow not cached, the `[ "$NVIDIA_SUFFIX" = "" ]` condition correctly falls through to the standard abort path — no attempt to double-fallback to legacy535 when already on legacy535.

## Build Validation

`install.sh` is a bash script — no Nix build required. Validated:
- `bash -n scripts/install.sh` (syntax check)
- Logic trace matches expected behavior
- `git ls-files hardware-configuration.nix` — not in repo ✓
- `system.stateVersion` not modified ✓
- No new flake inputs ✓

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 98% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99.75%)**

## Result: PASS
