# L-17 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/L-17_plex_todo_recheck_spec.md`

## Modified Files

- `modules/server/plex.nix` — re-dated the TODO to 2026-11, replaced the
  broken tracking issue link with a durable pointer to the upstream module
  source file, clarified the verification method.

## Review Findings

1. **Specification Compliance** — matches the plan's own instruction
   exactly: "verify the upstream Plex module fix; remove the workaround if
   resolved, or re-date with a new target version" — verified (not
   resolved), re-dated.
2. **Best Practices** — didn't trust the TODO's own prescribed verification
   command at face value; recognized it only reflects this repo's own
   `mkForce` output, not upstream state, and instead inspected the actual
   upstream `nixos/modules/services/misc/plex.nix` source directly to get
   a real answer.
3. **Consistency** — n/a, single-file comment update.
4. **Maintainability** — replaced a broken/misleading GitHub issue link
   with a pointer to a specific upstream source file and line pattern,
   which can't go stale the way an issue number can (issues get
   renumbered, closed for unrelated reasons, etc. — confirmed exactly this
   happened with the original link).
5. **Completeness** — addressed both problems found: the expired date and
   the broken tracking reference (the plan only mentioned the date).
6. **Performance** — n/a.
7. **Security** — n/a.
8. **API Currency** — n/a; the finding here *is* about API/behavior
   currency (confirming Plex's upstream module behavior at the current
   pin) — done via direct source inspection, matching the project's
   verification-over-assumption standard.
9. **Real research finding**: the original `Track:` link
   (`nixpkgs#310792`) pointed at a completely unrelated, already-closed
   issue ("goose: 3.19.2 -> 3.20.0"). Searched GitHub for the actual bug
   signature (`__isoc23_sscanf`, libva, glibc mismatch) and found issue
   #468070 with an identical crash signature — but that issue was closed
   as a user-configuration mistake (manually adding `libva` alongside a
   mismatched OS/package version), not as a fix to the module's
   unconditional injection, so it wasn't cited as a "the fix is tracked
   here" replacement — citing it without that caveat would have been
   nearly as misleading as the broken link it would have replaced.
10. **Build Validation:**
    - The edit is entirely inside a `#` comment block; zero
      evaluation-affecting lines touched (the `lib.mkForce ""` line itself
      is unchanged).
    - `nix flake show --impure` — passed.
    - `vexos-server-amd` (the role this file's service module applies to)
      — `.drv` hash **byte-identical** to the value recorded in this
      session's L-15 review, confirming zero effect.
    - Per-target `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`
      for `vexos-desktop-amd`, `-nvidia`, `-vm` — also byte-identical to
      prior recorded values.
    - `git ls-files hardware-configuration.nix` — empty. ✓
    - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs
      as every prior review this session — nothing new.

No CRITICAL or RECOMMENDED issues found.

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100%* | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

*Comment-only change — verified via byte-identical derivation hashes.

**Overall Grade: A (100%)**

## Returns

- Build result: PASS
- **PASS**
