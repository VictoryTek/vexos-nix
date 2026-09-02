# Review — Sync `just available-services` and `just services` via a shared catalog

Spec: `.github/docs/subagent_docs/justfile_service_list_sync_spec.md`

## Modified files

- `justfile`
  - Added `_service_catalog` variable (62 `group|name|description` lines) after
    `_server_service_names`, with a sync-comment on both.
  - `available-services` recipe: replaced 80 hand-written `_hdr`/`_svc` lines
    with a `while IFS='|' read` loop over the catalog. Header/footer `echo`
    lines and `[private]` unchanged.
  - `services` recipe: replaced 14 hand-written `_hdr … _check …` lines with the
    same loop; `_check` helper, `_require-server-role` guard, `SVC_FILE`
    empty-file guard, `set -euo pipefail`, and header line unchanged.

No Nix modules, no `flake.nix`, no `template/`, no scripts touched.

## Validation performed

| Check | Command | Result |
|-------|---------|--------|
| Justfile parses | `just --summary` / `just --evaluate` | PASS — 36 public recipes, no error |
| Catalog evaluates | `just --evaluate _service_catalog` | PASS — 62 lines, groups intact |
| `available-services` output | `just available-services` | PASS — identical grouping/columns to pre-change; now 62 entries incl. grimmory, joplin, searxng |
| `services` body (stubbed SVC_FILE) | simulation script + stub `server-services.nix` | PASS — 62 entries; `✓` for grimmory, joplin, searxng, `arr` (via `arr.sonarr`), `kernel-builder` (→`kernelBuilder`), `nginx-proxy-manager` (→`_`) |
| Lists match | `diff` of catalog names vs `_server_service_names` | PASS — identical, 62 each |
| Apostrophe in a description (`harmonia`) | `replace(_service_catalog, "'", "'\\''")` in the here-string | PASS — `host's store` renders correctly, no shell break |

`just services` itself cannot execute off a NixOS server host (needs
`/etc/nixos/vexos-variant` matching `*server*` and a real
`/etc/nixos/server-services.nix`); its logic was validated by running the exact
recipe body against a stub file.

## Score table

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

## Findings

- **No CRITICAL issues.**
- Note (not actionable here): `service-info`, `_units`, and the health-check URL
  `case` blocks in the `justfile` still hold their own per-service lists. They
  are keyed by service name and degrade gracefully (fall through to a default),
  so they are lower-risk than the two catalog views and were out of scope for
  this request. Worth a follow-up if full unification is desired.
- `_server_service_names` remains hand-maintained. It currently agrees with the
  catalog (verified). Deriving it via `shell(...)` was rejected in the spec as
  more fragile than the drift it prevents; the cross-reference comment is the
  mitigation.

## Result

**PASS** — both commands now render from `_service_catalog`, so they match
exactly by construction. `grimmory`, `joplin`, and `searxng` now appear in
`just services`.
