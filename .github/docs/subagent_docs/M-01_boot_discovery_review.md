# M-01 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-01_boot_discovery_spec.md`

## Modified Files

- `modules/boot-discovery.nix` — ESP type matching now recognizes both the GPT ESP
  GUID and the MBR ESP type code (`ef`), via precise `type=` field extraction instead
  of a loose substring test; `efibootmgr --create`'s previously-swallowed failure
  (`|| true`) now logs the actual success/failure and captured output; updated the
  stale header comment ("GPT tables" → "GPT or MBR").

## Review Findings

1. **Specification Compliance** — both defects from the spec addressed exactly as
   proposed.
2. **Best Practices** — the `if out="$(...)"; then ... else ...; fi` pattern correctly
   handles command failure under `set -euo pipefail` without aborting the script (the
   `if` condition context suppresses `set -e` for that one command, matching bash's
   documented behavior) — the surrounding `set -e` remains intact for the rest of the
   script.
3. **Consistency** — matches the module's existing style (same `log()` helper, same
   `sed`-based field extraction technique already used two lines below for `partuuid`).
4. **Maintainability** — the new inline comment documents the GPT-vs-MBR `sfdisk --dump`
   format difference directly at the point where it matters, so the next person editing
   this doesn't have to rediscover it.
5. **Completeness** — both identified defects fixed; no partial fix.
6. **Performance** — negligible (one extra `sed` invocation per partition line, already
   the same cost class as the existing `partuuid` extraction).
7. **Security** — no change; `efibootmgr` is still only invoked with the same
   parameters, just with its result observed instead of discarded.
8. **API Currency** — n/a (shell script, standard `sfdisk`/`efibootmgr` CLI usage).
9. **Build Validation:**
   - Built the actual `discoveryScript` derivation directly
     (`pkgs.writeShellScript` output) via `nix build --impure --expr ...` and ran
     `bash -n` (syntax OK) and `shellcheck` against the *rendered* script, not just the
     Nix source — only one pre-existing, unrelated info-level finding (SC2012, `ls`
     vs `find`, on a line this change didn't touch).
   - Functional test: fed four synthetic `sfdisk --dump`-style lines (GPT ESP, GPT
     non-ESP, MBR ESP, MBR non-ESP) through the exact new matching expression in
     isolation — all four classified correctly, directly confirming the MBR-detection
     fix works as intended (this is the core claim of the fix, verified concretely
     rather than just "looks right").
   - `nix flake show --impure` — passed.
   - Broader-than-minimum target set evaluated since `boot-discovery.nix` is imported
     by all six roles: `vexos-desktop-amd`, `-nvidia`, `-vm`, `vexos-server-amd`,
     `vexos-headless-server-amd`, `vexos-htpc-amd`, `vexos-stateless-amd`,
     `vexos-vanilla-amd` — all evaluated cleanly.
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs as every
     prior review this session; nothing new.

**Caveat carried forward from the spec, not a review finding**: this fix could not be
validated against real dual-boot hardware in this sandbox (no live diagnostics were
available this session). It addresses two concrete, verifiable defects found by code
inspection — MBR-labeled ESPs being invisible, and `efibootmgr` failures being silently
discarded — but is not a confirmed fix for the user's specific reported failure. If the
symptom persists, the now-real error logging should make the actual cause visible via
`journalctl -u vexos-boot-discovery -b` on the affected machine.

No CRITICAL or RECOMMENDED issues found in the code itself.

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

*Functionality verified via code-level testing (synthetic input, rendered-script lint);
not verified against real dual-boot hardware — see caveat above.

**Overall Grade: A (100%, with the hardware-validation caveat noted)**

## Returns

- Build result: PASS
- **PASS**
