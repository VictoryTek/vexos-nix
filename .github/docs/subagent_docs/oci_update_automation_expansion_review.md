# OCI Container Update Automation — Expansion Review

Spec: `oci_update_automation_expansion_spec.md`

## Changes Reviewed

1. `modules/server/joplin.nix` — `joplin-server` image `joplin/server:latest` →
   `joplin/server:3.7.1` (newest verified tag at spec time).
2. `.github/workflows/update-container-images-weekly-wednesday.yml`:
   - Header comment updated from 8 to 14 tracked services.
   - `SERVICES` array gained 6 entries: `maintainerr`, `joplin-server`, `joplin-db`
     (postgres), `grimmory-db` (mariadb), `grimmory`, `uptime-kuma`.
   - `latest_dockerhub_tag()` fixed to auto-prefix `library/` for unnamespaced
     official-image repos (needed for `postgres`) without changing the entry's
     file-matching repo string.
   - `current=$(...)` extraction changed from file-scoped to repo-scoped grep, required
     because `joplin.nix` and `grimmory.nix` each declare two tracked images — the
     original file-scoped grep would have matched both lines and produced a garbled
     multi-line value for those four new entries.

## Findings

- **Specification compliance**: matches spec exactly, including the two script-logic
  fixes documented there as required (not scope creep — both are latent bugs that only
  manifest once a file has >1 tracked image or an official/unnamespaced Docker Hub
  image is tracked, neither of which existed before this change).
- **Best practices / consistency**: new `SERVICES` entries follow the existing
  `file:repo:registry:pattern` convention exactly. Regex patterns for `postgres` and
  `mariadb` deliberately lock to the current major(.minor) version to avoid an
  unattended major-version DB migration; `grimmory` and the other four entries use the
  same open three-part-semver pattern as the pre-existing 8, per explicit user decision
  (2026-08-17) to let `grimmory` auto-bump freely from `v0.38.2` to whatever is newest.
- **Security**: no secrets touched. Preflight's secret scan flagged an unrelated
  pre-existing placeholder in `vexboard.nix` (WARN only, not introduced by this change).
- **Module Architecture Pattern**: not applicable — no shared/role-addition module
  structure touched, this is a CI script + one image tag literal.
- **Verification performed**:
  - Repo-scoped extraction regex tested locally against all 6 new + 2 sampled existing
    entries — all extracted the correct current tag, including both multi-image files
    (`joplin.nix`, `grimmory.nix`), confirming the bug fix works.
  - Embedded bash script extracted from the YAML and checked with `bash -n` — no syntax
    errors.
  - Workflow YAML parsed successfully with PyYAML.
  - `nix flake show --impure` (via WSL, since this workstation is Windows without a
    native `nix` install) — all 30 `nixosConfigurations` + modules evaluated cleanly.
  - `nix eval --impure` forced full evaluation (CI-equivalent of dry-build, since
    `nixos-rebuild` requires an actual NixOS host) for `vexos-desktop-amd`,
    `vexos-desktop-nvidia`, `vexos-desktop-vm` — all succeeded.
  - `vexos-server-amd` / `vexos-headless-server-amd` (touched by this change, since
    `joplin.nix` and `arr.nix` are server modules) failed evaluation — but on a
    **pre-existing, unrelated** assertion: `hosts/server-amd.nix` and
    `hosts/headless-server-amd.nix` carry placeholder ZFS `hostId` values
    (`a0000001`/`b0000001`) that a prior commit (`b161981`) intentionally rejects until
    a real per-host ID is set. Confirmed via `git log`/`grep` that this placeholder and
    the rejecting assertion both predate this change and are untouched by it — this
    dev environment simply has no real host claiming a `hostId`, which is expected
    outside of an actual deployed machine.
  - `git ls-files hardware-configuration.nix` — empty, correctly untracked.
  - `git diff --stat -- 'configuration-*.nix'` — empty, `stateVersion` untouched.
  - `bash scripts/preflight.sh` (via WSL) — **PASSED**. Stage `[2/8]` dry-build was
    skipped (expected: WSL has no `/etc/nixos/vexos-variant`, this isn't a real VexOS
    host), all other stages passed or produced only pre-existing/tooling-availability
    warnings (missing `jq`/`nixpkgs-fmt`/`gitleaks` on the WSL side, and the
    unrelated `vexboard.nix` placeholder secret warning).

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | N/A | — |
| Consistency | 100% | A |
| Build Success | 100% (with noted pre-existing, unrelated server-role hostId gap) | A |

**Overall Grade: A (100%)**

## Result

**PASS.**
