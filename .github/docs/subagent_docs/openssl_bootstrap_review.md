# Review: Bootstrap openssl in stateless installer scripts

Spec: `.github/docs/subagent_docs/openssl_bootstrap_spec.md`

## Files Reviewed
- `scripts/stateless-setup.sh`
- `scripts/migrate-to-stateless.sh`

## Findings

1. **Specification Compliance** — Both abort blocks replaced with the
   bootstrap block exactly as specified; both `openssl passwd -6 -stdin`
   call sites now use `"$OPENSSL"`. Indentation in
   `migrate-to-stateless.sh` matches the surrounding `else` branch.
2. **Best Practices** — Mirrors the established git-bootstrap pattern in
   `install.sh` (commit 59bd971), including
   `--extra-experimental-features 'nix-command flakes'` and
   `--no-link --print-out-paths`. Uses `nixpkgs#openssl.bin` to guarantee
   a single output path (verified: resolves to
   `/nix/store/...-openssl-3.6.2-bin`, which contains `bin/openssl`).
3. **Consistency** — Shell-only change; no Nix modules touched, so the
   Module Architecture Pattern (Option B) is unaffected. No `lib.mkIf`
   guards introduced.
4. **Maintainability** — Comments reference the install.sh precedent.
5. **Completeness** — Both stateless entry points (fresh ISO install and
   in-place migration) covered.
6. **Performance** — Binary-cache fetch only when openssl is missing.
7. **Security** — No secrets, no plaintext credentials; password handling
   unchanged (still hashed via `openssl passwd -6 -stdin`, never echoed).
8. **API Currency** — No new dependency or versioned library API; Context7
   not applicable (runtime binary fetched from nixpkgs binary cache).
9. **Build Validation**
   - `bash -n` passes on both scripts.
   - `nix eval --raw 'nixpkgs#openssl.bin.outPath'` resolves to a single
     store path.
   - `${CYAN}` confirmed defined in both scripts.
   - No `configuration-*.nix`, `flake.nix`, or module files modified, so
     `system.stateVersion`, flake inputs, and `hardware-configuration.nix`
     constraints are untouched (full preflight run in Phase 6).
   - Failure mode preserved: both scripts run `set -euo pipefail`, so a
     failed binary-cache fetch (no network) still aborts the script.

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
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Result: PASS
