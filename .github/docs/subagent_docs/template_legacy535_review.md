# template_legacy535 — Review

## Spec Compliance

- [x] `flake.nix` — `vexos-vanilla-nvidia-legacy535` added to hostList; count updated 29→30; stale "no NVIDIA legacy variants" comment removed
- [x] `ci.yml` — `vexos-vanilla-nvidia-legacy535` added to vanilla group; count comment 29→30
- [x] `template/etc-nixos-flake.nix` — comment header updated; all 6 nixosConfigurations entries added with correct builder + inline `nvidiaDriverVariant` module
- [x] `scripts/install.sh` — `&& [ "$ROLE" != "vanilla" ]` guard removed

## Correctness Notes

- Each legacy535 entry passes a list `[ gpuNvidiaModule { vexos.gpu.nvidiaDriverVariant = "legacy_535"; } ]`.
  The builder functions all use `if builtins.isList gpuModule then gpuModule else [ gpuModule ]`
  to normalise this — list passing is the established pattern and is handled correctly.
- `headless-server-nvidia-legacy535` uses `gpuNvidiaHeadless` (not `gpuNvidia`) — consistent
  with the existing `headless-server-nvidia` entry and the main flake's `mkHost` lookup which
  maps `headless-server + nvidia` → `nvidia-headless.nix`.
- `vanilla-nvidia-legacy535` uses `gpuNvidia` (not `gpuVanillaVm`) — vanilla VM is the only
  variant that needs the special gpuVanillaVm module (due to missing system.nix options);
  NVIDIA legacy535 is a regular non-VM variant and `gpuNvidia` is correct.
- No new module options, imports, or flake inputs introduced.

## Security / stateVersion / hardware-configuration

- `system.stateVersion` unchanged in all `configuration-*.nix` ✓
- `hardware-configuration.nix` not committed ✓
- No new flake inputs; no `follows` declarations needed ✓

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A (Windows) | — |

**Overall Grade: A (100%)**

## Result: PASS
