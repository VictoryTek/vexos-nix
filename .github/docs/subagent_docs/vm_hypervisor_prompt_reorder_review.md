# VM Hypervisor Prompt Reorder — Review

## Scope

Single file changed: `justfile`. The VM hypervisor selection block
(previously `justfile:290-340` in the pre-change file) was moved to
immediately follow the GPU-variant selection block (now `justfile:240-290`),
ahead of the desktop-environment block. No line inside either block was
altered — pure relocation, confirmed by re-reading the post-edit file in
full (`justfile:196-345`).

## Checks performed

1. **Specification compliance** — matches
   `vm_hypervisor_prompt_reorder_spec.md` exactly: block moved as specified,
   no logic changes, `_features_set` calls unaffected.
2. **Variable-ordering safety** — verified by inspection: the relocated
   block only reads `VARIANT` (set by the block directly above it) and
   `VM_PLATFORM` (a recipe parameter, defined at function entry). It does
   not reference `DESKTOP_ENV`, `OLD_DESKTOP_ENV`, or `DE_CHANGED`, which
   are now defined *after* it. The later combined check at
   `if [ "$DE_CHANGED" = "true" ] || [ "$VM_PLATFORM_CHANGED" = "true" ]`
   (now further down the recipe) still runs after both blocks have
   executed, since both variables are unconditionally initialized to
   `"false"` before their respective `if` guards regardless of order.
3. **Shell syntax** — the recipe body was extracted (the shebang script
   between `switch role=...:` and the next `[group(...)]` recipe) and
   checked with `bash -n`: passed clean (`SYNTAX_OK`).
4. **Consistency with existing pattern** — the reordered block now sits
   adjacent to its parent selection, matching how the NVIDIA driver-branch
   sub-question is nested directly inside the GPU-variant block
   (`justfile:221-237`).
5. **Build validation (vexos-nix specific)**:
   - `nix flake show --impure` — completed clean, all 30
     `nixosConfigurations` plus `nixosModules` and `packages` enumerated
     with no errors (justfile is not consumed by Nix evaluation, so this
     is expected to be unaffected — confirmed).
   - `sudo nixos-rebuild dry-build` for desktop-amd/nvidia/vm — **not run**.
     This session executes on a Windows host with no NixOS target
     available (WSL Ubuntu, not NixOS); `nixos-rebuild` requires a NixOS
     host with `/etc/nixos/hardware-configuration.nix`, which does not
     exist here. Per project's own risk analysis in the spec, this change
     touches only a plain-text shell script that is never evaluated by
     Nix, so the omission does not affect the correctness of the change
     itself — flagged here as an environment limitation, not skipped by
     choice.
   - `git ls-files hardware-configuration.nix` — empty, confirmed not
     committed.
   - `system.stateVersion` — unchanged in all `configuration-*.nix` files
     (grep confirms all six still read `"25.11"`).
   - No new flake inputs added — N/A.
6. **Security** — no secrets, no permission changes, no new sudo call
   sites (the same two `_features_set` calls exist, just reordered).
7. **Diff size** — `git diff --stat`: `justfile | 100 +++++---` (50
   insertions / 50 deletions), consistent with a pure block relocation of
   ~50 lines.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | N/A | — |
| Consistency | 100% | A |
| Build Success | 90% | A- (flake structure verified; nixos-rebuild dry-build not executable in this environment — see note above) |

**Overall Grade: A (98%)**

## Result

PASS. No refinement cycle needed.
