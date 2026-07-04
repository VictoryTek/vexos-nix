# M-22 — Review & Quality Assurance

Status: Phase 3 (Review) — scope expanded once, by user request
Spec: `.github/docs/subagent_docs/M-22_oci_container_latest_pins_spec.md`

## Modified Files

- `modules/server/{portainer,homepage,stirling-pdf,authelia,nginx-proxy-manager,dockhand,dozzle}.nix`
  — each `image = "...:latest"` pinned to a verified current stable tag.
- `.github/workflows/update-container-images.yml` (new) — scheduled workflow
  (Wednesdays) that checks each image's registry for a newer matching tag and
  rewrites the pin in place, committing directly to main (matching
  `update-flake-lock.yml`'s existing style) only when something actually changed.

## Scope Note

The literal MASTER_PLAN fix (pin to version tags) was implemented, but the user
pushed back on the tradeoff — pinning trades reproducibility for a manual bump
burden — and asked for automated weekly version checks that update the pins
themselves, closing the gap between "fully reproducible" and "stays current."
Addressed by adding the new workflow rather than either leaving `:latest` or leaving
the pins to go stale indefinitely.

## Review Findings

1. **Specification Compliance** — all 7 images pinned to verified tags; the
   automation addition matches what the user asked for.
2. **Best Practices** — version tags were verified against live registry data
   (Docker Hub's public tags API, GitHub releases, and the live GHCR package page for
   `homepage`) rather than guessed; the `dockhand` image reference itself was
   specifically investigated and confirmed legitimate via the project's own hosted
   manual before pinning a version to it, after an initial check (the Finsys GitHub
   org's package listing) raised a real doubt.
3. **Consistency** — the new workflow mirrors `update-flake-lock.yml`'s exact
   conventions: direct commit to main (not a PR), `github-actions[bot]` identity,
   skip-if-unchanged logic, `workflow_dispatch` for manual runs.
4. **Maintainability** — the workflow's per-service table (file/repo/registry/regex)
   is self-documenting; adding an 8th pinned service later is a one-line addition to
   that table, not new logic.
5. **Completeness** — all 7 cited images addressed; the new workflow covers all 7
   symmetrically (not just the two the MASTER_PLAN said to prioritize "at minimum").
6. **Performance** — n/a.
7. **Security** — pinning itself is a security-relevant fix (no more silent
   self-updates); the new workflow only ever writes version-pin strings it parsed from
   registry JSON via `jq`, never executes anything from the network response.
8. **API Currency** — n/a (Docker registry APIs, not a project dependency).
9. **Build Validation:**
   - `yamllint` (via `nix shell nixpkgs#yamllint`) — no findings against the new
     workflow file.
   - Isolated shell tests of the extraction/bump logic: confirmed correct behavior for
     both the plain-Docker-Hub image format and the `ghcr.io/`-prefixed format,
     confirmed the "no change needed" path correctly leaves `changed_files` empty
     (which gates the commit step).
   - Isolated regex tests against the *actual* tag lists fetched earlier for authelia,
     dozzle, stirling-pdf, and nginx-proxy-manager: each pattern correctly filters out
     branch/PR/variant noise and `sort -V | tail -1` selects the exact same version
     already verified manually.
   - Forced-branch Nix test: enabled all 7 services simultaneously (plus podman, to
     exercise the M-02 interaction) and confirmed every container's `image` attribute
     resolves to its pinned tag, with the full `toplevel` building successfully.
   - `nix flake show --impure` — passed.
   - Required targets (`vexos-desktop-amd`, `-nvidia`, `-vm`) evaluated cleanly;
     `vexos-server-amd`/`-headless-server-amd` hit the pre-existing, unrelated M-13
     hostId assertion on their own (expected without the CI fixture override; not
     re-litigated here).
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs as every
     prior review this session; nothing new.

**Caveat, not a review finding**: the GHCR anonymous-token lookup path (used for
`homepage` and `dockhand`) could not be end-to-end tested from this sandboxed session
due to its own restricted network egress (a direct `curl` to `ghcr.io/token` failed
here). This is the standard, widely-used anonymous bearer-token flow for public GHCR
images and GitHub Actions runners have unrestricted internet access, so it's expected
to work there — flagged as unverified-in-this-session rather than claimed as tested,
per the "verify before asserting" principle.

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

*The GHCR lookup path is untested end-to-end in this session — see caveat above.

**Overall Grade: A (100%, with the GHCR-lookup caveat noted)**

## Returns

- Build result: PASS
- **PASS**
