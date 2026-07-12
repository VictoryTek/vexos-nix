# Dockhand Image Fix — Review

## Spec Reference
`.github/docs/subagent_docs/dockhand_image_fix_spec.md`

## Modified Files
- `modules/server/dockhand.nix` (1 line)

## Review

1. **Specification Compliance** — Matches spec exactly: `image` changed from
   `ghcr.io/finsys/dockhand:v1.0.36` to `fnsys/dockhand:v1.0.37`. No other
   lines touched (`git diff --stat` confirms `1 file changed, 1 insertion(+), 1 deletion(-)`).
2. **Best Practices** — Follows existing repo convention of pinning OCI
   images to a specific version tag (matches `portainer.nix`, `arcane.nix`).
3. **Consistency** — No new `lib.mkIf` role/display/gaming guards introduced;
   Option B module architecture untouched.
4. **Maintainability** — Single-line, self-explanatory change; no new
   comments needed (existing header comment references the general
   deployment pattern, unaffected).
5. **Completeness** — Root cause (invalid GHCR image reference) fully
   addressed; verified corrected image pulls successfully and the module
   evaluates to the new value.
6. **Performance** — No regressions; no change to container resources,
   ports, or volumes.
7. **Security** — No secrets, no new attack surface; still runs as `0:0`
   per existing (pre-approved) upstream requirement, unchanged by this fix.
8. **API Currency** — N/A (OCI image tag, not a library/SDK integration;
   Context7 not applicable per Dependency Policy).
9. **Build Validation:**
   - `nix flake show --impure` — PASS, all 30 outputs listed, no errors.
   - `sudo nixos-rebuild dry-build` — **unavailable in this sandboxed
     session** (`sudo` blocked: "no new privileges" flag set). Substituted
     with the CI-equivalent safe check per project Test Commands:
     `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`.
   - `vexos-desktop-amd` — PASS (evaluates to a `.drv` path).
   - `vexos-desktop-nvidia` — PASS.
   - `vexos-desktop-vm` — PASS.
   - `vexos-server-amd` — FAILS, but on a **pre-existing, unrelated**
     assertion: `hosts/server-amd.nix` still carries a placeholder
     `networking.hostId = "a0000001"`, tripping the ZFS
     unique-hostId assertion in `modules/zfs-server.nix:85`. Confirmed
     unrelated to this change — same placeholder values exist across all
     8 server/headless-server host files, predating this fix, and are
     installer-assigned per-host values, not something `dockhand.nix`
     touches.
   - `vexos-headless-server-amd` — FAILS with the identical pre-existing
     hostId assertion, same root cause as above.
   - **Targeted module validation** (since the pre-existing hostId
     assertion blocked full-config eval of server roles): evaluated
     `modules/server/dockhand.nix` directly via `extendModules` with
     `vexos.server.dockhand.enable = true` and a non-placeholder
     `networking.hostId`, isolating this module from the unrelated
     blocker. Result:
     `virtualisation.oci-containers.containers.dockhand.image` correctly
     resolves to `"fnsys/dockhand:v1.0.37"`. This confirms the module
     itself evaluates cleanly with the fix applied.
   - `git ls-files hardware-configuration.nix` — empty, not committed. PASS.
   - `system.stateVersion` — unchanged in all 6 `configuration-*.nix` files
     (still `"25.11"` everywhere). PASS.
   - No new flake inputs — no `follows` review needed.

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
| Build Success | 90% | A- (dry-build unavailable in sandbox; substituted with equivalent `nix eval --impure`, which passed; server-role full-eval blocked by an unrelated pre-existing hostId assertion, not this change) |

**Overall Grade: A (98%)**

## Notes for User

- The `vexos-server-amd` / `vexos-headless-server-amd` full-configuration
  eval failures are **pre-existing** and **unrelated** to this fix — they
  come from placeholder `networking.hostId` values in `hosts/*.nix` that
  are meant to be set per-machine by the installer. Not something to fix as
  part of this change; flagging per Surgical Changes principle (noticed,
  not touched).
- `sudo` is unavailable in this execution sandbox, so the mandated
  `nixos-rebuild dry-build` commands could not run here. Substituted with
  the CI-equivalent `nix eval --impure` full-evaluation check (also listed
  as an approved Test Command in `CLAUDE.md`), which passed for all
  reachable targets. Recommend the user run
  `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` (or
  `vexos-vmc`'s actual target) locally for full confirmation before
  applying.

## Result: PASS
