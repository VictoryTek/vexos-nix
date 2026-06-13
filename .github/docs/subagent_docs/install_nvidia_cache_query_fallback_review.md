# Review: Dynamic Cache-Query Fallback + All-Role Kernel Override Support

## Specification Compliance

| Requirement | Status |
|---|---|
| `query_cached_nvidia_variant()` function added | ✓ |
| Iterates `stable → legacy_535`, returns vexos variant name | ✓ |
| Uses `nix eval --impure` against pinned nixpkgs from `/etc/nixos` inputs | ✓ |
| Checks `nix path-info --store https://cache.nixos.org` | ✓ |
| Returns nothing + exits cleanly if neither is cached | ✓ |
| `[ "$ROLE" = "desktop" ]` gate removed | ✓ |
| `kernelOverrideFile` added to all 5 remaining builders in template flake | ✓ |
| Post-install note shows queried variant name dynamically | ✓ |
| Hardcoded `legacy_535` string eliminated from override content | ✓ |

## Best Practices

- `|| continue` on `nix eval` call: evaluation failure (wrong attribute path, network error)
  is silently skipped to next candidate — correct ✓
- `[ -z "$out_path" ] && continue`: guards against empty string from `eval --raw` ✓
- `&>/dev/null 2>&1` on `path-info`: network failure = non-zero = continue ✓
- `<< NIXEOF` (unquoted) on driver override heredoc: allows `$CACHED_NV_VARIANT` expansion ✓
- `<< 'NIXEOF'` (quoted) on kernel-only override heredoc: no variables to expand ✓
- `grep -oP` with Perl regex for post-install note: safe, `-o` extracts only the match ✓
- `sudo` on `nix eval` in function: `/etc/nixos` may be root-owned; consistent with rest of script ✓

## Logic Verification

Tracing the failing scenario (NVIDIA 580 uncached for any kernel):

1. First dry-build → SOURCE_BUILDS: `NVIDIA-Linux-x86_64-580.142.run.drv`, `nvidia-x11-580.142-6.18.34.drv`, `openrazer-3.10.3-6.18.34.drv`, `nvidia-settings-580.142.drv`
2. All match HEAVY_BUILD_REGEX → NON_KERNEL_BUILDS empty → kernel fallback fires (now for ALL roles, not just desktop) ✓
3. kernel-only override written, second dry-build → REMAINING: `nvidia-x11-580.142-6.12.92.drv`, `nvidia-settings-580.142.drv`, `NVIDIA-Linux-x86_64-580.142.run.drv`
4. REMAINING_NON_NVIDIA = filter by HEAVY_BUILD_REGEX → empty; VARIANT=nvidia, NVIDIA_SUFFIX="" → driver query fires ✓
5. `query_cached_nvidia_variant "linuxPackages"`:
   - tries `stable` → evals to 580.142 outPath → not in cache → continue
   - tries `legacy_535` → evals to 535.x outPath → in cache → returns "legacy_535" ✓
6. Override upgraded with `vexos.gpu.nvidiaDriverVariant = "legacy_535"` ✓
7. Third dry-build confirms fully cached ✓
8. Install proceeds ✓

Edge cases:
- `query_cached_nvidia_variant` returns `"latest"` (stable IS somehow now cached): override
  sets `nvidiaDriverVariant = "latest"` (redundant but harmless; third dry-build confirms) ✓
- Neither cached → clear abort message lists both variants checked ✓
- Non-NVIDIA remaining items → falls through to standard abort ✓
- Non-NVIDIA roles with kernel cache miss (e.g., stateless-amd + openrazer uncached):
  kernel-only override applied, no driver query attempted (VARIANT != "nvidia") ✓

## Template Flake — All Builders

Six builders now include `lib.optional hasKernelOverride kernelOverrideFile`:
- `_mkVariantWith` (desktop) — line 163 (pre-existing) ✓
- `mkStatelessVariant` — line 196 ✓
- `mkHtpcVariant` — line 216 ✓
- `mkVanillaVariant` — line 234 ✓
- `mkHeadlessServerVariant` — line 258 ✓
- `mkServerVariant` — line 295 ✓

`kernelOverrideFile` and `hasKernelOverride` declared at top-level `let` (lines 131–132),
scoped to the entire flake — available to all builders ✓

Nix parse: `nix-instantiate --parse` passes ✓

## Consistency

- Pattern matches existing `lib.optional hasUserOverride` and `lib.optional hasServices` usage ✓
- `vexos.gpu.nvidiaDriverVariant` option declared in `modules/gpu/nvidia.nix`, imported
  via `gpuNvidia` for all NVIDIA variants across all roles ✓
- No new `lib.mkIf` guards introduced ✓

## Security

- No secrets or credentials ✓
- `builtins.getFlake "git+file:///etc/nixos"` reads from local filesystem only ✓
- `nix path-info --store https://cache.nixos.org` is a read-only cache query ✓

## Build Validation

- `bash -n scripts/install.sh`: syntax OK ✓
- `nix-instantiate --parse template/etc-nixos-flake.nix`: parse OK ✓
- `hardware-configuration.nix` not tracked ✓
- `system.stateVersion` not changed ✓
- No new flake inputs ✓

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 99% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99.9%)**

## Result: PASS
