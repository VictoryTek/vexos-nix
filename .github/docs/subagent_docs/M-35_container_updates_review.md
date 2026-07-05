# M-35 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-35_container_updates_spec.md`

**Process note:** the user directly challenged the plan's premise
mid-session ("didn't we pin OCI containers already?" / "I'd rather updates
ride the same `just update`/`deploy`/`update-all` commands"), which is
exactly right and reshaped this item's scope before any implementation
started — re-verified rather than assumed, confirmed both points, and scoped
accordingly.

## Modified Files

- `modules/server/arcane.nix` — pinned `image` from `:latest` to `:v1.19.4`
  (the one straggler M-22's original pinning pass missed, since Arcane was
  added after that pass).
- `.github/workflows/update-container-images.yml` — added Arcane to the
  tracked-services list (GHCR, same tag pattern as `homepage`/`dockhand`);
  updated header comment count/list and added a line documenting why no
  separate update recipe exists.

## Review Findings

1. **Specification Compliance** — matches the user-corrected scope exactly:
   no `just update-containers` recipe added; the one remaining `:latest`
   pinned; existing automation extended to cover it.
2. **Best Practices** — verified the actual currently-published GHCR tags
   for Arcane directly (not guessed) — `v1.19.4` is the only real semver
   release tag; other tags are floating majors, prerelease channels, or
   digest pins, matching this repo's existing semver-pin convention.
3. **Consistency** — the new `update-container-images.yml` entry uses the
   identical GHCR tag-regex style already used for `homepage`/`dockhand`
   (`^v[0-9]+\.[0-9]+\.[0-9]+\$`), not a new one-off pattern.
4. **Maintainability** — the workflow's header comment now explicitly states
   why no separate pull/restart recipe exists, preventing a future
   contributor from re-proposing the same thing this session's user
   correctly pushed back on.
5. **Completeness** — grepped every `modules/server/*.nix` for
   `image = ".*:latest"` after the fix — zero remaining matches.
6. **Performance** — n/a.
7. **Security** — pinning a previously-floating tag is a net improvement
   (reproducibility), same category as M-22's original 7 pins.
8. **API Currency** — verified GHCR's actual tag list via the real registry
   API (anonymous bearer-token flow, same approach used for M-22's original
   research) rather than assuming a version number.
9. **Build Validation:**
   - Extracted the workflow's embedded bash script and validated: YAML
     parses cleanly (`pyyaml`), `bash -n` syntax check passes.
   - **End-to-end dry run** of the grep/sed logic against the real
     `arcane.nix`: `current=$(grep -oP ...)` correctly extracts `v1.19.4`;
     simulated a bump to `v1.19.5` via the exact `sed` command the workflow
     uses — produced the correct rewritten `image` line.
   - `nix flake show --impure` — passed.
   - **Integration check** via `extendModules`: enabled `vexos.server.arcane`
     on `vexos-server-amd` and confirmed
     `virtualisation.oci-containers.containers.arcane.image` evaluates to
     exactly `ghcr.io/getarcaneapp/manager:v1.19.4`.
   - Per-target `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`
     for `vexos-desktop-amd`, `-nvidia`, `-vm` — evaluated cleanly.
   - `vexos-server-amd` / `vexos-headless-server-amd` — evaluated via
     `extendModules`; `.drv` hashes identical to the values recorded in
     M-33/M-34's own reviews (Arcane is disabled by default, so this change
     doesn't affect the default server-role closure).
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs
     as every prior review this session — nothing new.

No CRITICAL or RECOMMENDED issues found.

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

- Build result: PASS
- **PASS**
