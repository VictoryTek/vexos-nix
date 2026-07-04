# M-13 — Review & Quality Assurance

Status: Phase 3 (Review) — includes one refinement cycle plus one user-directed scope resolution
Spec: `.github/docs/subagent_docs/M-13_shared_zfs_hostid_spec.md`

## Modified Files

- `hosts/{server,headless-server}-{amd,nvidia,intel,vm}.nix` (8 files) — wrapped each
  `networking.hostId = "<placeholder>";` in `lib.mkDefault`.
- `modules/zfs-server.nix` — changed the rock-bottom fallback from
  `lib.mkDefault "00000000"` to `lib.mkOverride 1500 "00000000"` (see Refinement Cycle
  1), and extended the assertion to reject all 8 committed placeholders, not just
  `"00000000"`.
- `.github/workflows/ci.yml` — added `networking.hostId = "cafebabe";` to the existing
  stub `hardware-configuration.nix` CI already writes for every matrix group (see Scope
  Resolution below).

## Refinement Cycle 1

**Issue found during build validation (CRITICAL):** giving both `zfs-server.nix` and
the host files `lib.mkDefault` for the same `str`-type option produced a genuine
priority conflict (`networking.hostId' has conflicting definition values`) — unlike
list-type options, two different values at the same priority tier for a non-mergeable
type is an error, not a silent pick. Fixed by moving `zfs-server.nix`'s fallback to
`lib.mkOverride 1500` (weaker than `mkDefault`'s 1000), so the host files' own defaults
correctly win over it, with a comment explaining why.

## Scope Resolution: CI conflict

After the refinement above, evaluating `vexos-server-amd`/`vexos-headless-server-amd`
directly surfaced a second, structural issue: CI (`.github/workflows/ci.yml`) evaluates
every server/headless-server config as its own normal validation (forcing all
assertions), and the strengthened assertion now correctly fails on every one of them by
design (they're generic multi-user templates — none can have a "real" per-machine
hostId baked in). Presented three options to the user; they chose to update CI rather
than weaken the fix. Implemented by adding one line to the *existing* stub
`hardware-configuration.nix` heredoc CI already writes before evaluation — that file is
already unconditionally imported by `mkHost` at plain (priority-100) precedence, which
beats both the host files' `mkDefault` (1000) and `zfs-server.nix`'s `mkOverride 1500`
fallback, so no new flake mechanism or per-group conditional step was needed (mirrors
the existing precedent one step further up in the same file: the stateless group's
CI-only password-override fixture).

## Review Findings

1. **Specification Compliance** — matches the spec, with the CI conflict surfaced and
   resolved as an explicit user-directed decision rather than silently worked around.
2. **Best Practices** — correct priority-tier design (host-file default < zfs-server
   rock-bottom fallback < any real override), consistent with how NixOS module priority
   is meant to be used for this exact "several layers of defaults" pattern.
3. **Consistency** — the CI fixture change follows the exact same pattern already
   established in the same file for the stateless group's password fixture.
4. **Maintainability** — the assertion's placeholder list and the CI fixture both carry
   comments explaining their relationship to each other and to the host files.
5. **Completeness** — all 8 host files updated; the assertion catches all of them;
   CI evaluates all 10 affected configs (5 server + 5 headless-server GPU variants)
   successfully with the fixture in place.
6. **Performance** — no change.
7. **Security** — this is a genuine security/data-integrity fix: ZFS's protection
   against importing a pool that's already imported elsewhere previously silently
   never engaged for any unedited deployment of these role/GPU combinations.
8. **API Currency** — n/a, core NixOS module priority semantics.
9. **Build Validation:**
   - Forced-branch test (no override): confirmed the assertion now fires for
     `vexos-server-amd` with a clear message, where it previously silently passed.
   - Forced-branch test (`lib.mkForce "deadbeef"`): confirmed a real override still
     builds cleanly — the mechanism isn't just fail-closed, it's genuinely overridable.
   - Forced-branch test (CI fixture value `"cafebabe"`, matching the exact CI change):
     confirmed both `vexos-server-amd` and `vexos-headless-server-amd` build
     successfully — direct proof the CI fix resolves the conflict, not just a
     theoretical claim about priorities.
   - `nix flake show --impure` — passed.
   - Required desktop targets (`vexos-desktop-amd`, `-nvidia`, `-vm`) evaluated
     cleanly and unaffected (zfs-server.nix isn't imported by those roles).
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED (its own dry-build check is scoped to
     `/etc/nixos/vexos-variant`, absent on this sandbox, so it skips gracefully rather
     than silently passing over a real failure — consistent with every prior preflight
     run this session; the direct `nix eval` tests above are the real verification for
     this specific fix). Same pre-existing WARNs; nothing new.

No CRITICAL or RECOMMENDED issues found after the refinement cycle and CI resolution.

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Returns

- Build result: PASS (after 1 refinement cycle + 1 CI scope resolution)
- **PASS**
