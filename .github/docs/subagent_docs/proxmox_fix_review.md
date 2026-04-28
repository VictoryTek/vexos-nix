# Review: Fix Proxmox Overlay Not Applied to Server NixOS Configurations

**Date:** 2026-04-28  
**Reviewer:** QA Agent  
**Spec:** `.github/docs/subagent_docs/proxmox_fix_spec.md`

---

## Summary of Findings

The implementation correctly resolves the root cause identified in the spec: the
`proxmox-nixos` overlay (`inputs.proxmox-nixos.overlays.default`) was never added
to `nixpkgs.overlays`, meaning `pkgs.proxmox-ve` was absent whenever
`services.proxmox-ve.enable = true` was set and the lazy default for
`services.proxmox-ve.package` was evaluated.

All five spec-mandated changes are present and accurate:

1. **`proxmoxOverlayModule` defined in `let` block** — placed after `upModule`,
   following the exact same inline-module pattern as `unstableOverlayModule`.
   Comment correctly explains why the overlay must be explicit.
2. **Correct overlay attribute** — `nixpkgs.overlays = [ inputs.proxmox-nixos.overlays.default ]`.
3. **Path A (`roles`) — `server.baseModules`** — includes `proxmoxOverlayModule`
   before `inputs.proxmox-nixos.nixosModules.proxmox-ve`.
4. **Path A (`roles`) — `headless-server.baseModules`** — same addition; correctly
   omits `upModule` (headless has no display).
5. **Path B (`mkBaseModule`)** — changed from `lib.optional … single-value` to
   `lib.optionals … [ proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ]`.
   `lib.optionals` (plural) is the correct function when passing a list — no
   functional difference but avoids a subtle type mismatch.
6. **Comment in `modules/server/proxmox.nix`** — corrected from the false claim
   that the NixOS module auto-applies its overlay, to the accurate description
   that both the overlay module and the NixOS module are applied at the flake
   level via `roles.server/headless-server.baseModules`.

No regressions were introduced:
- Non-server roles (`desktop`, `htpc`, `stateless`) are unaffected — `proxmoxOverlayModule`
  is not added to their `baseModules`.
- `system.stateVersion` was not modified (confirmed by static inspection; only
  `flake.nix` and `modules/server/proxmox.nix` were changed).
- `hardware-configuration.nix` is not tracked in the repository.
- All existing flake inputs retain correct `follows` declarations; the `proxmox-nixos`
  input intentionally omits `nixpkgs.follows` per the spec's documented rationale.

---

## Build Validation Results

### Environment note

Build validation was performed from a Windows host with WSL (Nix 2.34.1).
`/etc/nixos/hardware-configuration.nix` does not exist in the WSL environment;
this affects `nixosConfigurations.*` evaluation but not `nixosModules.*` evaluation.

### `nix flake check --no-build --impure`

```
evaluating flake...
checking flake output 'nixosModules'...
checking NixOS module 'nixosModules.base'...              ✓ PASS
checking NixOS module 'nixosModules.htpcBase'...          ✓ PASS
checking NixOS module 'nixosModules.serverBase'...        ✓ PASS
checking NixOS module 'nixosModules.headlessServerBase'...✓ PASS
checking NixOS module 'nixosModules.statelessBase'...     ✓ PASS
checking NixOS module 'nixosModules.gpuAmd'...            ✓ PASS
checking NixOS module 'nixosModules.gpuNvidia'...         ✓ PASS
checking NixOS module 'nixosModules.gpuIntel'...          ✓ PASS
checking NixOS module 'nixosModules.gpuAmdHeadless'...    ✓ PASS
checking NixOS module 'nixosModules.gpuNvidiaHeadless'... ✓ PASS
checking NixOS module 'nixosModules.gpuIntelHeadless'...  ✓ PASS
checking NixOS module 'nixosModules.gpuVm'...             ✓ PASS
checking NixOS module 'nixosModules.statelessGpuVm'...    ✓ PASS
checking NixOS module 'nixosModules.asus'...              ✓ PASS
checking flake output 'nixosConfigurations'...
error: path '/etc/nixos/hardware-configuration.nix' does not exist
```

**All 14 `nixosModules.*` checks passed**, including `serverBase` and
`headlessServerBase` which are the two modules that now include
`proxmoxOverlayModule`. The `nixosConfigurations.*` failure is the expected
environment limitation (no `/etc/nixos/hardware-configuration.nix` in WSL) and
is not caused by this change.

### `sudo nixos-rebuild dry-build` (server variants)

Cannot be executed in the WSL dev environment: `nixos-rebuild` is a NixOS-only
binary and `/etc/nixos/hardware-configuration.nix` is absent. These commands
must be run on a live NixOS host:

```bash
sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-server-vm
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd
```

**Recommendation:** Run these three dry-builds on the target NixOS host before
deploying. Based on the static code review and the passing `nixosModules.*`
evaluations, there are no structural issues that would cause them to fail.

---

## Score Table

| Category                  | Score | Grade |
|---------------------------|-------|-------|
| Specification Compliance  | 100%  | A+    |
| Best Practices            | 97%   | A+    |
| Functionality             | 97%   | A+    |
| Code Quality              | 95%   | A     |
| Security                  | 100%  | A+    |
| Performance               | 100%  | A+    |
| Consistency               | 98%   | A+    |
| Build Success             | 85%   | B+    |

> Build Success scored B+ because `nixosConfigurations.*` dry-builds could not
> be executed in the WSL dev environment. All `nixosModules.*` checks passed;
> no code defects were found that would cause a dry-build failure on a real host.

**Overall Grade: A (97%)**

---

## Verdict

**PASS**

The implementation is correct, complete, and consistent with the project's
module architecture pattern. The proxmox overlay is now explicitly applied in
both `mkHost` (Path A) and `mkBaseModule` (Path B), scoped to `server` and
`headless-server` roles only.

**Remaining action for the deploying engineer:**
Run `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` (and the vm /
headless-server variants) on a NixOS host to confirm the full system closure
builds before applying with `switch`.
